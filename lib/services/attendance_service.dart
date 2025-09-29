import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AttendanceService {
  static final _db = FirebaseFirestore.instance;

  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // WRITE: exceptions only (you already have something like this)
  static Future<void> mark({
    required String courseId,
    required String eventId,
    required String status, // absent | cancelled | present (clear)
    required String title,
    required DateTime start,
    required DateTime end,
  }) async {
    final ref = _db.collection('users').doc(_uid)
                   .collection('absences').doc(eventId);

    if (status == 'present') {
      await ref.delete(); // back to default
    } else {
      await ref.set({
        'status': status,
        'courseCode': courseId,
        'eventSummary': title,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // READ: all exception docs for a course (map eventId -> status)
  static Future<Map<String, String>> getCourseExceptions(String courseId) async {
    final q = await _db.collection('users').doc(_uid)
      .collection('absences')
      .where('courseCode', isEqualTo: courseId)
      .get();

    final map = <String, String>{};
    for (final d in q.docs) {
      final status = (d.data()['status'] ?? '').toString();
      map[d.id] = status;
    }
    return map;
  }

  // Optional: remember we already warned at/above a given threshold
  static Future<bool> shouldWarn(String courseId, double pct) async {
    final ref = _db.collection('users').doc(_uid)
      .collection('alerts').doc('attendance_$courseId');

    final snap = await ref.get();
    final last = (snap.data()?['lastPct'] ?? 0).toDouble();
    if (pct > 20 && pct > last) {
      await ref.set({'lastPct': pct}, SetOptions(merge: true));
      return true;
    }
    return false;
  }
}
