// lib/services/absence_calculator.dart 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/lecture.dart';

/// Computes absence percentage for a course using your Lecture model.
/// We count only lectures that exist in the schedule.
/// - Present is default (no Firestore doc).
/// - We store exceptions: 'absent'.
/// - Percentage = ABSENT / TOTAL_SCHEDULED * 100
class AbsenceCalculator {
  /// Compute absence % and (optionally) show a local notification if > 20%.
  static Future<double> computeAndNotify({
    required String courseId,
    required List<Lecture> allLectures,
    bool notify = true,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0.0;

    // Normalize course id for robust matching (e.g., "CS 101" == "CS101")
    final norm = _normalizeCourse(courseId);

    // 1) Filter lectures that belong to this course
    final courseLectures = allLectures
        .where((l) => _normalizeCourse(l.courseCode) == norm)
        .toList();

    if (courseLectures.isEmpty) return 0.0;

    // 2) Load exceptions from Firestore (users/{uid}/absences)
    final exceptions = await _loadExceptions(uid, norm);

    // 3) Count absent for existing schedule items only
    int absent = 0;
    for (final lec in courseLectures) {
      final status = exceptions[lec.id];
      if (status == 'absent') absent++;
    }

    // 4) Denominator = total scheduled sessions
    final total = courseLectures.length;
    if (total <= 0) return 0.0;

    final pct = absent * 100.0 / total;

    // 5) Optional local notification

    return pct;
  }

  /// Convenience wrapper when you just need the percentage (no notification).
  static Future<double> computePercent({
    required String courseId,
    required List<Lecture> allLectures,
  }) =>
      computeAndNotify(courseId: courseId, allLectures: allLectures, notify: false);

  // ---------- helpers ----------

  static String _normalizeCourse(String value) =>
      value.toUpperCase().replaceAll(' ', '');

  /// Returns map of eventId -> status ('absent'), scoped to course.
  static Future<Map<String, String>> _loadExceptions(
      String uid, String courseIdNormalized) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('absences')
        .where('courseCode', isEqualTo: courseIdNormalized)
        .get();

    final map = <String, String>{};
    for (final d in snap.docs) {
      final data = d.data();
      final status = (data['status'] ?? '').toString();
      map[d.id] = status;
    }
    return map;
  }
}
