// lib/screens/absence_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:absherk/services/attendance_service.dart';
import '../services/attendance_totals.dart';
import 'package:absherk/services/absence_calculator.dart';

class AbsencePage extends StatefulWidget {
  const AbsencePage({super.key});
  @override
  State<AbsencePage> createState() => _AbsencePageState();
}

class _AbsencePageState extends State<AbsencePage> {
  Future<Set<String>> _loadCourseCodesFallback() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return {};
      final q = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('lectures')
          .get();
      final Set<String> codes = {};
      for (final d in q.docs) {
        final raw = (d.data()['courseCode'] ?? '').toString();
        if (raw.isEmpty) continue;
        codes.add(_normalize(raw));
      }
      if (codes.isNotEmpty) return codes;
      // optional root fallback
      final r = await FirebaseFirestore.instance.collection('lectures').get();
      for (final d in r.docs) {
        final raw = (d.data()['courseCode'] ?? '').toString();
        if (raw.isEmpty) continue;
        codes.add(_normalize(raw));
      }
      return codes;
    } catch (_) {
      return {};
    }
  }
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

          // 2) Group by course
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final d in docs) {
            final data = d.data();
            final code = _normalize((data['courseCode'] ?? '').toString());
            final key = code.isEmpty ? 'UNKNOWN' : code;
            grouped.putIfAbsent(key, () => []).add({'id': d.id, ...data});
          }

          // Merge with known courses from totals (Calendar) so courses with
          // zero absences still appear.
          final totalsCourses =
              AttendanceTotals.instance.totalsByCourse.value.keys.toSet();
          final allCodes = <String>{...grouped.keys, ...totalsCourses};

          // If we still don't know any courses, try fetching from lectures.
          if (allCodes.isEmpty) {
            return FutureBuilder<Set<String>>(
              future: _loadCourseCodesFallback(),
              builder: (context, fsnap) {
                if (fsnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final codes = fsnap.data ?? {};
                if (codes.isEmpty && docs.isEmpty) {
                  return const Center(child: Text('No courses found.'));
                }
                final List<_CourseItem> items = codes.map((code) {
                  final recs = grouped[code] ?? <Map<String, dynamic>>[];
                  if (recs.isNotEmpty) {
                    recs.sort((a, b) {
                      final da = _asDateTime(a['start']) ?? DateTime(0);
                      final db = _asDateTime(b['start']) ?? DateTime(0);
                      return db.compareTo(da);
                    });
                  }
                  return _CourseItem(
                    code: code,
                    records: recs,
                    latest: recs.isNotEmpty ? _asDateTime(recs.first['start']) : null,
                  );
                }).toList()
                  ..sort((a, b) => a.code.compareTo(b.code));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _CourseCard(item: items[i]),
                );
              },
            );
          }

          // 3) Build items for union of codes (sorted by course code)
          final List<_CourseItem> items = allCodes.map((code) {
            final recs = grouped[code] ?? <Map<String, dynamic>>[];
            if (recs.isNotEmpty) {
              recs.sort((a, b) {
                final da = _asDateTime(a['start']) ?? DateTime(0);
                final db = _asDateTime(b['start']) ?? DateTime(0);
                return db.compareTo(da);
              });
            }
            return _CourseItem(
              code: code,
              records: recs,
              latest: recs.isNotEmpty ? _asDateTime(recs.first['start']) : null,
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

            // Compute duration-weighted %, show counts in the label.
            _PercentBar(courseCode: item.code, records: item.records),

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
  const _PercentBar({required this.courseCode, required this.records});

  final String courseCode; // normalized
  final List<Map<String, dynamic>> records; // only 'absent' rows

  @override
  Widget build(BuildContext context) {
    // Prefer CalendarScreen-provided total minutes; otherwise, fall back
    // to computing minutes from Firestore lectures via _computeDenominator.
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: AttendanceTotals.instance.totalMinutesByCourse,
      builder: (context, totals, _) {
        final providedMinutes = totals[courseCode];
        if (providedMinutes != null && providedMinutes > 0) {
          return _renderBar(totalMinutes: providedMinutes);
        }
        return FutureBuilder<_Denom>(
          future: _computeDenominatorMinutes(courseCode),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _placeholderBar();
            }
            final denom = snap.data ?? const _Denom(totalEvents: 0, totalMinutes: 0);
            final totalMinutes = denom.totalMinutes > 0
                ? denom.totalMinutes
                : _sumAbsentMinutes(records);
            return _renderBar(totalMinutes: totalMinutes);
          },
        );
      },
    );
  }

  Widget _renderBar({required int totalMinutes}) {
    final absentEvents = records.length;
    final absentMinutes = _sumAbsentMinutes(records);
    final pct = totalMinutes == 0 ? 0.0 : (absentMinutes * 100.0 / totalMinutes);
    final level = (pct / 25).clamp(0, 1).toDouble();

    Color barColor;
    if (level >= 1.0) {
      barColor = Colors.red;
    } else if (level >= 0.5) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.green;
    }

    // UI should be pure: no side effects during build.

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
          'Absence: ${pct.toStringAsFixed(1)}% (absent $absentEvents of ' 
          '${_totalClassesFor(courseCode)} classes)',
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

  int _totalClassesFor(String courseCode) {
    final counts = AttendanceTotals.instance.totalsByCourse.value;
    return counts[courseCode] ?? 0;
  }

  int _sumAbsentMinutes(List<Map<String, dynamic>> recs) {
    int total = 0;
    for (final r in recs) {
      final s = _asDateTime(r['start']);
      final e = _asDateTime(r['end']) ?? (s?.add(const Duration(minutes: 1)));
      if (s == null) continue;
      final mins = (e != null && e.isAfter(s)) ? e.difference(s).inMinutes : 1;
      total += mins <= 0 ? 1 : mins;
    }
    return total;
  }
}

// Denominator = totals up to now (events and minutes)
class _Denom {
  const _Denom({required this.totalEvents, required this.totalMinutes});
  final int totalEvents;
  final int totalMinutes;
}

Future<_Denom> _computeDenominatorMinutes(String normalizedCourseCode) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const _Denom(totalEvents: 0, totalMinutes: 0);

  // 1) Read user's lectures for this course.
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
    // No schedule found; return zeros so UI falls back gracefully.
    return const _Denom(totalEvents: 0, totalMinutes: 0);
  }

  // 2) Generate occurrences from semester start to today.
  final now = DateTime.now();
  final startOfYear = DateTime(now.year, 9, 1); // simple default
  int totalEvents = 0;
  int totalMinutes = 0;

  for (final d in lectDocs) {
    final data = d.data();
    final int dayOfWeek = (data['dayOfWeek'] as num).toInt(); // 0..6
    final int startTime = (data['startTime'] as num?)?.toInt() ?? 0;
    final int endTime = (data['endTime'] as num?)?.toInt() ?? 0;
    final int lectMins = (endTime - startTime) > 0 ? (endTime - startTime) : 1;

    // Count each week's occurrence.
    final occ = _countWeekdayOccurrences(startOfYear, now, dayOfWeek);
    totalEvents += occ;
    totalMinutes += occ * lectMins;
  }

  return _Denom(totalEvents: totalEvents, totalMinutes: totalMinutes);
}

Future<_Denom> _computeDenominator(String normalizedCourseCode) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const _Denom(totalEvents: 0, totalMinutes: 0);

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
    return const _Denom(totalEvents: 0, totalMinutes: 0);
  }

  // 2) Generate occurrences from semester start to today.
  //    We’ll assume semester started on Sep 1 of the current academic year,
  //    change if you already store semesterStart in lecture docs.
  final now = DateTime.now();
  final startOfYear = DateTime(now.year, 9, 1); // simple default
  int totalEvents = 0;
  int totalMinutes = 0;

  for (final d in lectDocs) {
    final data = d.data();
    final int dayOfWeek = (data['dayOfWeek'] as num).toInt(); // 0..6
    // count each week’s occurrence from startOfYear..today for that weekday
    final int startTime = (data['startTime'] as num?)?.toInt() ?? 0;
    final int endTime = (data['endTime'] as num?)?.toInt() ?? 0;
    final int lectMins = (endTime - startTime) > 0 ? (endTime - startTime) : 1;
    final occ = _countWeekdayOccurrences(startOfYear, now, dayOfWeek);
    totalEvents += occ;
    totalMinutes += occ * lectMins;
  }

  return _Denom(totalEvents: totalEvents, totalMinutes: totalMinutes);
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
        // Recompute for this course and notify if still above threshold
        final code = (record['courseCode'] ?? '').toString();
        if (code.isNotEmpty) {
          try {
            // Sum remaining absence minutes
            final absSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser?.uid)
                .collection('absences')
                .where('courseCode', isEqualTo: code)
                .get();
            int absentMinutes = 0;
            for (final d in absSnap.docs) {
              final data = d.data();
              final s = _asDateTime(data['start']);
              final e = _asDateTime(data['end']) ?? (s?.add(const Duration(minutes: 1)));
              if (s == null) continue;
              final mins = (e != null && e.isAfter(s)) ? e.difference(s).inMinutes : 1;
              absentMinutes += mins <= 0 ? 1 : mins;
            }

            final tm = AttendanceTotals.instance.totalMinutesByCourse.value[code] ?? 0;
            double pct;
            if (tm > 0) {
              pct = absentMinutes * 100.0 / tm;
            } else {
              final denom = await _computeDenominatorMinutes(code);
              pct = denom.totalMinutes > 0 ? (absentMinutes * 100.0 / denom.totalMinutes) : 0.0;
            }
            // Notifications removed: no OS alerts
          } catch (_) {}
        }
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
              // Recompute for this course and notify if still above threshold
              final code = (record['courseCode'] ?? '').toString();
              if (code.isNotEmpty) {
                try {
                  final absSnap = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser?.uid)
                      .collection('absences')
                      .where('courseCode', isEqualTo: code)
                      .get();
                  int absentMinutes = 0;
                  for (final d in absSnap.docs) {
                    final data = d.data();
                    final s = _asDateTime(data['start']);
                    final e = _asDateTime(data['end']) ?? (s?.add(const Duration(minutes: 1)));
                    if (s == null) continue;
                    final mins = (e != null && e.isAfter(s)) ? e.difference(s).inMinutes : 1;
                    absentMinutes += mins <= 0 ? 1 : mins;
                  }
                  final tm = AttendanceTotals.instance.totalMinutesByCourse.value[code] ?? 0;
                  double pct;
                  if (tm > 0) {
                    pct = absentMinutes * 100.0 / tm;
                  } else {
                    final denom = await _computeDenominatorMinutes(code);
                    pct = denom.totalMinutes > 0 ? (absentMinutes * 100.0 / denom.totalMinutes) : 0.0;
                  }
                  // Notifications removed: no OS alerts
                } catch (_) {}
              }
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
