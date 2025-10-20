// lib/screens/my_courses_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'add_lecture_screen.dart';
import '../services/microsoft_auth_service.dart';
import '../services/microsoft_calendar_service.dart';

class MyCoursesScreen extends StatefulWidget {
  const MyCoursesScreen({super.key});

  @override
  State<MyCoursesScreen> createState() => _MyCoursesScreenState();
}

class _MyCoursesScreenState extends State<MyCoursesScreen> {
  String? _userDocId; // Firebase UID or microsoft_user_doc_id
  late CollectionReference<Map<String, dynamic>> _scheduleRef;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _resolveUserDocId();
  }

  Future<void> _resolveUserDocId() async {
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser != null) {
      _userDocId = fbUser.uid;
    } else {
      final prefs = await SharedPreferences.getInstance();
      _userDocId = prefs.getString('microsoft_user_doc_id');
    }
    if (_userDocId != null && _userDocId!.isNotEmpty) {
      _scheduleRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .collection('schedule');
    }
    if (mounted) setState(() => _loadingUser = false);
  }

  // ---------- UI helpers ----------
  static const _dowNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  String _fmtTime(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hh = (h % 12 == 0) ? 12 : (h % 12);
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm $ampm';
  }

  // ---------- Data ops ----------
  Future<int> _currentTotalHours() async {
    final snap = await _scheduleRef.get();
    int total = 0;
    for (final d in snap.docs) {
      total += (d.data()['hours'] ?? 0) as int;
    }
    return total;
  }

  Future<void> _onAddPressed() async {
    if (_userDocId == null || _userDocId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first.')),
      );
      return;
    }
    final total = await _currentTotalHours();
    if (total >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You reached the 20-hour limit.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddLectureScreen()),
    );
    if (mounted) setState(() {}); // refresh
  }

  void _confirmDelete(String sectionId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove section'),
        content: Text('Remove section $sectionId from your schedule?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSection(sectionId);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Delete all docs of this section (if you store per-day docs) OR the single doc (if consolidated),
  /// and remove linked Microsoft Calendar items if present.
  Future<void> _deleteSection(String sectionId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Fetch all docs in user's schedule for this section (handles per-day storage)
      final q = await _scheduleRef.where('section', isEqualTo: sectionId).get();
      if (q.docs.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Section not found.')));
        return;
      }

      // Try to sign in to Microsoft (optional)
      final account = await MicrosoftAuthService.ensureSignedIn();

      for (final doc in q.docs) {
        final data = doc.data();
        final eventId = data['calendarEventId'] as String?;
        final seriesId = data['calendarSeriesMasterId'] as String?;
        await _scheduleRef.doc(doc.id).delete();

        if (account != null && (eventId != null || seriesId != null)) {
          try {
            await MicrosoftCalendarService.deleteLecture(
              account: account,
              eventId: eventId ?? '',
              seriesMasterId: seriesId,
            );
          } catch (_) {
            // Ignore calendar deletion errors so UI stays responsive
          }
        }
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Section $sectionId removed.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to remove: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_userDocId == null || _userDocId!.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view your courses.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Courses'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _onAddPressed),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _scheduleRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('No courses added yet.'));
          }

          // Group by section → one card per section
          final Map<String, _SectionGroup> groups = {};
          for (final d in snap.data!.docs) {
            final x = d.data();
            final section = (x['section'] ?? '').toString();
            if (section.isEmpty) continue;

            final g = groups.putIfAbsent(
              section,
              () => _SectionGroup(
                section: section,
                courseCode: (x['courseCode'] ?? '').toString(),
                courseName: (x['courseName'] ?? '').toString(),
                classroom: (x['classroom'] ?? '').toString(),
                hours: (x['hours'] ?? 0) as int,
              ),
            );

            // Support both "single arrays in one doc" OR "per-day docs"
            final hasArrays = x['dayOfWeek'] is List && x['startTime'] is List && x['endTime'] is List;
            if (hasArrays) {
              final days = List<int>.from(x['dayOfWeek']);
              final starts = List<int>.from(x['startTime']);
              final ends = List<int>.from(x['endTime']);
              for (int i = 0; i < days.length; i++) {
                g.sessions.add(_Session(days[i], starts[i], ends[i]));
              }
            } else {
              // per-day doc
              final day = (x['dayOfWeek'] ?? 0) as int;
              final start = (x['startTime'] ?? 0) as int;
              final end = (x['endTime'] ?? 0) as int;
              g.sessions.add(_Session(day, start, end));
            }
          }

          // Sort sessions inside each group by day/time
          for (final g in groups.values) {
            g.sessions.sort((a, b) {
              final c = a.day.compareTo(b.day);
              return c != 0 ? c : a.start.compareTo(b.start);
            });
          }

          final groupedList = groups.values.toList()
            ..sort((a, b) => a.courseCode.compareTo(b.courseCode));

          return ListView.builder(
            itemCount: groupedList.length,
            itemBuilder: (_, i) {
              final g = groupedList[i];
              final timesText = g.sessions.map((s) =>
                  '${_dowNames[s.day]} | ${_fmtTime(s.start)} - ${_fmtTime(s.end)}'
              ).join('\n');

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(
                    '${g.courseCode} - Section ${g.section}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${g.courseName}\nRoom ${g.classroom}\n$timesText'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmDelete(g.section),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------- grouping models (local to this file) ----------
class _SectionGroup {
  final String section;
  final String courseCode;
  final String courseName;
  final String classroom;
  final int hours;
  final List<_Session> sessions = [];

  _SectionGroup({
    required this.section,
    required this.courseCode,
    required this.courseName,
    required this.classroom,
    required this.hours,
  });
}

class _Session {
  final int day;
  final int start;
  final int end;
  _Session(this.day, this.start, this.end);
}
