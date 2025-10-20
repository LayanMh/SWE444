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
  final DateFormat _timeFormatter = DateFormat('hh:mm a');

  static const List<String> _weekdays = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];

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
        final waiting =
            snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

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
              final first = sessions.first;
              sessions.sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${first.courseCode} - Section $section',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(first.courseName),
                      if (first.classroom.isNotEmpty)
                        Text('Room ${first.classroom}'),
                      const SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: sessions.map((s) => Text(_formatSchedule(s))).toList(),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          onPressed: () => _confirmDeleteGroup(section, sessions),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        }

        return Scaffold(
  appBar: AppBar(
    title: const Text('My Courses'),
    actions: [
      if (entries.isNotEmpty && !_bulkDeleting)
        TextButton(
          onPressed: _confirmBulkDelete,
          child: const Text(
            'Clear All',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      if (_bulkDeleting)
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          ),
        ),
    ],
  ),
  body: body,
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
      return _timeFormatter.format(DateTime(now.year, now.month, now.day, h, min));
    }
    return '$day: ${fmt(e.startTime)} - ${fmt(e.endTime)}';
  }

  Future<void> _confirmDeleteGroup(String section, List<ScheduleEntry> sessions) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove section $section?'),
        content: Text('This will delete ${sessions.length} class${sessions.length > 1 ? 'es' : ''} '
            'from your schedule and Microsoft Calendar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
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

    for (final s in sessions) {
      await _deleteEntry(s);
    }
  }

  Future<void> _deleteEntry(ScheduleEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);

    // Optimistic removal
    setState(() {
      _deletingIds.add(entry.id);
    });

    try {
      await ScheduleService.deleteEntry(entry);
      messenger.showSnackBar(
        SnackBar(content: Text('${entry.courseCode} removed from your schedule.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error deleting: $e')));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error clearing courses: $e')),
    );
  } finally {
    if (mounted) setState(() => _bulkDeleting = false);
  }
}

}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'No courses yet\n Add sections from the Schedule tab',
        textAlign: TextAlign.center,
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
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
