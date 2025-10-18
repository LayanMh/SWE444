// lib/services/attendance_totals.dart
import 'package:flutter/foundation.dart';

/// Simple singleton to share per-course total scheduled counts and minutes
/// computed by CalendarScreen with other parts of the app (e.g., AbsencePage).
class AttendanceTotals {
  AttendanceTotals._();
  static final AttendanceTotals instance = AttendanceTotals._();

  /// Map of normalized courseCode -> total scheduled events (count).
  /// Normalization should match CalendarScreen's `_resolveCourseId` and
  /// AbsencePage grouping (uppercase, no spaces, e.g., CS101).
  final ValueNotifier<Map<String, int>> totalsByCourse =
      ValueNotifier<Map<String, int>>({});

  /// Map of normalized courseCode -> total scheduled minutes.
  final ValueNotifier<Map<String, int>> totalMinutesByCourse =
      ValueNotifier<Map<String, int>>({});

  void setTotals(Map<String, int> totals) {
    totalsByCourse.value = Map.unmodifiable(totals);
  }

  void setTotalsMinutes(Map<String, int> totalsMinutes) {
    totalMinutesByCourse.value = Map.unmodifiable(totalsMinutes);
  }

  void clear() {
    totalsByCourse.value = const {};
    totalMinutesByCourse.value = const {};
  }
}

