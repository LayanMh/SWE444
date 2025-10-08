// lib/services/attendance_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AttendanceService {
  AttendanceService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Throw if not signed in.
  static String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in (FirebaseAuth.currentUser is null).');
    }
    return uid;
  }

  /// Normalize course codes to a stable key (e.g. "CS 101" -> "CS101").
  static String normalizeCourseCode(String v) => v.toUpperCase().replaceAll(' ', '');

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Create/update an exception, or clear it if status == 'present'.
  static Future<void> mark({
    required String courseId,
    required String eventId,
    required String status, // 'absent' | 'present'
    required String title,
    required DateTime start,
    required DateTime end,
  }) async {
    final uid = _requireUid();
    final ref = _db.collection('users').doc(uid).collection('absences').doc(eventId);

    if (status == 'present') {
      await ref.delete(); // default state (present) → no exception doc
      return;
    }

    await ref.set({
      'courseCode': normalizeCourseCode(courseId),
      'status': status, // 'absent'
      'eventSummary': title,
      'start': Timestamp.fromDate(start),
      'end': Timestamp.fromDate(end),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Delete a single exception by eventId.
  static Future<void> clearEvent(String eventId) async {
    final uid = _requireUid();
    await _db.collection('users').doc(uid).collection('absences').doc(eventId).delete();
  }

  // ---------------------------------------------------------------------------
  // Reads / Streams
  // ---------------------------------------------------------------------------

  /// Stream ALL absence exceptions (newest first).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMyAbsences() {
    final uid = _requireUid();
    return _db
        .collection('users')
        .doc(uid)
        .collection('absences')
        .orderBy('start', descending: true)
        .snapshots();
  }

  /// Stream exceptions for one course.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamCourseAbsences(String courseId) {
    final uid = _requireUid();
    final norm = normalizeCourseCode(courseId);
    return _db
        .collection('users')
        .doc(uid)
        .collection('absences')
        .where('courseCode', isEqualTo: norm)
        .orderBy('start', descending: true)
        .snapshots();
  }

  /// One-off read of exceptions for a course (eventId -> status).
  static Future<Map<String, String>> getCourseExceptions(String courseId) async {
    final uid = _requireUid();
    final norm = normalizeCourseCode(courseId);
    final q = await _db
        .collection('users')
        .doc(uid)
        .collection('absences')
        .where('courseCode', isEqualTo: norm)
        .get();

    return {for (final d in q.docs) d.id: (d.data()['status'] ?? '').toString()};
  }

  /// Optional: throttle warnings over 20%.
  static Future<bool> shouldWarn(String courseId, double pct) async {
    final uid = _requireUid();
    final norm = normalizeCourseCode(courseId);
    final ref = _db.collection('users').doc(uid).collection('alerts').doc('attendance_$norm');

    final snap = await ref.get();
    final last = (snap.data()?['lastPct'] ?? 0).toDouble();
    if (pct > 20 && pct > last) {
      await ref.set({'lastPct': pct, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
      return true;
    }
    return false;
  }
}
