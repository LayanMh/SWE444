import 'package:flutter/foundation.dart';

class NotiService {
  NotiService._();

  static bool _inited = false;

  // Notifications disabled: keep API but do nothing.
  static Future<void> initialize() async {
    _inited = true;
  }

  static Future<void> showAbsenceAlert(String courseId, double pct) async {
    if (!_inited) {
      try {
        await initialize();
      } catch (_) {}
    }
    // No-op (notifications suppressed on all platforms, including web)
    return;
  }
}
