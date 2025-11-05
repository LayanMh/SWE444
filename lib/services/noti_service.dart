import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotiService {
  NotiService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'attendance_alerts';
  static const String _channelName = 'Attendance Alerts';
  static const String _channelDesc = 'Alerts when absence exceeds thresholds';

  static bool _inited = false;

  /// Normalize a display name for swap notifications.
  ///
  /// - Trims whitespace.
  /// - Falls back to "A student" when empty.
  /// - Uses the first token when multiple names are present so the alert reads naturally.
  static String formatDisplayName(
    String? rawName, {
    String fallback = 'A student',
  }) {
    final trimmed = rawName?.trim();
    if (trimmed == null || trimmed.isEmpty) return fallback;
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts.isNotEmpty && parts.first.isNotEmpty ? parts.first : (trimmed.isNotEmpty ? trimmed : fallback);
  }

  /// Initialize the local notifications plugin and request permissions.
  static Future<void> initialize() async {
    if (_inited) return;

    if (kIsWeb) {
      // Local notifications are not supported on web via this plugin.
      _inited = true;
      return;
    }

    // Use your custom small icon from res/drawable: abesherk.png
    const androidInit = AndroidInitializationSettings('abesherk');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

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

    // iOS: request permissions via implementation when available.
    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

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

    final percentText = pct.toStringAsFixed(1);
    final rounded = double.tryParse(percentText) ?? pct;
    String title;
    String body;
    if (rounded > 25.0) {
      title = 'Attendance Limit Reached';
      body = 'Absences in $courseId reached $percentText% (over the 25% limit) You’ve got this!! let’s aim for the next classes';
    } else if ((rounded - 25.0).abs() < 0.01) {
      title = 'Heads Up on your Attendance!!';
      body = 'Absences in $courseId are now $percentText% Let’s keep future classes on track!';
    } else {
      title = 'Heads Up on your Attendance!!Let’s Get Back on Track';
      body = 'Absences in $courseId are $percentText% getting close to 25%!! Keeping up this week will keep you safe 👍';
    }

    await _showStyledNotification(
      title: title,
      body: body,
      ticker: 'Attendance alert',
      payload: 'course:$courseId;pct:$percentText',
    );
  }

  /// Show a local notification related to swap activity.
  static Future<void> showSwapAlert({
    required String title,
    required String body,
  }) async {
    if (!_inited) {
      try {
        await initialize();
      } catch (_) {
        // ignore initialization failures for swap alerts
      }
    }

    await _showStyledNotification(
      title: title,
      body: body,
      ticker: 'Swap notification',
      payload: 'swap',
    );
  }

  static Future<void> _showStyledNotification({
    required String title,
    required String body,
    required String ticker,
    required String payload,
  }) async {
    if (kIsWeb) return;

    final bigBitmap = const DrawableResourceAndroidBitmap('absherk_notif');
    final richDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: ticker,
        icon: 'abesherk',
        styleInformation: BigPictureStyleInformation(
          bigBitmap,
          largeIcon: bigBitmap,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: false,
        ),
      ),
      iOS: const DarwinNotificationDetails(),
    );

    final fallback = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: ticker,
        icon: 'abesherk',
      ),
      iOS: const DarwinNotificationDetails(),
    );

    final id = (DateTime.now().millisecondsSinceEpoch % 0x7fffffff).toInt();
    try {
      await _plugin.show(id, title, body, richDetails, payload: payload);
    } catch (error) {
      try {
        await _plugin.show(id, title, body, fallback, payload: payload);
      } catch (fallbackError) {
        debugPrint(
          "❌ Failed to display local notification ($ticker): $fallbackError (primary error: $error)",
        );
      }
    }
  }

}
