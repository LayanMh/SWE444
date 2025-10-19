// lib/services/absence_calculator.dart 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/lecture.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // 5) Local notification removed (no alerts on thresholds).

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

  /// Compute absence % for a course by reading Firestore directly (no lecture list needed).
  /// Denominator is the number of scheduled occurrences up to now based on user's lectures.
  static Future<double> computePercentFromFirestore({required String courseId}) async {
    final docId = await _resolveUserDocIdOrNull();
    if (docId == null || docId.isEmpty) return 0.0;

    final norm = _normalizeCourse(courseId);

    // 1) Count absences for this course (exceptions stored as 'absent').
    final absSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(docId)
        .collection('absences')
        .where('courseCode', isEqualTo: norm)
        .get();
    final absent = absSnap.docs.length;

    // 2) Compute denominator from lectures by counting weekly occurrences since a start date.
    final lectSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(docId)
        .collection('lectures')
        .where('courseCode', isEqualTo: norm)
        .get();

    var lectDocs = lectSnap.docs;
    if (lectDocs.isEmpty) {
      final root = await FirebaseFirestore.instance
          .collection('lectures')
          .where('courseCode', isEqualTo: norm)
          .get();
      lectDocs = root.docs;
    }

    if (lectDocs.isEmpty) return 0.0;

    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 9, 1);
    int total = 0;
    for (final d in lectDocs) {
      final data = d.data();
      final int dayOfWeek = (data['dayOfWeek'] as num?)?.toInt() ?? 0; // 0..6
      total += _countWeekdayOccurrences(startOfYear, now, dayOfWeek);
    }

    if (total <= 0) return 0.0;
    return absent * 100.0 / total;
  }

  static int _countWeekdayOccurrences(DateTime from, DateTime to, int weekdayZeroBased) {
    final target = ((weekdayZeroBased % 7) + 1); // DateTime.weekday: 1=Mon..7=Sun
    var first = from;
    while (first.weekday != target) {
      first = first.add(const Duration(days: 1));
    }
    if (first.isAfter(to)) return 0;
    final days = to.difference(first).inDays;
    return (days ~/ 7) + 1;
  }

  // Mirrors AttendanceService._resolveUserDocId logic.
  static Future<String?> _resolveUserDocIdOrNull() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) return uid;
    final prefs = await SharedPreferences.getInstance();
    final fallbackId = prefs.getString('microsoft_user_doc_id');
    return fallbackId;
  }
}
