// lib/screens/absence_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:absherk/services/attendance_service.dart';
import 'package:absherk/services/noti_service.dart';
import '../services/attendance_totals.dart';

class AbsencePage extends StatefulWidget {
  const AbsencePage({super.key});
  @override
  State<AbsencePage> createState() => _AbsencePageState();
}

class _AbsencePageState extends State<AbsencePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Absences')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: AttendanceService.streamMyAbsences(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          var docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('No absences recorded.'));
          }

          // 2) Group by course
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final d in docs) {
            final data = d.data();
            final code = _normalize((data['courseCode'] ?? '').toString());
            final key = code.isEmpty ? 'UNKNOWN' : code;
            grouped.putIfAbsent(key, () => []).add({'id': d.id, ...data});
          }

          // 3) Build items (sorted by course code)
          final items = grouped.entries.map((e) {
            // newest first
            e.value.sort((a, b) {
              final da = _asDateTime(a['start']) ?? DateTime(0);
              final db = _asDateTime(b['start']) ?? DateTime(0);
              return db.compareTo(da);
            });
            return _CourseItem(
              code: e.key,
              records: e.value,
              latest: _asDateTime(e.value.first['start']),
            );
          }).toList()
            ..sort((a, b) => a.code.compareTo(b.code));

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, i) => _CourseCard(item: items[i]),
          );
        },
      ),
    );
  }
}

class _CourseItem {
  _CourseItem({
    required this.code,
    required this.records,
    required this.latest,
  });

  final String code;
  final List<Map<String, dynamic>> records; // only 'absent' rows
  final DateTime? latest;

  int get absentCount => records.length;
}

/* =========================== UI: Course Card ============================ */

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.item});
  final _CourseItem item;

  @override
  Widget build(BuildContext context) {
    final courseCode = item.code == 'UNKNOWN' ? 'Unknown course' : item.code;
    final latestStr = item.latest == null
        ? null
        : DateFormat('MMM d, yyyy • hh:mm a').format(item.latest!);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              courseCode,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            _Badge(
              label: 'Absent ${item.absentCount}',
              color: Colors.red.withOpacity(0.12),
              textColor: Colors.red,
            ),
            const SizedBox(height: 8),

            // Compute total classes so far FROM LECTURES and show %.
            _PercentBar(courseCode: item.code, absences: item.absentCount),

            const SizedBox(height: 4),
            if (latestStr != null) Text('Latest: $latestStr'),
          ],
        ),
        children: [
          const Divider(height: 1),
          ...item.records.map((r) => _AbsenceRow(record: r)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/* =========================== % Bar (denominator from lectures) ============================ */

class _PercentBar extends StatelessWidget {
  const _PercentBar({required this.courseCode, required this.absences});

  final String courseCode; // normalized
  final int absences;

  @override
  Widget build(BuildContext context) {
    // Prefer CalendarScreen-provided totals if available; otherwise, fall back
    // to computing from Firestore lectures via _computeDenominator.
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: AttendanceTotals.instance.totalsByCourse,
      builder: (context, totals, _) {
        final provided = totals[courseCode];
        if (provided != null && provided > 0) {
          return _renderBar(total: provided);
        }
        return FutureBuilder<_Denom>(
          future: _computeDenominator(courseCode),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _placeholderBar();
            }
            final denom = snap.data ?? const _Denom(totalSoFar: 0);
            final fallbackTotal = denom.totalSoFar > 0 ? denom.totalSoFar : absences;
            return _renderBar(total: fallbackTotal);
          },
        );
      },
    );
  }

  Widget _renderBar({required int total}) {
    final pct = total == 0 ? 0.0 : (absences * 100.0 / total);
    final level = (pct / 25).clamp(0, 1).toDouble();

    Color barColor;
    if (level >= 1.0) {
      barColor = Colors.red;
    } else if (level >= 0.5) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.green;
    }

    // Fire-and-forget: if threshold is crossed, maybe show a local notif.
    if (pct > 20) {
      // Use a microtask to avoid doing async work directly in build.
      Future.microtask(() => _maybeNotify(courseCode, pct));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: level),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              color: barColor,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Absence: ${pct.toStringAsFixed(1)}% of classes ($absences/$total)',
          style: TextStyle(
            fontSize: 12,
            color: barColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _placeholderBar() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.15,
              minHeight: 8,
              color: Colors.grey.shade400,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Absence: …',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

// Denominator = number of scheduled class occurrences up to now
class _Denom {
  const _Denom({required this.totalSoFar});
  final int totalSoFar;
}

Future<_Denom> _computeDenominator(String normalizedCourseCode) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const _Denom(totalSoFar: 0);

  // 1) Read user's lectures for this course.
  //    Expected doc fields (based on your Lecture model):
  //    courseCode (String), dayOfWeek (0..6, Mon=1? adjust below), startTime/endTime (minutes)
  final userLects = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('lectures')
      .where('courseCode', isEqualTo: normalizedCourseCode)
      .get();

  // If nothing in users/{uid}/lectures, try a fallback root collection (optional).
  var lectDocs = userLects.docs;
  if (lectDocs.isEmpty) {
    final root = await FirebaseFirestore.instance
        .collection('lectures')
        .where('courseCode', isEqualTo: normalizedCourseCode)
        .get();
    lectDocs = root.docs;
  }

  if (lectDocs.isEmpty) {
    // No schedule → we can’t know total; fall back to absences-only elsewhere.
    return const _Denom(totalSoFar: 0);
  }

  // 2) Generate occurrences from semester start to today.
  //    We’ll assume semester started on Sep 1 of the current academic year,
  //    change if you already store semesterStart in lecture docs.
  final now = DateTime.now();
  final startOfYear = DateTime(now.year, 9, 1); // simple default
  int total = 0;

  for (final d in lectDocs) {
    final data = d.data();
    final int dayOfWeek = (data['dayOfWeek'] as num).toInt(); // 0..6
    // count each week’s occurrence from startOfYear..today for that weekday
    total += _countWeekdayOccurrences(startOfYear, now, dayOfWeek);
  }

  return _Denom(totalSoFar: total);
}

// Throttled via AttendanceService.shouldWarn to avoid repeated alerts.
Future<void> _maybeNotify(String courseCodeNormalized, double pct) async {
  try {
    final ok = await AttendanceService.shouldWarn(courseCodeNormalized, pct);
    if (ok) {
      await NotiService.showAbsenceAlert(courseCodeNormalized, pct);
    }
  } catch (_) {
    // ignore
  }
}

int _countWeekdayOccurrences(DateTime from, DateTime to, int weekdayZeroBased) {
  // Convert to DateTime.weekday (1=Mon..7=Sun). Your model is 0..6.
  final target = ((weekdayZeroBased % 7) + 1);
  // Find first target weekday >= from
  var first = from;
  while (first.weekday != target) {
    first = first.add(const Duration(days: 1));
  }
  if (first.isAfter(to)) return 0;
  final days = to.difference(first).inDays;
  return (days ~/ 7) + 1;
}

/* =========================== Absence Row (with delete) ============================ */

class _AbsenceRow extends StatelessWidget {
  const _AbsenceRow({required this.record});
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final start = _asDateTime(record['start']);
    final title = (record['eventSummary'] ??
            record['title'] ??
            record['courseName'] ??
            record['course'] ??
            record['courseCode'] ??
            'Unknown class')
        .toString();
    final when = start != null
        ? DateFormat('EEE, MMM d • hh:mm a').format(start)
        : 'No date';
    final eventId = (record['id'] ?? '').toString();

    return Dismissible(
      key: ValueKey('abs_row_$eventId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.red.withOpacity(0.12),
        child: const Icon(Icons.delete_forever_rounded, color: Colors.red),
      ),
      confirmDismiss: (_) async => await _confirmDelete(context, title),
      onDismissed: (_) async {
        await AttendanceService.clearEvent(eventId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed: $title'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: ListTile(
        leading: const Icon(Icons.remove_circle_rounded, color: Colors.red),
        title: Text(title),
        subtitle: Text('absent • $when'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        trailing: IconButton(
          icon: const Icon(Icons.delete_rounded),
          color: Colors.redAccent,
          tooltip: 'Delete record',
          onPressed: () async {
            final ok = await _confirmDelete(context, title);
            if (ok) {
              await AttendanceService.clearEvent(eventId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removed: $title'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete record?'),
            content: Text('This will remove:\n$title'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

/* (Filter removed) */

/* =========================== Small helpers ============================ */

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.textColor});
  final String label;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: textColor ?? Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  if (v is Map && v['_seconds'] != null) {
    final secs = (v['_seconds'] as num).toInt();
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  }
  return null;
}

String _normalize(String s) => s.toUpperCase().replaceAll(' ', '');
DateTime _atStartOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _atEndOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
