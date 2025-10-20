import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/schedule_provider.dart';
import '../services/schedule_service.dart';

class MyCoursesPage extends StatefulWidget {
  const MyCoursesPage({super.key});

  @override
  State<MyCoursesPage> createState() => _MyCoursesPageState();
}

class _MyCoursesPageState extends State<MyCoursesPage> {
  final Set<String> _deletingIds = <String>{};
  bool _bulkDeleting = false;

  static const List<String> _weekdays = <String>[
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  final DateFormat _timeFormatter = DateFormat('hh:mm a');

  Future<void> _refreshProviderSchedule() async {
    if (!mounted) {
      return;
    }
    final provider = context.read<ScheduleProvider>();
    try {
      final entries = await ScheduleService.fetchScheduleOnce();
      if (!mounted) {
        return;
      }
      provider.replaceLectures(entries.map((entry) => entry.toLecture()));
    } catch (_) {
      // Ignore sync errors; UI already reflects Firestore via the stream.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScheduleEntry>>(
      stream: ScheduleService.watchSchedule(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? <ScheduleEntry>[];
        final bool waiting =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

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
          body = ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final deleting = _deletingIds.contains(entry.id);
              return Opacity(
                opacity: deleting ? 0.5 : 1,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      '${entry.courseCode} - Section ${entry.section}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(entry.courseName),
                        if (entry.classroom.isNotEmpty)
                          Text('Room ${entry.classroom}'),
                        Text(_formatSchedule(entry)),
                      ],
                    ),
                    trailing: deleting
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: Colors.redAccent,
                            tooltip: 'Remove from schedule',
                            onPressed: () => _confirmDelete(entry),
                          ),
                  ),
                ),
              );
            },
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('My Courses'),
            actions: [
              if (_bulkDeleting)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (entries.isNotEmpty && !waiting)
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
                    onPressed: () => _confirmDeleteAll(entries),
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: const Text('Clear all'),
                  ),
                ),
            ],
          ),
          body: body,
        );
      },
    );
  }

  String _formatSchedule(ScheduleEntry entry) {
    final dayLabel =
        (entry.dayOfWeek >= 0 && entry.dayOfWeek < _weekdays.length)
        ? _weekdays[entry.dayOfWeek]
        : 'Day ${entry.dayOfWeek}';

    String formatTime(int minutes) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, hours, mins);
      return _timeFormatter.format(dt);
    }

    final startLabel = formatTime(entry.startTime);
    final endLabel = formatTime(entry.endTime);
    return '$dayLabel | $startLabel - $endLabel';
  }

  Future<void> _confirmDelete(ScheduleEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${entry.courseCode}?'),
        content: const Text(
          'This will delete the course from your weekly schedule and Microsoft calendar.',
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

    if (!mounted || confirmed != true) {
      return;
    }

    await _deleteEntry(entry);
  }

  Future<void> _confirmDeleteAll(List<ScheduleEntry> entries) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all courses?'),
        content: Text(
          'This will remove ${entries.length} course${entries.length == 1 ? '' : 's'} from your schedule and Microsoft calendar.',
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
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _bulkDeleting = true;
      _deletingIds
        ..clear()
        ..addAll(entries.map((e) => e.id));
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await ScheduleService.deleteAllEntries();
      if (!mounted) return;
      if (result.failedCount == 0) {
        final count = result.deletedCount;
        final label = count == 1 ? 'course' : 'courses';
        messenger.showSnackBar(
          SnackBar(content: Text('Removed $count $label.')),
        );
      } else {
        final errorLabel = result.error?.toString() ?? 'unknown error';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Removed ${result.deletedCount} courses, '
              '${result.failedCount} failed: $errorLabel',
            ),
          ),
        );
      }
      await _refreshProviderSchedule();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not clear courses: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _bulkDeleting = false;
          _deletingIds.clear();
        });
      }
    }
  }

  Future<void> _deleteEntry(ScheduleEntry entry) async {
    setState(() {
      _deletingIds.add(entry.id);
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      await ScheduleService.deleteEntry(entry);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${entry.courseCode} removed from your schedule.'),
        ),
      );
      await _refreshProviderSchedule();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete ${entry.courseCode}: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingIds.remove(entry.id);
        });
      }
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No courses yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add sections from the Schedule tab to see them here.',
              textAlign: TextAlign.center,
            ),
          ],
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
