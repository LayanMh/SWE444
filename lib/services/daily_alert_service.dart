import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:absherk/services/absence_calculator.dart';
import 'package:absherk/services/noti_service.dart';

/// Computes tomorrow's schedule and absence %, then schedules a 6pm alert
/// for today when any course tomorrow exceeds 20% absence.
///
/// Limitations:
/// - Runs when called (e.g., on app start/resume). If the app hasn't run
///   before 6pm, no alert is scheduled that day unless you integrate a
///   background task (e.g., workmanager on Android).
class DailyAlertService {
  DailyAlertService._();

  /// Stable notification id so we can update/cancel the 6pm alert per day.
  static const int _kSixPmAlertId = 6001;

  /// Call from app start or foreground events to refresh the 6pm alert.
  static Future<void> evaluateAndScheduleSixPmAlert() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      // Not signed in, nothing to evaluate
      return;
    }

    try {
      final tomorrowDow = _tomorrowWeekdayZeroBased();

      // Query user's lectures for tomorrow (fallback to root if needed)
      final userLects = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('lectures')
          .where('dayOfWeek', isEqualTo: tomorrowDow)
          .get();

      var lectDocs = userLects.docs;
      if (lectDocs.isEmpty) {
        final root = await FirebaseFirestore.instance
            .collection('lectures')
            .where('dayOfWeek', isEqualTo: tomorrowDow)
            .get();
        lectDocs = root.docs;
      }

      if (lectDocs.isEmpty) {
        // No classes tomorrow; ensure any scheduled alert is canceled.
        await NotiService.cancel(_kSixPmAlertId);
        return;
      }

      // Unique normalized course codes for tomorrow
      final Set<String> courseCodes = lectDocs
          .map((d) => (d.data()['courseCode'] ?? '').toString())
          .map((c) => c.toUpperCase().replaceAll(' ', ''))
          .where((c) => c.isNotEmpty)
          .toSet();

      if (courseCodes.isEmpty) {
        await NotiService.cancel(_kSixPmAlertId);
        return;
      }

      // Compute absence % per course, collect those > 20%
      final List<_CourseAlert> risky = [];
      for (final code in courseCodes) {
        final pct = await AbsenceCalculator.computePercentFromFirestore(
            courseId: code);
        if (pct > 20.0) {
          risky.add(_CourseAlert(code: code, pct: pct));
        }
      }

      if (risky.isEmpty) {
        // Nothing over 20% for tomorrow's courses; cancel any previous alert
        await NotiService.cancel(_kSixPmAlertId);
        return;
      }

      // Prepare message listing risky courses
      risky.sort((a, b) => a.code.compareTo(b.code));
      final body = risky
          .map((e) => '${e.code}: ${e.pct.toStringAsFixed(1)}%')
          .join(' • ');

      // Schedule for the next 6pm local time (today if still upcoming)
      final DateTime now = DateTime.now();
      DateTime sixPm = DateTime(now.year, now.month, now.day, 18, 0);
      if (!sixPm.isAfter(now)) {
        sixPm = sixPm.add(const Duration(days: 1));
      }

      await NotiService.scheduleOneTime(
        id: _kSixPmAlertId,
        whenLocal: sixPm,
        title: 'Be Ready For Tomorrow',
        body: 'Absence > 20% in: $body',
      );
    } catch (_) {
      // Fail silently; do not crash app startup
    }
  }

  static int _tomorrowWeekdayZeroBased() {
    final d = DateTime.now().add(const Duration(days: 1));
    // DateTime.weekday: 1=Mon..7=Sun; we use 0..6 with 0=Mon
    return (d.weekday - 1) % 7;
  }
}

class _CourseAlert {
  _CourseAlert({required this.code, required this.pct});
  final String code;
  final double pct;
}

