import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/schedule_provider.dart';
import '../services/schedule_service.dart';
import 'home_page.dart';

const _kBgColor = Color(0xFFE6F3FF);
const _kTopBarColor = Color(0xFF0D4F94);
const _kAccentColor = Color(0xFF4A98E9);

class MyCoursesPage extends StatefulWidget {
  const MyCoursesPage({super.key});

  @override
  State<MyCoursesPage> createState() => _MyCoursesPageState();
}

class _MyCoursesPageState extends State<MyCoursesPage> {
  final Set<String> _deletingIds = <String>{};
  bool _bulkDeleting = false;
  final DateFormat _timeFormatter = DateFormat('hh:mm a');

  static const List<String> _weekdays = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  Map<String, List<ScheduleEntry>> _buildConflictMap(
      List<ScheduleEntry> entries) {
    final Map<String, List<ScheduleEntry>> conflicts =
        <String, List<ScheduleEntry>>{};
    final Map<int, List<ScheduleEntry>> byDay = <int, List<ScheduleEntry>>{};
    for (final entry in entries) {
      byDay.putIfAbsent(entry.dayOfWeek, () => <ScheduleEntry>[]).add(entry);
    }

    for (final dayEntries in byDay.values) {
      final sorted = List<ScheduleEntry>.of(dayEntries)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      for (var i = 0; i < sorted.length; i++) {
        final current = sorted[i];
        for (var j = i + 1; j < sorted.length; j++) {
          final other = sorted[j];
          if (other.startTime >= current.endTime) {
            break;
          }
          conflicts.putIfAbsent(current.id, () => <ScheduleEntry>[]).add(other);
          conflicts.putIfAbsent(other.id, () => <ScheduleEntry>[]).add(current);
        }
      }
    }

    return conflicts;
  }

  Future<void> _refreshProviderSchedule() async {
    if (!mounted) return;
    final provider = context.read<ScheduleProvider>();
    try {
      final entries = await ScheduleService.fetchScheduleOnce();
      if (!mounted) return;
      provider.replaceLectures(entries.map((e) => e.toLecture()));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScheduleEntry>>(
      stream: ScheduleService.watchSchedule(), // Firestore stream
      builder: (context, snapshot) {
        final entries = snapshot.data ?? <ScheduleEntry>[];
        final waiting = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        final conflictMap = _buildConflictMap(entries);

        Widget body;
        if (snapshot.hasError) {
          body = _ErrorView(
            message: snapshot.error.toString(),
            onRetry: () => setState(() {}),
          );
        } else if (waiting) {
          body = const Center(child: CircularProgressIndicator());
        } else if (entries.isEmpty) {
          body = const _EmptyView();
        } else {
          // Group sessions by section
          final grouped = <String, List<ScheduleEntry>>{};
          for (final e in entries) {
            grouped.putIfAbsent(e.section, () => []).add(e);
          }

          body = ListView(
            padding: const EdgeInsets.all(16),
            children: grouped.entries.map((entry) {
              final section = entry.key;
              final sessions = entry.value;
              final isDeletingSection =
                  sessions.any((session) => _deletingIds.contains(session.id));
              final first = sessions.first;
              sessions.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
              final hasConflict =
                  sessions.any((s) => conflictMap.containsKey(s.id));

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: hasConflict
                        ? Colors.redAccent
                        : _kTopBarColor.withOpacity(0.08),
                    width: hasConflict ? 1.5 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${first.courseCode} - Section $section',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _kTopBarColor,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                            onPressed: isDeletingSection || _bulkDeleting
                                ? null
                                : () => _confirmDeleteGroup(section, sessions),
                            tooltip: (isDeletingSection || _bulkDeleting)
                                ? 'Deleting...'
                                : null,
                          ),
                        ],
                      ),
                      Text(
                        first.courseName,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.75),
                        ),
                      ),
                      if (first.classroom.isNotEmpty)
                        Text(
                          'Room ${first.classroom}',
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.6),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: sessions.map((s) {
                          final conflicts =
                              conflictMap[s.id] ?? const <ScheduleEntry>[];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatSchedule(s),
                                  style: const TextStyle(
                                    color: _kTopBarColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (conflicts.isNotEmpty)
                                  Text(
                                    'Conflict with ${_formatConflictTargets(conflicts)}',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        }

        return Scaffold(
          backgroundColor: _kBgColor,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(86),
          child: Container(
            padding: const EdgeInsets.only(top: 12, left: 8, right: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF2E5D9F),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'My Courses',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: (entries.isEmpty || _bulkDeleting)
                          ? null
                          : _confirmBulkDelete,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: _bulkDeleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Clear All'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: body,
          bottomNavigationBar: _buildNavBar(currentIndex: 2),
        );
      },
    );
  }

  String _formatSchedule(ScheduleEntry e) {
    final day = (e.dayOfWeek >= 0 && e.dayOfWeek < _weekdays.length)
        ? _weekdays[e.dayOfWeek]
        : 'Day ${e.dayOfWeek}';
    String fmt(int m) {
      final h = m ~/ 60, min = m % 60;
      final now = DateTime.now();
      return _timeFormatter.format(
        DateTime(now.year, now.month, now.day, h, min),
      );
    }

    return '$day: ${fmt(e.startTime)} - ${fmt(e.endTime)}';
  }

  String _formatConflictTargets(List<ScheduleEntry> conflicts) {
    final labels = <String>{};
    for (final entry in conflicts) {
      final sectionLabel =
          entry.section.isNotEmpty ? 'section ${entry.section}' : '';
      labels.add(
        sectionLabel.isEmpty
            ? entry.courseCode
            : '${entry.courseCode} ($sectionLabel)',
      );
    }
    return labels.join(', ');
  }

  Future<void> _confirmDeleteGroup(
      String section, List<ScheduleEntry> sessions) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove section $section?'),
        content: Text(
          'This will delete ${sessions.length} class${sessions.length > 1 ? 'es' : ''} '
          'from your schedule and Microsoft Calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    // Optimistically remove UI immediately
    setState(() {
      for (final s in sessions) {
        _deletingIds.add(s.id);
      }
    });

    final messenger = ScaffoldMessenger.of(context);
    var allSucceeded = true;

    for (final s in sessions) {
      final success = await _deleteEntry(s, showSuccessMessage: false);
      if (!success) {
        allSucceeded = false;
      }
    }

    if (!mounted || !allSucceeded) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${sessions.first.courseCode} - Section $section removed from your schedule.',
        ),
      ),
    );
  }

  Future<bool> _deleteEntry(
    ScheduleEntry entry, {
    bool showSuccessMessage = true,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    // Optimistic removal
    setState(() {
      _deletingIds.add(entry.id);
    });

    try {
      await ScheduleService.deleteEntry(entry);
      if (showSuccessMessage) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${entry.courseCode} removed from your schedule.',
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error deleting: $e')),
      );
      return false;
    } finally {
      setState(() {
        _deletingIds.remove(entry.id);
      });
    }
  }

  Future<void> _confirmBulkDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all courses?'),
        content: const Text(
          'This will delete your entire schedule and remove all linked Microsoft Calendar entries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear All',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _bulkDeleting = true);
    try {
      final result = await ScheduleService.deleteAllEntries();
      if (!mounted) return;
      final msg = result.failedCount == 0
          ? 'Removed ${result.deletedCount} courses.'
          : 'Removed ${result.deletedCount}, failed ${result.failedCount}.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error clearing courses: $e')),
      );
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
  }

  void _onNavTap(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(initialIndex: index),
      ),
    );
  }

  Widget _buildNavBar({required int currentIndex}) {
    const inactiveColor = Color(0xFF7A8DA8);
    const activeColor = Color(0xFF2E5D9F);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xF2EAF3FF),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navItem(Icons.person_outline, 'Profile', currentIndex == 0, () => _onNavTap(0), activeColor, inactiveColor),
            _navItem(Icons.event_available_outlined, 'Schedule', currentIndex == 1, () => _onNavTap(1), activeColor, inactiveColor),
            _navItem(Icons.home_outlined, 'Home', currentIndex == 2, () => _onNavTap(2), activeColor, inactiveColor),
            _navItem(Icons.school_outlined, 'Experience', currentIndex == 3, () => _onNavTap(3), activeColor, inactiveColor),
            _navItem(Icons.people_outline, 'Community', currentIndex == 4, () => _onNavTap(4), activeColor, inactiveColor),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool active, VoidCallback onTap,
      Color activeColor, Color inactiveColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? activeColor : inactiveColor, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? activeColor : inactiveColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: active ? 26 : 0,
                decoration: BoxDecoration(
                  color: active ? activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'No courses yet\nAdd sections from the Schedule tab',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _kTopBarColor.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTopBarColor.withOpacity(0.8)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
