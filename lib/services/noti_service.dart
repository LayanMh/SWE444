import 'package:cloud_firestore/cloud_firestore.dart';
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

    if (kIsWeb) return; // no-op on web

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
      iOS: const DarwinNotificationDetails(),
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
      iOS: const DarwinNotificationDetails(),
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

  /// Enqueue a remote push notification for the specified user.
  ///
  /// This looks up the user's stored FCM tokens and writes a notification job
  /// into Firestore so the backend worker can fan out the push. Falls back to
  /// logging if no token is found.
  static Future<void> sendNotificationToUser(
    String userId, {
    required String title,
    required String body,
  }) async {
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final data = userDoc.data();
      if (data == null) {
        debugPrint("⚠️ No user document found for $userId; skipping notification.");
        return;
      }

      final tokens = <String>{};
      final tokenField = data['fcmToken'];
      final tokensField = data['fcmTokens'];
      if (tokenField is String && tokenField.isNotEmpty) tokens.add(tokenField);
      if (tokensField is Iterable) {
        tokens.addAll(tokensField.whereType<String>().where((t) => t.isNotEmpty));
      }

      if (tokens.isEmpty) {
        debugPrint("⚠️ No FCM tokens stored for $userId; cannot send notification.");
        return;
      }

      await FirebaseFirestore.instance.collection('push_notifications').add({
        'userId': userId,
        'tokens': tokens.toList(),
        'title': title,
        'body': body,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      debugPrint("📩 Enqueued push notification for $userId");
    } catch (e) {
      debugPrint("❌ Failed to enqueue notification for $userId: $e");
    }
  }
}
