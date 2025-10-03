// lib/screens/absence_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';

enum AbsenceFilter { all, absent, cancelled }

class AbsencePage extends StatefulWidget {
  const AbsencePage({super.key});
  @override
  State<AbsencePage> createState() => _AbsencePageState();
}

class _AbsencePageState extends State<AbsencePage> {
  AbsenceFilter _filter = AbsenceFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Absences')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: AttendanceService.streamMyAbsences(),
        builder: (context, absSnap) {
          if (absSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (absSnap.hasError) {
            return Center(child: Text('Error: ${absSnap.error}'));
          }

          final absDocs = absSnap.data?.docs ?? [];
          if (absDocs.isEmpty) {
            return const Center(child: Text('No absences recorded.'));
          }

          // Also stream per-course stats (true denominator)
          return StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: AttendanceService.streamCourseStats(),
            builder: (context, statsSnap) {
              final stats = statsSnap.data ?? <String, Map<String, dynamic>>{};

              // 1) Group all exception records by course (keep ALL records intact)
              final Map<String, List<Map<String, dynamic>>> grouped = {};
              for (final d in absDocs) {
                final data = d.data();
                final code = _normalize((data['courseCode'] ?? '').toString());
                final key = code.isEmpty ? 'UNKNOWN' : code;
                grouped.putIfAbsent(key, () => []).add({'id': d.id, ...data});
              }

              // 2) Build _CourseItem list and apply COURSE-LEVEL filter
              final items = <_CourseItem>[];
              grouped.forEach((courseCode, recs) {
                final absentCount =
                    recs.where((r) => (r['status'] ?? '') == 'absent').length;
                final cancelledCount =
                    recs.where((r) => (r['status'] ?? '') == 'cancelled').length;

                // Decide inclusion based on filter (course-level)
                final include = switch (_filter) {
                  AbsenceFilter.all => true,
                  AbsenceFilter.absent => absentCount > 0,
                  AbsenceFilter.cancelled => cancelledCount > 0,
                };
                if (!include) return;

                // Sort newest first for "Latest" and details
                recs.sort((a, b) {
                  final da = _asDateTime(a['start']) ?? DateTime(0);
                  final db = _asDateTime(b['start']) ?? DateTime(0);
                  return db.compareTo(da);
                });

                // Use stats (same denominator as snackbar) when available
                final stat = stats[courseCode] ?? {};
                final totalEvents = (stat['totalEvents'] as num?)?.toInt();
                final cancelledStat = (stat['cancelled'] as num?)?.toInt();

                final cancelled = cancelledStat ?? cancelledCount;
                int effective; // denominator
                if (totalEvents != null) {
                  effective = (totalEvents - (cancelled ?? 0)).clamp(0, 100000);
                } else {
                  // fallback: exceptions-only (not ideal, but safe)
                  effective = (recs.length - (cancelled ?? 0)).clamp(0, 100000);
                }

                final pct = effective > 0 ? (absentCount / effective) * 100 : 0.0;
                final latest = _asDateTime(recs.first['start']);

                items.add(_CourseItem(
                  code: courseCode,
                  records: recs,               // KEEP ALL records (absent & cancelled)
                  absent: absentCount,
                  cancelled: cancelled ?? 0,
                  effective: effective,
                  pct: pct,
                  latest: latest,
                ));
              });

              items.sort((a, b) => a.code.compareTo(b.code));

              return Column(
                children: [
                  _FilterBar(
                    value: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _CourseCard(item: items[i]),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/* =========================== UI widgets ============================ */

class _CourseItem {
  _CourseItem({
    required this.code,
    required this.records,
    required this.absent,
    required this.cancelled,
    required this.effective,
    required this.pct,
    required this.latest,
  });

  final String code;
  final List<Map<String, dynamic>> records; // contains BOTH absent & cancelled
  final int absent;
  final int cancelled;
  final int effective;   // denominator used
  final double pct;      // 0..100
  final DateTime? latest;
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.item});
  final _CourseItem item;

  @override
  Widget build(BuildContext context) {
    final courseCode = item.code == 'UNKNOWN' ? 'Unknown course' : item.code;

    // Progress toward 20%
    final level = (item.pct / 20).clamp(0, 1).toDouble(); // 0..1
    Color barColor;
    if (level >= 1.0) {
      barColor = Colors.red;
    } else if (level >= 0.5) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.green;
    }

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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (item.absent > 0)
                  _Badge(
                    label: 'Absent ${item.absent}',
                    color: Colors.red.withOpacity(0.12),
                    textColor: Colors.red,
                  ),
                if (item.absent > 0 && item.cancelled > 0) const SizedBox(width: 6),
                if (item.cancelled > 0)
                  _Badge(
                    label: 'Cancelled ${item.cancelled}',
                    color: Colors.orange.withOpacity(0.12),
                    textColor: Colors.orange[900],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: level,
                minHeight: 8,
                color: barColor,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Absence: ${item.pct.toStringAsFixed(1)}% of classes '
              '(${item.absent}/${item.effective})',
              style: TextStyle(
                fontSize: 12,
                color: barColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        subtitle: latestStr == null ? null : Text('Latest: $latestStr'),
        children: [
          const Divider(height: 1),
          // IMPORTANT: show ALL records for this course (don’t filter details)
          ...item.records.map((r) => _AbsenceRow(record: r)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _AbsenceRow extends StatelessWidget {
  const _AbsenceRow({required this.record});
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final status = (record['status'] ?? 'present').toString();
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

    IconData icon;
    Color color;
    switch (status) {
      case 'absent':
        icon = Icons.close_rounded;
        color = Colors.red;
        break;
      case 'cancelled':
        icon = Icons.cancel_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.check_circle_rounded;
        color = Colors.green;
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text('$status • $when'),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});
  final AbsenceFilter value;
  final ValueChanged<AbsenceFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, AbsenceFilter f) {
      final selected = value == f;
      final cs = Theme.of(context).colorScheme;
      final bg = selected ? cs.primary.withOpacity(0.12) : Colors.white;
      final fg = selected ? cs.primary : Colors.black87;

      return GestureDetector(
        onTap: () => onChanged(f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: selected ? fg : Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          seg('All', AbsenceFilter.all),
          seg('Absent', AbsenceFilter.absent),
          seg('Cancelled', AbsenceFilter.cancelled),
        ],
      ),
    );
  }
}

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

/* =========================== helpers ============================== */

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
