import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../services/microsoft_auth_service.dart';
import '../services/microsoft_calendar_service.dart';
import 'add_lecture_screen.dart';

import '../services/attendance_service.dart'; // for attendance
import '../services/attendance_totals.dart';
import 'package:absherk/services/noti_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Duration _calendarWindowRange = Duration(days: 210);

  late final DateTime _calendarWindowStart = MicrosoftCalendarService.resolveSemesterStart();
  MicrosoftAccount? _account;
  List<MicrosoftCalendarEvent> _events = <MicrosoftCalendarEvent>[];
  List<DateTime> _dayKeys = <DateTime>[];
  PageController? _pageController;
  int _currentPage = 0;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCalendar(interactive: false);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
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
      final account =
          MicrosoftAuthService.currentAccount ??
          await MicrosoftAuthService.ensureSignedIn(interactive: interactive);

      if (!mounted) return;

      if (account == null) {
        final previousController = _pageController;
        setState(() {
          _account = null;
          _events = <MicrosoftCalendarEvent>[];
          _dayKeys = <DateTime>[];
          _currentPage = 0;
          _pageController = null;
          _isLoading = false;
        });
        previousController?.dispose();
        AttendanceTotals.instance.clear();
        return;
      }

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

      final dayKeys = _extractDayKeys(events);
      final initialIndex = dayKeys.isEmpty ? 0 : _resolveInitialPage(dayKeys);
      final previousController = _pageController;
      final newController = dayKeys.isEmpty
          ? null
          : PageController(initialPage: initialIndex);

      setState(() {
        _account = account;
        _events = events;
        _dayKeys = dayKeys;
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
    // ✅ Use existing session
    final account =
        MicrosoftAuthService.currentAccount ??
        await MicrosoftAuthService.ensureSignedIn(interactive: interactive);

    if (account == null) {
      setState(() {
        _account = null;
        _events = <MicrosoftCalendarEvent>[];
        _isLoading = false;
      });
      return;
    }
  }

  Future<void> _handleRefresh() {
    return _loadCalendar(interactive: false, showSpinner: false);
  }

  Future<void> _handleSignOut() async {
    await MicrosoftAuthService.signOut();
    if (!mounted) return;
    final previousController = _pageController;
    setState(() {
      _account = null;
      _events = <MicrosoftCalendarEvent>[];
      _dayKeys = <DateTime>[];
      _currentPage = 0;
      _pageController = null;
    });
    previousController?.dispose();
    AttendanceTotals.instance.clear();
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
        title: const Text('My Schedule'),
        actions: [
          if (_account != null && _events.isNotEmpty && !_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: _confirmDeleteAll,
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('Clear all'),
              ),
            ),
          if (_account != null && !_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _loadCalendar(interactive: false),
              tooltip: 'Refresh events',
            ),
          if (_account != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _handleSignOut,
              tooltip: 'Sign out',
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: (_account != null && _events.isNotEmpty && !_isLoading)
          ? _buildAddSectionButton()
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildAddSectionButton({EdgeInsetsGeometry padding = const EdgeInsets.only(right: 16, bottom: 8), double width = 170}) {
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
                colors: [Color(0xFF4C6EF5), Color(0xFF5AD7C0)],
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

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _ErrorView(
        message: _error!,
        onRetry: () => _loadCalendar(interactive: false),
      );
    }

    if (_account == null) {
      return _SignInPrompt(onPressed: () => _loadCalendar(interactive: true));
    }

    if (_events.isEmpty) {
      return _buildEmptyState();
    }

    return _buildCalendarPager();
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F1FF), Color(0xFFF8F5FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 64,
                color: Color(0xFF4C6EF5),
              ),
              const SizedBox(height: 24),
              Text(
                'Build your calendar',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1B2559),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Tap "Add Section" to start crafting your schedule.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF4F5D9A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.center,
                child: _buildAddSectionButton(
                  padding: EdgeInsets.zero,
                  width: 200,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarPager() {
    final controller = _pageController;
    if (controller == null || _dayKeys.isEmpty) {
      return _buildEmptyState();
    }

    var pageIndex = _currentPage;
    if (pageIndex < 0) {
      pageIndex = 0;
    } else if (pageIndex >= _dayKeys.length) {
      pageIndex = _dayKeys.length - 1;
    }

    final currentDay = _dayKeys[pageIndex];
    final theme = Theme.of(context);
    final isToday = _isSameDay(currentDay, DateTime.now());

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE8F1FF), Color(0xFFFDF7FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: true,
        minimum: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: pageIndex > 0
                        ? () => _goToPage(pageIndex - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    splashRadius: 24,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('EEEE').format(currentDay),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1B2559),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMMM d, yyyy').format(currentDay),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF4F5D9A),
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
                              color: const Color(
                                0xFF4C6EF5,
                              ).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Today',
                              style: TextStyle(
                                color: Color(0xFF4C6EF5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: pageIndex < _dayKeys.length - 1
                        ? () => _goToPage(pageIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    splashRadius: 24,
                  ),
                ],
              ),
            ),
            if (!isToday &&
                _dayKeys.any((day) => _isSameDay(day, DateTime.now())))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _jumpToToday,
                    icon: const Icon(Icons.today_rounded),
                    label: const Text('Jump to today'),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: _dayKeys.length,
                onPageChanged: (page) => setState(() => _currentPage = page),
                itemBuilder: (context, pageIndex) {
                  final day = _dayKeys[pageIndex];
                  final dailyEvents = _eventsForDay(day);
                  return _buildDayPage(day, dailyEvents);
                },
              ),
            ),
            const SizedBox(height: 16),
            _buildPageIndicators(),
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
              color: Color(0xFF4C6EF5),
            ),
            const SizedBox(height: 18),
            Text(
              'No classes scheduled',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1B2559),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Enjoy your day or add a new section to stay ahead.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4F5D9A),
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

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 6,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          final start = event.start;
          if (start == null) return;
          final now = DateTime.now();
          final eventDay = DateTime(start.year, start.month, start.day);
          final today = DateTime(now.year, now.month, now.day);
          final isFutureDay = eventDay.isAfter(today);
          if (isFutureDay) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can only record absence for today or past classes.'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          // Prevent opening if absence already recorded for this event
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            try {
              final snap = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('absences')
                  .doc(event.id)
                  .get();
              final status = (snap.data()?['status'] ?? '').toString();
              if (snap.exists && status == 'absent') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Absence already recorded for this class.'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
            } catch (_) {
              // If check fails, fall through to allow dialog
            }
          }
          _openAbsenceDialog(event);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4C6EF5), Color(0xFF5AD7C0)],
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
                        color: const Color(0xFF1B2559),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: Color(0xFF4F5D9A),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          timeLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF4F5D9A),
                          ),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9F1FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF1B74E4),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              location,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF1B74E4),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _confirmDelete(event),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFE63946),
                ),
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicators() {
    if (_dayKeys.length <= 1) {
      return const SizedBox(height: 8);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_dayKeys.length, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: isActive ? 20 : 8,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF4C6EF5) : const Color(0xFFE0E5FF),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  List<DateTime> _extractDayKeys(List<MicrosoftCalendarEvent> events) {
    final days = <DateTime>{};
    for (final event in events) {
      final start = event.start;
      if (start != null) {
        days.add(_normalizeDate(start));
      }
    }
    final result = days.toList()..sort();
    return result;
  }

  int _resolveInitialPage(List<DateTime> days) {
    if (days.isEmpty) {
      return 0;
    }
    final today = _normalizeDate(DateTime.now());
    final todayIndex = days.indexWhere((day) => _isSameDay(day, today));
    if (todayIndex != -1) {
      return todayIndex;
    }
    for (var i = 0; i < days.length; i++) {
      if (days[i].isAfter(today)) {
        return i;
      }
    }
    return days.length - 1;
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<MicrosoftCalendarEvent> _eventsForDay(DateTime day) {
    final normalized = _normalizeDate(day);
    final events = _events.where((event) {
      final start = event.start;
      if (start == null) return false;
      return _isSameDay(start, normalized);
    }).toList();
    events.sort((a, b) {
      final aStart = a.start ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bStart = b.start ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aStart.compareTo(bStart);
    });
    return events;
  }

  void _goToPage(int index) {
    final controller = _pageController;
    if (controller == null) return;
    if (index < 0 || index >= _dayKeys.length) return;
    controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _jumpToToday() {
    final todayIndex = _dayKeys.indexWhere(
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

  String? _resolveSeriesId(MicrosoftCalendarEvent event) {
    final candidate = event.seriesMasterId?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
    final type = event.eventType?.toLowerCase();
    if (type == 'seriesmaster') {
      return event.id;
    }
    return null;
  }

  String _formatEventTime(MicrosoftCalendarEvent event) {
    if (event.isAllDay) return 'All day';

    final start = event.start;
    final end = event.end;
    if (start == null) return 'Time not specified';

    final formatter = DateFormat('hh:mm a');
    final startLabel = formatter.format(start);
    if (end == null || start.isAtSameMomentAs(end)) return startLabel;
    return '$startLabel - ${formatter.format(end)}';
  }

  Future<void> _confirmDeleteAll() async {
    if (_events.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No sections to delete.')));
      return;
    }

    final total = _events.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All Sections'),
        content: Text(
          'This will remove $total section${total == 1 ? '' : 's'} from your calendar. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete all',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (!mounted) {
      return;
    }

    if (confirmed != true) {
      return;
    }

    if (_account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in with Microsoft first.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final snapshot = List<MicrosoftCalendarEvent>.from(_events);
    final processedSeries = <String>{};
    final processedSingles = <String>{};
    Object? firstError;

    for (final event in snapshot) {
      try {
        final seriesId = _resolveSeriesId(event);
        if (seriesId != null) {
          if (!processedSeries.add(seriesId)) {
            continue;
          }
          await MicrosoftCalendarService.deleteLecture(
            account: _account!,
            eventId: event.id,
            seriesMasterId: seriesId,
          );
        } else {
          if (!processedSingles.add(event.id)) {
            continue;
          }
          await MicrosoftCalendarService.deleteLecture(
            account: _account!,
            eventId: event.id,
          );
        }
      } catch (error) {
        firstError ??= error;
      }
    }

    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    if (firstError == null) {
      // Clear absence records for all deleted event IDs and courses
      final ids = snapshot.map((e) => e.id);
      await _clearAbsencesForEvents(ids);
      final courseIds = snapshot.map(_resolveCourseId).toSet();
      for (final c in courseIds) {
        await _clearAbsencesForCourse(c);
      }
      setState(() {
        _events = <MicrosoftCalendarEvent>[];
        _isLoading = false;
      });
      _publishTotals();
      messenger.showSnackBar(
        const SnackBar(content: Text('All sections deleted.')),
      );
    } else {
      setState(() {
        _isLoading = false;
      });
      await _loadCalendar(interactive: false, showSpinner: false);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Some sections could not be deleted: $firstError'),
        ),
      );
    }
  }

  Future<void> _confirmDelete(MicrosoftCalendarEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Lecture'),
        content: Text(
          'Are you sure you want to delete "${event.subject}" for all upcoming occurrences?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_account == null) return;

      final seriesId = _resolveSeriesId(event);

      await MicrosoftCalendarService.deleteLecture(
        account: _account!,
        eventId: event.id,
        seriesMasterId: seriesId,
      );

      if (!mounted) return;

      // Determine event IDs that will be removed so we can clear absences
      final List<String> removedIds = <String>[];
      if (seriesId != null) {
        for (final e in _events) {
          final candidateSeriesId = _resolveSeriesId(e);
          if (e.id == event.id || e.id == seriesId || candidateSeriesId == seriesId) {
            removedIds.add(e.id);
          }
        }
      } else {
        removedIds.add(event.id);
      }

      setState(() {
        if (seriesId != null) {
          _events.removeWhere((e) {
            final candidateSeriesId = _resolveSeriesId(e);
            return e.id == event.id || e.id == seriesId || candidateSeriesId == seriesId;
          });
        } else {
          _events.removeWhere((e) => e.id == event.id);
        }
      });
      // Clear absence records for removed events; if deleting a series, also by course
      await _clearAbsencesForEvents(removedIds);
      if (seriesId != null) {
        final courseId = _resolveCourseId(event);
        await _clearAbsencesForCourse(courseId);
      }
      _publishTotals();

      messenger.showSnackBar(
        SnackBar(
          content: Text('${event.subject} deleted for all occurrences.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error deleting event: $e')),
      );
    }
  }

  /// Extract a course code from the event subject, e.g. "CS101 � Lecture 5".
  String _resolveCourseId(MicrosoftCalendarEvent e) {
    final s = (e.subject).toUpperCase();
    final m = RegExp(r'[A-Z]{2,}\s?\d{2,}').firstMatch(s); // CS101 or CS 101
    return (m?.group(0)?.replaceAll(' ', '')) ?? 'UNASSIGNED';
  }

  /// Show dialog to mark Absent / Cancelled / Clear (present).
  void _openAbsenceDialog(MicrosoftCalendarEvent event) {
    final String eventId = event.id; // Microsoft event id (must be non-null)
    final String courseId = _resolveCourseId(event);
    final String title = event.subject.isNotEmpty ? event.subject : 'Lecture';
    final DateTime start = event.start ?? DateTime.now();
    final DateTime end = event.end ?? start.add(const Duration(minutes: 1));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Record absence')),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        content: Text(title),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            child: const Text('Absent'),
            onPressed: () async {
              // Allow marking absence for today or any past day; block future days.
              final now = DateTime.now();
              final eventDay = DateTime(start.year, start.month, start.day);
              final today = DateTime(now.year, now.month, now.day);
              final isFutureDay = eventDay.isAfter(today);
              if (isFutureDay) {
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'You can only record absence for today or past classes.',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
                return;
              }
              await AttendanceService.mark(
                courseId: courseId,
                eventId: eventId,
                status: 'absent',
                title: title,
                start: start,
                end: end,
              );
              await _recomputeAndWarn(courseId);
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  /// Recompute absence % for a course and show a SnackBar warning if > 20%.
  ///
  /// Rule:
  /// - Present = default (no doc in Firestore)
  /// - We only store exceptions: 'absent'
  /// - Percentage = ABSENT / TOTAL_EVENTS * 100
  Future<void> _recomputeAndWarn(String courseId) async {
    final courseEvents = _events
        .where((e) => _resolveCourseId(e) == courseId)
        .toList();
    if (courseEvents.isEmpty) {
      return;
    }

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

    final absent = courseEvents.where((e) => byEvent[e.id] == 'absent').length;
    final total = courseEvents.length;
    if (total == 0 || !mounted) {
      return;
    }

    final pct = absent * 100.0 / total;
    final msg = '$courseId absence: ${pct.toStringAsFixed(1)}% (absent $absent of $total)';

    // Local notification when thresholds exceeded (20%/25%).
    if (pct > 20) {
      // Fire-and-forget; NotiService is initialized in main
      // and handles tiered messages and platform specifics.
      // Avoid blocking the UI.
      // ignore: unawaited_futures
      NotiService.showAbsenceAlert(courseId, pct);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pct > 20 ? 'Warning: $msg - over 20%!' : msg),
        backgroundColor: pct > 20 ? Colors.red : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Compute totals per normalized course code and publish to shared state
  /// so AbsencePage can use the same denominators as CalendarScreen.
  void _publishTotals() {
    final Map<String, int> totals = <String, int>{};
    for (final e in _events) {
      final code = _resolveCourseId(e);
      totals[code] = (totals[code] ?? 0) + 1;
    }
    AttendanceTotals.instance.setTotals(totals);
  }

  /// Remove absence documents for the given event IDs, ignoring individual errors.
  Future<void> _clearAbsencesForEvents(Iterable<String> eventIds) async {
    for (final id in eventIds) {
      try {
        await AttendanceService.clearEvent(id);
      } catch (_) {
        // Ignore errors per-id to avoid blocking the whole flow.
      }
    }
  }

  /// Remove all absence docs for a course code (normalized) for the current user.
  Future<void> _clearAbsencesForCourse(String courseId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('absences')
          .where('courseCode', isEqualTo: courseId)
          .get();
      for (final d in q.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
    } catch (_) {
      // ignore cleanup errors
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Something went wrong:\n$message',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Sign in with your Microsoft account to view your calendar.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onPressed,
            child: const Text('Sign in with Microsoft'),
          ),
        ],
      ),
    );
  }
}





