import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/microsoft_auth_service.dart';
import '../services/microsoft_calendar_service.dart';
import 'add_lecture_screen.dart';

import '../services/attendance_service.dart'; // for attendance
import '../services/attendance_totals.dart';
import 'package:absherk/services/noti_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class _CalendarPalette {
  static const Color gradientStart = Color(0xFF0092A5);
  static const Color gradientEnd = Color(0xFF0E1D6F);
  static const Color cardGradientStart = Color(0xFFF1F7FF);
  static const Color cardGradientEnd = Color(0xFFE5F1FF);
  static const Color cardBorder = Color(0xFFA5C2F5);
  static const Color textStrong = Color(0xFF122448);
  static const Color textMuted = Color(0xFF4D5C7C);
  static const Color accentPrimary = Color(0xFF4C6EF5);
  static const Color accentSecondary = Color(0xFF5AD7C0);
  static const Color chipBackground = Color(0xFFE3EDFF);
  static const Color chipText = Color(0xFF2F4FA2);
  static const Color headerStrong = Color(0xFFF1F9FF);
  static const Color headerMuted = Color(0xCCF1F9FF);
  static const Color headerChipBackground = Color(0x40FFFFFF);
  static const Color headerChipText = Color(0xFFEFF6FF);
  static const Color indicatorInactive = Color(0x66FFFFFF);
  static const Color iconOnGradient = Colors.white;
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Duration _calendarWindowRange = Duration(days: 210);

  // Cached formatters (faster than recreating)
  static final DateFormat _dayOfWeekFmt = DateFormat('EEEE');
  static final DateFormat _fullDateFmt = DateFormat('MMMM d, yyyy');
  static final DateFormat _timeFmt = DateFormat('hh:mm a');

  // Semester start from service
  late final DateTime _calendarWindowStart =
      MicrosoftCalendarService.resolveSemesterStart();

  MicrosoftAccount? _account;
  List<MicrosoftCalendarEvent> _events = <MicrosoftCalendarEvent>[];

  // Fast per-day index
  Map<DateTime, List<MicrosoftCalendarEvent>> _eventsByDay = {};
  List<DateTime> _orderedDays = <DateTime>[];

  PageController? _pageController;
  int _currentPage = 0;
  bool _isLoading = false;
  String? _error;

  // Local cache so icons flip immediately after marking without waiting for Firestore
  final Set<String> _recentlyMarkedAbsent = <String>{};

  // Live absence map & listeners
  StreamSubscription<QuerySnapshot>? _absencesSub;
  final Map<String, String> _absenceByEventId = {}; // eventId -> 'absent'
  bool _absencesReady = false;

  // Debounced schedule refresh
  StreamSubscription? _scheduleSub;
  Timer? _scheduleDebounce;

  @override
  void initState() {
    super.initState();
    _listenScheduleChanges();
    _listenAbsences();
    _loadCalendar(interactive: false);
  }

  @override
  void dispose() {
    _scheduleDebounce?.cancel();
    _scheduleSub?.cancel();
    _absencesSub?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _listenScheduleChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _scheduleSub?.cancel();
    _scheduleSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('schedule')
        .snapshots()
        .listen((_) {
      _scheduleDebounce?.cancel();
      _scheduleDebounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted && !_isLoading) {
          _loadCalendar(interactive: false, showSpinner: false);
        }
      });
    });
  }

  void _listenAbsences() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _absencesSub?.cancel();
    _absencesSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('absences')
        .snapshots()
        .listen((snap) {
      _absenceByEventId.clear();
      for (final d in snap.docs) {
        final status = (d.data()['status'] ?? '').toString();
        if (status.isNotEmpty) {
          _absenceByEventId[d.id] = status;
        }
      }
      // Reconcile local optimistic cache with server: if an absence was deleted,
      // ensure the UI icon flips back to "record absence" by clearing it here.
      if (_recentlyMarkedAbsent.isNotEmpty) {
        final toRemove = _recentlyMarkedAbsent
            .where((id) => _absenceByEventId[id] != 'absent')
            .toList();
        for (final id in toRemove) {
          _recentlyMarkedAbsent.remove(id);
        }
      }
      if (mounted) setState(() => _absencesReady = true);
    });
  }

  Future<void> _loadCalendar({
    bool interactive = false,
    bool showSpinner = true,
  }) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }

    try {
      // Ensure account (once)
      final account = MicrosoftAuthService.currentAccount ??
          await MicrosoftAuthService.ensureSignedIn(
            interactive: interactive,
          );

      if (!mounted) return;

      if (account == null) {
        final previousController = _pageController;
        setState(() {
          _account = null;
          _events = <MicrosoftCalendarEvent>[];
          _eventsByDay.clear();
          _orderedDays.clear();
          _currentPage = 0;
          _pageController = null;
          _isLoading = false;
        });
        previousController?.dispose();
        AttendanceTotals.instance.clear();
        return;
      }

      // Fetch & sort
      final fetchedEvents = await MicrosoftCalendarService.fetchUpcomingEvents(
        account,
        start: _calendarWindowStart,
        range: _calendarWindowRange,
      );

      if (!mounted) return;

      final events = List<MicrosoftCalendarEvent>.from(fetchedEvents);
      events.sort((a, b) {
        final aStart = a.start ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bStart = b.start ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aStart.compareTo(bStart);
      });

      // Build fast per-day index
      _rebuildIndex(events);

      // Decide day keys for paging (lightweight + small padding)
      final dayKeys = _orderedDays.isEmpty
          ? _extractDayKeysLight(events)
          : List<DateTime>.from(_orderedDays);

      final initialIndex = dayKeys.isEmpty ? 0 : _resolveInitialPage(dayKeys);

      final previousController = _pageController;
      final newController =
          dayKeys.isEmpty ? null : PageController(initialPage: initialIndex);

      setState(() {
        _account = account;
        _events = events;
        _currentPage = dayKeys.isEmpty ? 0 : initialIndex;
        _pageController = newController;
        _isLoading = false;
      });

      previousController?.dispose();
      _publishTotals();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _rebuildIndex(List<MicrosoftCalendarEvent> events) {
    final map = <DateTime, List<MicrosoftCalendarEvent>>{};
    for (final e in events) {
      final s = e.start;
      if (s == null) continue;
      final d = DateTime(s.year, s.month, s.day);
      (map[d] ??= <MicrosoftCalendarEvent>[]).add(e);
    }
    for (final list in map.values) {
      list.sort((a, b) => (a.start ?? DateTime(0))
          .compareTo(b.start ?? DateTime(0)));
    }
    _eventsByDay = map;
    _orderedDays = _eventsByDay.keys.toList()..sort();
  }

  Future<void> _handleRefresh() {
    return _loadCalendar(interactive: false, showSpinner: false);
  }

  Future<void> _openAddLecture() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddLectureScreen()),
    );
    if (!mounted) return;
    await _loadCalendar(interactive: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('My Schedule'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton:
          (_account != null && _events.isNotEmpty && !_isLoading)
              ? _buildAddSectionButton()
              : null,
      body: _buildBody(),
    );
  }

  Widget _buildAddSectionButton({
    EdgeInsetsGeometry padding = const EdgeInsets.only(right: 16, bottom: 12),
    double width = 152,
  }) {
    return Padding(
      padding: padding,
      child: Material(
        color: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x334C6EF5),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _openAddLecture,
          child: Ink(
            height: 54,
            width: width,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              gradient: LinearGradient(
                colors: <Color>[
                  _CalendarPalette.accentPrimary,
                  _CalendarPalette.accentSecondary,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.school_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Add Section',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _decorateBackground(Widget child) {
    return Container(
      constraints: const BoxConstraints.expand(),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            _CalendarPalette.gradientStart,
            _CalendarPalette.gradientEnd,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _decorateBackground(
        const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return _decorateBackground(
        _ErrorView(
          message: _error!,
          onRetry: () => _loadCalendar(interactive: false),
        ),
      );
    }

    if (_account == null) {
      return _decorateBackground(
        _SignInPrompt(onPressed: () => _loadCalendar(interactive: true)),
      );
    }

    if (_events.isEmpty) {
      return _buildEmptyState();
    }

    return _buildCalendarPager();
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return _decorateBackground(
      RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 64,
              color: _CalendarPalette.accentPrimary,
            ),
            const SizedBox(height: 24),
            Text(
              'Build your calendar',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Tap "Add Section" to start crafting your schedule.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.center,
              child: _buildAddSectionButton(
                padding: const EdgeInsets.only(bottom: 24),
                width: 168,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarPager() {
    final controller = _pageController;
    final dayKeys = _orderedDays.isEmpty
        ? _extractDayKeysLight(_events)
        : _orderedDays;

    if (controller == null || dayKeys.isEmpty) {
      return _buildEmptyState();
    }

    var pageIndex = _currentPage;
    if (pageIndex < 0) {
      pageIndex = 0;
    } else if (pageIndex >= dayKeys.length) {
      pageIndex = dayKeys.length - 1;
    }

    final currentDay = dayKeys[pageIndex];
    final currentDayEvents = _eventsForDayFast(currentDay);
    final theme = Theme.of(context);
    final isToday = _isSameDay(currentDay, DateTime.now());

    return _decorateBackground(
      SafeArea(
        bottom: true,
        minimum: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed:
                        pageIndex > 0 ? () => _goToPage(pageIndex - 1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    color: _CalendarPalette.iconOnGradient,
                    splashRadius: 24,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _dayOfWeekFmt.format(currentDay),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _CalendarPalette.headerStrong,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fullDateFmt.format(currentDay),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _CalendarPalette.headerMuted,
                          ),
                        ),
                        if (isToday)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _CalendarPalette.headerChipBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Today',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _CalendarPalette.headerChipText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: pageIndex < dayKeys.length - 1
                        ? () => _goToPage(pageIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    color: _CalendarPalette.iconOnGradient,
                    splashRadius: 24,
                  ),
                ],
              ),
            ),
            if ((!isToday &&
                    dayKeys.any((day) => _isSameDay(day, DateTime.now()))) ||
                currentDayEvents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (currentDayEvents.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: _CalendarPalette.headerMuted,
                        ),
                        onPressed: () => _confirmAbsenceAllDay(currentDay),
                        icon: const Icon(
                          Icons.event_busy_rounded,
                          color: _CalendarPalette.headerMuted,
                        ),
                        label: Text(
                          'Absence All Day',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _CalendarPalette.headerMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (currentDayEvents.isNotEmpty &&
                        !isToday &&
                        dayKeys.any((day) => _isSameDay(day, DateTime.now())))
                      const SizedBox(width: 12),
                    if (!isToday &&
                        dayKeys.any((day) => _isSameDay(day, DateTime.now())))
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: _CalendarPalette.headerStrong,
                        ),
                        onPressed: _jumpToToday,
                        icon: const Icon(
                          Icons.today_rounded,
                          color: _CalendarPalette.headerStrong,
                        ),
                        label: Text(
                          'Jump to today',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _CalendarPalette.headerStrong,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: dayKeys.length,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, pageIndex) {
                  final day = dayKeys[pageIndex];
                  final dailyEvents = _eventsForDayFast(day);
                  return _buildDayPage(day, dailyEvents);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDayPage(DateTime day, List<MicrosoftCalendarEvent> events) {
    final theme = Theme.of(context);
    final storageKey = 'day-${day.toIso8601String()}';

    if (events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        child: ListView(
          key: PageStorageKey(storageKey),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          children: [
            const Icon(
              Icons.emoji_emotions_outlined,
              size: 52,
              color: Color.fromARGB(255, 255, 255, 255),
            ),
            const SizedBox(height: 18),
            Text(
              'No classes scheduled',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color.fromARGB(255, 246, 248, 250),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Enjoy your day or add a new section to stay ahead.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color.fromARGB(255, 251, 251, 251),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.separated(
        key: PageStorageKey(storageKey),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: events.length,
        itemBuilder: (context, index) => _buildEventCard(events[index]),
        separatorBuilder: (context, index) => const SizedBox(height: 16),
      ),
    );
  }

  Widget _buildEventCard(MicrosoftCalendarEvent event) {
    final theme = Theme.of(context);
    final subject = event.subject.isNotEmpty ? event.subject : 'Untitled event';
    final location = event.location?.trim() ?? '';
    final timeLabel = _formatEventTime(event);

    final bool isFutureDay = (event.start != null &&
        DateTime(event.start!.year, event.start!.month, event.start!.day)
            .isAfter(DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        )));

    final bool isAbsent = _isAbsentCached(event.id);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: null, // Recording absence is via the icon only
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: <Color>[
                _CalendarPalette.cardGradientStart,
                _CalendarPalette.cardGradientEnd,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: _CalendarPalette.cardBorder.withOpacity(0.55),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _CalendarPalette.cardBorder.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: <Color>[
                        _CalendarPalette.accentPrimary,
                        _CalendarPalette.accentSecondary,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _CalendarPalette.textStrong,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: _CalendarPalette.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timeLabel,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _CalendarPalette.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (location.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _CalendarPalette.chipBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: _CalendarPalette.chipText,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  location,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _CalendarPalette.chipText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isFutureDay) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip:
                        isAbsent ? 'Absence recorded' : 'Record absence',
                    visualDensity: VisualDensity.compact,
                    icon: isAbsent
                        ? const Icon(Icons.person_off_outlined)
                        : const Icon(Icons.person_outline),
                    color: isAbsent
                        ? Colors.redAccent
                        : _CalendarPalette.accentPrimary,
                    onPressed: () async {
                      await _confirmAbsenceToggle(event, isAbsent: isAbsent);
                      // Local instant flip
                      _absenceByEventId[event.id] = 'absent';
                      _recentlyMarkedAbsent.add(event.id);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<DateTime> _extractDayKeysLight(List<MicrosoftCalendarEvent> events) {
    // If no events: show current week
    if (events.isEmpty) {
      final today = _normalizeDate(DateTime.now());
      final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
      return List<DateTime>.generate(
        7,
        (i) => _normalizeDate(startOfWeek.add(Duration(days: i))),
      )..sort();
    }

    final set = <DateTime>{};
    for (final e in events) {
      final s = e.start;
      if (s == null) continue;
      set.add(_normalizeDate(s));
    }
    final days = set.toList()..sort();

    // Small padding around data for a nicer pager experience
    final List<DateTime> padded = [];
    final first = days.first.subtract(const Duration(days: 3));
    final last = days.last.add(const Duration(days: 3));
    for (DateTime d = _normalizeDate(first);
        !d.isAfter(last);
        d = d.add(const Duration(days: 1))) {
      padded.add(d);
    }
    return padded;
  }

  List<MicrosoftCalendarEvent> _eventsForDayFast(DateTime day) {
    final d = _normalizeDate(day);
    return _eventsByDay[d] ?? const <MicrosoftCalendarEvent>[];
  }

  Widget _buildPageIndicators() {
    final dayKeys = _orderedDays.isEmpty
        ? _extractDayKeysLight(_events)
        : _orderedDays;

    if (dayKeys.length <= 1) {
      return const SizedBox(height: 8);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(dayKeys.length, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: isActive ? 20 : 8,
          decoration: BoxDecoration(
            color: isActive
                ? _CalendarPalette.headerStrong
                : _CalendarPalette.indicatorInactive,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  int _resolveInitialPage(List<DateTime> days) {
    if (days.isEmpty) return 0;
    final today = _normalizeDate(DateTime.now());
    final todayIndex = days.indexWhere((day) => _isSameDay(day, today));
    if (todayIndex != -1) return todayIndex;
    for (var i = 0; i < days.length; i++) {
      if (days[i].isAfter(today)) return i;
    }
    return days.length - 1;
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  void _goToPage(int index) {
    final controller = _pageController;
    final dayKeys = _orderedDays.isEmpty
        ? _extractDayKeysLight(_events)
        : _orderedDays;
    if (controller == null) return;
    if (index < 0 || index >= dayKeys.length) return;
    controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToToday() {
    final dayKeys = _orderedDays.isEmpty
        ? _extractDayKeysLight(_events)
        : _orderedDays;

    final todayIndex = dayKeys.indexWhere(
      (day) => _isSameDay(day, DateTime.now()),
    );
    if (todayIndex != -1) {
      _goToPage(todayIndex);
    }
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatEventTime(MicrosoftCalendarEvent event) {
    if (event.isAllDay) return 'All day';
    final start = event.start;
    final end = event.end;
    if (start == null) return 'Time not specified';
    final startLabel = _timeFmt.format(start);
    if (end == null || start.isAtSameMomentAs(end)) return startLabel;
    return '$startLabel - ${_timeFmt.format(end)}';
  }

  /// Extract a course code from the event subject, e.g. "CS101 – Lecture 5".
  String _resolveCourseId(MicrosoftCalendarEvent e) {
    final s = (e.subject).toUpperCase();
    final m = RegExp(r'[A-Z]{2,}\s?\d{2,}').firstMatch(s); // CS101 or CS 101
    return (m?.group(0)?.replaceAll(' ', '')) ?? 'UNASSIGNED';
  }

  bool _isAbsentCached(String eventId) =>
      _absenceByEventId[eventId] == 'absent' ||
      _recentlyMarkedAbsent.contains(eventId);

  /// Recompute absence % for a course and show a SnackBar warning if > 20%.
  Future<void> _recomputeAndWarn(String courseId) async {
    final courseEvents =
        _events.where((e) => _resolveCourseId(e) == courseId).toList();
    if (courseEvents.isEmpty) return;

    Map<String, String> byEvent;
    try {
      byEvent = await AttendanceService.getCourseExceptions(courseId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update absence for $courseId: $error'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    int _durationMinutes(MicrosoftCalendarEvent e) {
      final start = e.start;
      final end = e.end;
      if (start == null) return 0;
      final dtEnd =
          (end == null || !end.isAfter(start)) ? start.add(const Duration(minutes: 1)) : end;
      final mins = dtEnd.difference(start).inMinutes;
      return mins <= 0 ? 1 : mins;
    }

    int totalMinutes = 0;
    int absentMinutes = 0;
    int totalEvents = courseEvents.length;
    int absentEvents = 0;

    for (final e in courseEvents) {
      final m = _durationMinutes(e);
      totalMinutes += m;
      if (byEvent[e.id] == 'absent') {
        absentMinutes += m;
        absentEvents += 1;
      }
    }

    if (totalMinutes == 0 || !mounted) return;

    final pct = absentMinutes * 100.0 / totalMinutes;

    final msg =
        'Your absence just increased in $courseId absent $absentEvents of $totalEvents classes (${pct.toStringAsFixed(1)}%)\n Try to make the next class!';

    if (pct > 20) {
      // ignore: unawaited_futures
      NotiService.showAbsenceAlert(courseId, pct);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pct > 20 ? 'Warning: $msg - over 20%!' : msg,
          textAlign: TextAlign.center,
        ),
        backgroundColor: pct > 20 ? Colors.red : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _confirmAbsenceAllDay(DateTime day) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(day.year, day.month, day.day);
    if (target.isAfter(today)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You can only record absence for today or past classes.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final dayLabel = DateFormat('EEE, MMM d, yyyy').format(target);
    final totalCount = _eventsForDayFast(target).length;
    if (totalCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No classes scheduled for this day.')),
      );
      return;
    }

    // If every class is already marked absent, notify and exit.
    try {
      final allAbsent = await _areAllEventsAbsentForDay(target);
      if (allAbsent) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Absence already recorded for all classes this day.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
    } catch (_) {
      // Proceed even if check fails.
    }

    // Compute how many are pending to mark (not already absent)
    int pendingCount = totalCount;
    try {
      pendingCount = await _countPendingAbsencesForDay(target);
    } catch (_) {
      pendingCount = totalCount;
    }
    if (pendingCount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Absence already recorded for all classes this day.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Absent all day'),
            content: Text(
              'Record absence for $pendingCount classes on\n$dayLabel?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mark all'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    await _markAbsenceAllDay(target);
  }

  Future<void> _markAbsenceAllDay(DateTime day) async {
    final events = _eventsForDayFast(day);
    if (events.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final Set<String> changedCourses = <String>{};
    int newMarks = 0;
    int skipped = 0;

    for (final e in events) {
      final start = e.start ?? day;
      final end = e.end ?? start.add(const Duration(minutes: 1));
      final courseId = _resolveCourseId(e);
      try {
        // Skip if already marked absent for this event
        final alreadyAbsent = await _isEventAlreadyAbsent(e.id);
        if (alreadyAbsent) {
          skipped += 1;
          continue;
        }
        await AttendanceService.mark(
          courseId: courseId,
          eventId: e.id,
          status: 'absent',
          title: e.subject.isNotEmpty ? e.subject : 'Lecture',
          start: start,
          end: end,
        );
        _absenceByEventId[e.id] = 'absent';
        _recentlyMarkedAbsent.add(e.id);
        changedCourses.add(courseId);
        newMarks += 1;
      } catch (_) {
        // Continue with other events even if one fails
      }
    }

    if (!mounted) return;
    if (newMarks == 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Absence already recorded for all classes this day.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    } else if (skipped > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Recorded absence for $newMarks classes ($skipped already recorded).',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
  messenger.showSnackBar(
    SnackBar(
      content: Text('Recorded absence for $newMarks classes.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}


    // Recompute and warn only for courses that actually changed
    for (final c in changedCourses) {
      try {
        await _recomputeAndWarn(c);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<bool> _isEventAlreadyAbsent(String eventId) async {
    // Prefer live map; fallback to Firestore only if needed
    if (_absenceByEventId[eventId] == 'absent' ||
        _recentlyMarkedAbsent.contains(eventId)) {
      return true;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _recentlyMarkedAbsent.contains(eventId);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('absences')
          .doc(eventId)
          .get();
      final status = (snap.data()?['status'] ?? '').toString();
      final isAbsent = snap.exists && status == 'absent';
      if (!isAbsent) {
        _recentlyMarkedAbsent.remove(eventId);
      }
      return isAbsent || _recentlyMarkedAbsent.contains(eventId);
    } catch (_) {
      // Network/permission error: best effort fallback to local cache
      return _recentlyMarkedAbsent.contains(eventId);
    }
  }

  Future<bool> _areAllEventsAbsentForDay(DateTime day) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final events = _eventsForDayFast(day);
    if (events.isEmpty) return false;
    for (final e in events) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('absences')
            .doc(e.id)
            .get();
        final status = (snap.data()?['status'] ?? '').toString();
        if (!snap.exists || status != 'absent') {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<int> _countPendingAbsencesForDay(DateTime day) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;
    final events = _eventsForDayFast(day);
    if (events.isEmpty) return 0;
    int pending = 0;
    for (final e in events) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('absences')
            .doc(e.id)
            .get();
        final status = (snap.data()?['status'] ?? '').toString();
        if (!(snap.exists && status == 'absent')) {
          pending += 1;
        }
      } catch (_) {
        // If check fails for an event, assume it's pending to avoid undercounting
        pending += 1;
      }
    }
    return pending;
  }

  /// Confirm from the icon and record absence (no clearing from calendar).
  Future<void> _confirmAbsenceToggle(
    MicrosoftCalendarEvent event, {
    required bool isAbsent,
  }) async {
    final start = event.start ?? DateTime.now();
    final now = DateTime.now();
    final eventDay = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    if (eventDay.isAfter(today)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You can only record absence for today or past classes.',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (isAbsent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Absence already recorded for this class.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record absence?'),
        content: Text(event.subject.isNotEmpty ? event.subject : 'Lecture'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final String eventId = event.id;
    final String courseId = _resolveCourseId(event);
    final String title = event.subject.isNotEmpty ? event.subject : 'Lecture';
    final DateTime end = event.end ?? start.add(const Duration(minutes: 1));

    await AttendanceService.mark(
      courseId: courseId,
      eventId: eventId,
      status: 'absent',
      title: title,
      start: start,
      end: end,
    );
    _absenceByEventId[eventId] = 'absent';
    _recentlyMarkedAbsent.add(eventId);
    await _recomputeAndWarn(courseId);
  }

  /// Compute totals per normalized course code and publish to shared state
  /// so AbsencePage can use the same denominators as CalendarScreen.
  void _publishTotals() {
    int _durationMinutes(MicrosoftCalendarEvent e) {
      final start = e.start;
      final end = e.end;
      if (start == null) return 0;
      final dtEnd =
          (end == null || !end.isAfter(start)) ? start.add(const Duration(minutes: 1)) : end;
      final mins = dtEnd.difference(start).inMinutes;
      return mins <= 0 ? 1 : mins;
    }

    final Map<String, int> totalsCount = <String, int>{};
    final Map<String, int> totalsMinutes = <String, int>{};
    for (final e in _events) {
      final code = _resolveCourseId(e);
      totalsCount[code] = (totalsCount[code] ?? 0) + 1;
      totalsMinutes[code] = (totalsMinutes[code] ?? 0) + _durationMinutes(e);
    }
    AttendanceTotals.instance.setTotals(totalsCount);
    AttendanceTotals.instance.setTotalsMinutes(totalsMinutes);
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white.withOpacity(0.9),
          border: Border.all(
            color: _CalendarPalette.cardBorder.withOpacity(0.4),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _CalendarPalette.cardBorder.withOpacity(0.2),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 40,
              color: _CalendarPalette.accentPrimary,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: _CalendarPalette.textStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _CalendarPalette.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _CalendarPalette.accentPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: <Color>[
              _CalendarPalette.cardGradientStart,
              _CalendarPalette.cardGradientEnd,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: _CalendarPalette.cardBorder.withOpacity(0.5),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _CalendarPalette.cardBorder.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_sync_rounded,
              size: 48,
              color: _CalendarPalette.accentPrimary,
            ),
            const SizedBox(height: 20),
            Text(
              'Connect your Microsoft calendar to see your schedule.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _CalendarPalette.textStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _CalendarPalette.accentPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onPressed,
                child: const Text(
                  'Sign in with Microsoft',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
