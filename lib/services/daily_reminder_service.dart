import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'absence_calculator.dart';

class DailyReminderService {
  DailyReminderService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'daily_attendance_reminders';
  static const String _channelName = 'Daily Attendance Reminders';
  static const String _channelDesc = 'Reminds at 6 PM if tomorrow risk > 20%';

  static const int _notifId = 6001; // fixed id for the 6 PM reminder

  static bool _inited = false;

  static Future<void> initialize() async {
    if (_inited) return;
    if (kIsWeb) {
      _inited = true;
      return; // no local notifications on web
    }

    // Timezone data for zoned scheduling
    try {
      tzdata.initializeTimeZones();
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('abesherk');
    
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      enableLights: true,
      enableVibration: true,
      showBadge: true,
    );
    await androidImpl?.createNotificationChannel(channel);

    _inited = true;
  }

  /// Schedule a notification for the next 6 PM local time IF any course
  /// scheduled tomorrow has absence % > 20.
  static Future<void> schedule6pmForTomorrowIfNeeded() async {
    if (!_inited) {
      try {
        await initialize();
      } catch (_) {}
    }
    if (kIsWeb) return; // no-op on web

    // Schedule for 18:00 UTC (converted to device local time)
    final nowUtc = DateTime.now().toUtc();
    final sixUtcToday = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 18);
    final targetUtc = nowUtc.isBefore(sixUtcToday)
        ? sixUtcToday
        : sixUtcToday.add(const Duration(days: 1));
    final tz.TZDateTime scheduleTime = tz.TZDateTime.from(targetUtc, tz.local);

    final List<_CourseRisk> risks = await _computeTomorrowRisks();

    if (risks.isEmpty) {
      // Nothing to warn about: cancel any previous reminder.
      try {
        await _plugin.cancel(_notifId);
      } catch (_) {}
      return;
    }

    final body = _formatBody(risks);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Attendance reminder',
        icon: 'abesherk',
      ),
      iOS: const DarwinNotificationDetails(),
    );

    try {
      // Cancel previous scheduled one so we don’t queue duplicates.
      await _plugin.cancel(_notifId);
    } catch (_) {}

    try {
      await _plugin.zonedSchedule(
        _notifId,
        'Attendance Reminder',
        body,
        scheduleTime,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'reminder:tomorrow_risk',
      );
    } catch (_) {
      // Best-effort only
    }
  }

  // -------- helpers --------

  /// Schedules a one-off debug notification 10 seconds from now to verify
  /// that notifications are working on the device/emulator.
  static Future<void> debugPingIn10s() async {
    await initialize();
    if (kIsWeb) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Debug ping',
        icon: 'abesherk',
      ),
      iOS: const DarwinNotificationDetails(),
    );

    // Always show one immediately to verify permissions/wiring.
    try {
      await _plugin.show(
        9997,
        'Debug Ping',
        'Immediate test notification.',
        details,
        payload: 'debug:show_now',
      );
    } catch (_) {}
  }

  /// Immediately shows whether a 6 PM UTC reminder would be scheduled today
  /// and lists tomorrow's at-risk courses (>20%). This does NOT schedule.
  static Future<void> debugReportTomorrowRiskNow() async {
    await initialize();
    if (kIsWeb) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Reminder status',
        icon: 'abesherk',
      ),
      iOS: const DarwinNotificationDetails(),
    );

    // Compute target 18:00 UTC converted to local (same as scheduler)
    final nowUtc = DateTime.now().toUtc();
    final sixUtcToday = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 13);
    final targetUtc = nowUtc.isBefore(sixUtcToday)
        ? sixUtcToday
        : sixUtcToday.add(const Duration(days: 1));
    final localWhen = tz.TZDateTime.from(targetUtc, tz.local);

    final risks = await _computeTomorrowRisks();
    final body = risks.isEmpty
        ? 'No reminder: no courses >20% for tomorrow.'
        : _formatBody(risks) + ' | Fires ~ ' + _fmt(localWhen);

    try {
      await _plugin.show(
        9996,
        risks.isEmpty ? 'Reminder Status: Not Scheduled' : 'Reminder Status: Scheduled',
        body,
        details,
        payload: 'debug:status',
      );
    } catch (_) {}
  }

  static String _fmt(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  static Future<List<_CourseRisk>> _computeTomorrowRisks() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return const [];

      // Determine tomorrow’s weekday in 0..6 (0=Sun)
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final dayOfWeekZeroBased = (tomorrow.weekday % 7); // Mon=1..Sun=7 -> 1..0

      // Read user schedule for tomorrow (handle both 0..6 and 1..7 encodings)
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
      final oneBased = ((dayOfWeekZeroBased + 1) <= 7) ? (dayOfWeekZeroBased + 1) : 1;

      // users/{uid}/schedule
      try {
        final a = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('schedule')
            .where('dayOfWeek', isEqualTo: dayOfWeekZeroBased)
            .get();
        docs.addAll(a.docs);
      } catch (_) {}
      try {
        final b = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('schedule')
            .where('dayOfWeek', isEqualTo: oneBased)
            .get();
        for (final d in b.docs) {
          if (!docs.any((x) => x.id == d.id)) docs.add(d);
        }
      } catch (_) {}

      // users/{uid}/lectures
      try {
        final c = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('lectures')
            .where('dayOfWeek', isEqualTo: dayOfWeekZeroBased)
            .get();
        for (final d in c.docs) {
          if (!docs.any((x) => x.id == d.id)) docs.add(d);
        }
      } catch (_) {}
      try {
        final d = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('lectures')
            .where('dayOfWeek', isEqualTo: oneBased)
            .get();
        for (final e in d.docs) {
          if (!docs.any((x) => x.id == e.id)) docs.add(e);
        }
      } catch (_) {}

      // Optional root fallback
      if (docs.isEmpty) {
        try {
          final e = await FirebaseFirestore.instance
              .collection('lectures')
              .where('dayOfWeek', isEqualTo: dayOfWeekZeroBased)
              .get();
          docs.addAll(e.docs);
        } catch (_) {}
        try {
          final f = await FirebaseFirestore.instance
              .collection('lectures')
              .where('dayOfWeek', isEqualTo: oneBased)
              .get();
          for (final d in f.docs) {
            if (!docs.any((x) => x.id == d.id)) docs.add(d);
          }
        } catch (_) {}
      }

      if (docs.isEmpty) return const [];

      final Set<String> courseCodes = {
        for (final d in docs)
          (d.data()['courseCode'] ?? '').toString().toUpperCase().replaceAll(' ', '')
      }..removeWhere((e) => e.isEmpty);

      if (courseCodes.isEmpty) return const [];

      final List<_CourseRisk> risks = [];
      for (final code in courseCodes) {
        try {
          final pct = await AbsenceCalculator.computePercentFromFirestore(courseId: code);
          if (pct > 20) {
            risks.add(_CourseRisk(code, pct));
          }
        } catch (_) {}
      }
      // Highest risk first
      risks.sort((a, b) => b.pct.compareTo(a.pct));
      return risks;
    } catch (_) {
      return const [];
    }
  }

  static String _formatBody(List<_CourseRisk> risks) {
    // Show up to 3 courses to keep it short
    final top = risks.take(3).map((r) => '${r.code} (${r.pct.toStringAsFixed(1)}%)').join(', ');
    final more = risks.length > 3 ? ' +${risks.length - 3} more' : '';
    return 'Tomorrow risk > 20% for: $top$more. Be present!';
  }
}

class _CourseRisk {
  final String code;
  final double pct;
  _CourseRisk(this.code, this.pct);
}
