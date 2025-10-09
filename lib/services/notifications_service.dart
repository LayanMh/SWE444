import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import '../models/lecture.dart';

class NotiService {
  final notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  // INITIALIZE
  Future<void> initNotification() async {
    if (_isInitialized) return; // prevent re-initialization

    const initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
      android: initSettingsAndroid,
    );

    await notificationsPlugin.initialize(initSettings);

    // Request permissions where needed
    try {
      await notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}

    _isInitialized = true;
  }

  // NOTIFICATIONS DETAIL SETUP
  NotificationDetails notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_channel_id',
        'Daily Notifications',
        channelDescription: 'Daily Notification Channel',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );
  }

  // SHOW NOTIFICATION
  Future<void> showNotification({
    int id = 0,
    String? title,
    String? body,
  }) async {
    return notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails(),
    );
  }

  // Schedule a one-shot notification at a specific time
  Future<void> scheduleAt({
    required int id,
    required DateTime when,
    String? title,
    String? body,
  }) async {
    // If time already passed, skip
    if (when.isBefore(DateTime.now().add(const Duration(seconds: 10)))) return;
    await notificationsPlugin.schedule(
      id,
      title,
      body,
      when,
      notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'daily_summary',
    );
  }

  // Compute and schedule daily summaries for the next N days
  Future<void> scheduleDailySummariesForNextDays({
    required List<Lecture> lectures,
    int daysAhead = 7,
    int minutesAfterEnd = 10,
  }) async {
    final now = DateTime.now();
    for (int i = 0; i < daysAhead; i++) {
      final date = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final modelDow = date.weekday % 7; // Map DateTime weekday (Mon=1..Sun=7) to 0..6 with Sun=0

      final todaysLectures = lectures.where((l) => l.dayOfWeek == modelDow).toList();
      if (todaysLectures.isEmpty) continue;

      final lastEndMinutes = todaysLectures.map((l) => l.endTime).reduce((a, b) => a > b ? a : b);
      final scheduled = DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: lastEndMinutes + minutesAfterEnd));

      final id = _dailySummaryIdForDate(date);
      await scheduleAt(
        id: id,
        when: scheduled,
        title: 'Daily Summary',
        body: 'Your day is done — check attendance summary.',
      );
    }
  }

  Future<void> cancelDailySummariesForNextDays({int daysAhead = 7}) async {
    final now = DateTime.now();
    for (int i = 0; i < daysAhead; i++) {
      final date = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final id = _dailySummaryIdForDate(date);
      await notificationsPlugin.cancel(id);
    }
  }

  int _dailySummaryIdForDate(DateTime date) {
    // Unique but deterministic per date: 88 + yyyymmdd
    final yyyymmdd = date.year * 10000 + date.month * 100 + date.day;
    return 88000000 + yyyymmdd;
  }
  // ON NOTI TAP
}
