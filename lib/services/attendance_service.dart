// lib/services/attendance_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:absherk/services/absence_calculator.dart';
import 'package:absherk/services/noti_service.dart';

class AttendanceService {
  AttendanceService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Determine the Firestore doc id for the current user.
  static Future<String> _resolveUserDocId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      return uid;
    }

    final prefs = await SharedPreferences.getInstance();
    final fallbackId = prefs.getString('microsoft_user_doc_id');
    if (fallbackId != null && fallbackId.isNotEmpty) {
      return fallbackId;
    }

    throw StateError('Not signed in (no Firebase or Microsoft session found).');
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
    final docId = await _resolveUserDocId();
    final ref =
        _db.collection('users').doc(docId).collection('absences').doc(eventId);

    if (status == 'present') {
      await ref.delete(); // default state (present) -> no exception doc
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

    // After marking absent, compute fresh percentage and alert if over thresholds.
    try {
      final pct = await AbsenceCalculator.computePercentFromFirestore(courseId: courseId);
      if (pct > 20) {
        await NotiService.showAbsenceAlert(courseId, pct);
      }
    } catch (_) {
      // Do not fail the write flow if notification fails
    }
  }

  /// Delete a single exception by eventId.
  static Future<void> clearEvent(String eventId) async {
    final docId = await _resolveUserDocId();
    await _db
        .collection('users')
        .doc(docId)
        .collection('absences')
        .doc(eventId)
        .delete();
  }

  // ---------------------------------------------------------------------------
  // Reads / Streams
  // ---------------------------------------------------------------------------

  /// Stream ALL absence exceptions (newest first).
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMyAbsences() {
    return Stream.fromFuture(_resolveUserDocId()).asyncExpand((docId) {
      return _db
          .collection('users')
          .doc(docId)
          .collection('absences')
          .orderBy('start', descending: true)
          .snapshots();
    });
  }

  /// Stream exceptions for one course.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamCourseAbsences(String courseId) {
    final norm = normalizeCourseCode(courseId);
    return Stream.fromFuture(_resolveUserDocId()).asyncExpand((docId) {
      return _db
          .collection('users')
          .doc(docId)
          .collection('absences')
          .where('courseCode', isEqualTo: norm)
          .orderBy('start', descending: true)
          .snapshots();
    });
  }

  /// One-off read of exceptions for a course (eventId -> status).
  static Future<Map<String, String>> getCourseExceptions(String courseId) async {
    final docId = await _resolveUserDocId();
    final norm = normalizeCourseCode(courseId);
    final q = await _db
        .collection('users')
        .doc(docId)
        .collection('absences')
        .where('courseCode', isEqualTo: norm)
        .get();

    return {for (final d in q.docs) d.id: (d.data()['status'] ?? '').toString()};
  }

  /// Optional: throttle warnings over 20%.
  static Future<bool> shouldWarn(String courseId, double pct) async {
    final docId = await _resolveUserDocId();
    final norm = normalizeCourseCode(courseId);
    final ref = _db.collection('users').doc(docId).collection('alerts').doc('attendance_$norm');

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
