import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
// For scheduled notifications at an exact local time
// Note: add `timezone` to pubspec.yaml
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotiService {
  NotiService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'attendance_alerts';
  static const String _channelName = 'Attendance Alerts';
  static const String _channelDesc = 'Alerts when absence exceeds thresholds';

  static bool _inited = false;

  /// Initialize the local notifications plugin and request permissions.
  static Future<void> initialize() async {
    if (_inited) return;

    if (kIsWeb) {
      // Local notifications are not supported on web via this plugin.
      _inited = true;
      return;
    }

    // Initialize timezone database for precise local scheduling
    try {
      tz.initializeTimeZones();
      // Best-effort: rely on device default local zone
      // If you add flutter_native_timezone, you can set explicit location.
      // final name = await FlutterNativeTimezone.getLocalTimezone();
      // tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // continue even if timezone init fails; immediate notifications still work
    }

    // Use your custom small icon from res/drawable: abesherk.png (Android only)
    const androidInit = AndroidInitializationSettings('abesherk');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(initSettings);

    // Android: request permission and create channel when available.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
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

  /// Show an absence threshold alert (20%+).
  static Future<void> showAbsenceAlert(String courseId, double pct) async {
    // Ensure initialized
    if (!_inited) {
      try {
        await initialize();
      } catch (_) {
        // ignore
      }
    }

    if (kIsWeb) return; // no-op on web

    final percentText = pct.toStringAsFixed(1);
    final rounded = double.tryParse(percentText) ?? pct;
    String title;
    String body;
    if (rounded > 25.0) {
      title = 'Attendance At Risk';
      body = 'You exceeded the 25% limit in $courseId ($percentText%).';
    } else if ((rounded - 25.0).abs() < 0.01) {
      title = 'Attendance Limit Reached';
      body = 'You hit the 25% absence limit in $courseId ($percentText%).';
    } else {
      title = 'Attendance Warning';
      body = 'You exceeded 20% absences in $courseId ($percentText%).';
    }

    // Try with custom image (requires res/drawable/absherk_notif.png).
    final bigBitmap = const DrawableResourceAndroidBitmap('absherk_notif');
    final withImage = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Attendance alert',
        icon: 'abesherk',
        styleInformation: BigPictureStyleInformation(
          bigBitmap,
          largeIcon: bigBitmap,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: false,
        ),
      ),
    );

    // Fallback details without image (in case resource not found or style fails)
    final fallback = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Attendance alert',
        icon: 'abesherk',
      ),
    );

    // Use a time-based id so each alert shows as a new notification
    final id = (DateTime.now().millisecondsSinceEpoch % 0x7fffffff).toInt();
    try {
      await _plugin.show(id, title, body, withImage,
          payload: 'course:$courseId;pct:$percentText');
    } catch (_) {
      // Try again without the image style
      await _plugin.show(id, title, body, fallback,
          payload: 'course:$courseId;pct:$percentText');
    }
  }

  /// Schedule a one-time local notification at a specific local DateTime.
  /// Uses a stable `id` so we can update/cancel it later.
  static Future<void> scheduleOneTime({
    required int id,
    required DateTime whenLocal,
    required String title,
    required String body,
  }) async {
    if (!_inited) {
      try {
        await initialize();
      } catch (_) {}
    }
    if (kIsWeb) return;

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Attendance alert',
        icon: 'abesherk',
      ),
    );

    try {
      final tzTime = tz.TZDateTime.from(whenLocal, tz.local);
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'scheduled:true',
      );
    } catch (_) {
      // If scheduling fails (e.g., timezone not available), fall back to showing immediately
      await _plugin.show(id, title, body, details, payload: 'fallback:true');
    }
  }

  /// Cancel a scheduled notification by id.
  static Future<void> cancel(int id) async {
    if (!_inited) {
      try {
        await initialize();
      } catch (_) {}
    }
    if (kIsWeb) return;
    await _plugin.cancel(id);
  }
}
