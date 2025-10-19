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
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
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

    final iosImpl =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

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
    final sixUtcToday = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 8);
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

    // Also schedule one ~10s later (may be delayed on inexact mode/Doze).
    final when = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10));
    try {
      await _plugin.zonedSchedule(
        9998,
        'Debug Ping (Scheduled)',
        'This should arrive around 10s later.',
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'debug:ping10s',
      );
    } catch (_) {}
  }

  static Future<List<_CourseRisk>> _computeTomorrowRisks() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return const [];

      // Determine tomorrow’s weekday in 0..6 (0=Sun)
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final dayOfWeekZeroBased = (tomorrow.weekday % 7); // Mon=1..Sun=7 -> 1..0

      // Read user schedule for tomorrow
      final userLectures = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('lectures')
          .where('dayOfWeek', isEqualTo: dayOfWeekZeroBased)
          .get();

      var docs = userLectures.docs;
      if (docs.isEmpty) {
        // Optional fallback to root collection
        final fallback = await FirebaseFirestore.instance
            .collection('lectures')
            .where('dayOfWeek', isEqualTo: dayOfWeekZeroBased)
            .get();
        docs = fallback.docs;
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
