import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

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

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
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

    if (kIsWeb) return; // no-op on web

    final percentText = pct.toStringAsFixed(1);
    final title = 'Attendance Warning';
    final body =
        'You exceeded 20% absences in $courseId ($percentText%).';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Attendance alert',
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Use a deterministic id per course to avoid stacking too many
    final id = courseId.hashCode & 0x7fffffff;
    await _plugin.show(id, title, body, details,
        payload: 'course:$courseId;pct:$percentText');
  }
}
