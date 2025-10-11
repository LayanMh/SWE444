import 'package:intl/intl.dart';

/// Normalized weekly meeting pattern for one section occurrence.
class MeetingPattern {
  /// ISO weekday 1..7 (Mon=1 .. Sun=7)
  final int weekday;
  /// Start time in HHmm (e.g., 0800)
  final String startHHmm;
  /// End time in HHmm (e.g., 0920)
  final String endHHmm;
  /// Classroom location (e.g., B12-123)
  final String classroom;

  MeetingPattern({
    required this.weekday,
    required this.startHHmm,
    required this.endHHmm,
    required this.classroom,
  });
}

/// Data extracted from the official timetable for a specific section.
class TimetableResult {
  /// Normalized, uppercase course code without spaces (e.g., CS101)
  final String courseCode;
  final String courseName;
  final String section;
  final DateTime termStart; // inclusive, local date at 00:00
  final DateTime termEnd;   // inclusive, local date at 23:59
  final List<MeetingPattern> meetings;

  TimetableResult({
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.termStart,
    required this.termEnd,
    required this.meetings,
  });
}

/// Implementations fetch and parse the official timetable page.
abstract class TimetableProvider {
  /// Fetch timetable for the given identifiers. Return null if not found.
  /// `courseCode` is optional; if omitted, the provider should infer it
  /// from the page based on `section`.
  Future<TimetableResult?> fetch({
    String? courseCode,
    required String section,
  });
}

/// Utility to parse HHmm (e.g., "0800") into Duration from midnight.
Duration parseHHmm(String hhmm) {
  final normalized = hhmm.padLeft(4, '0');
  final h = int.parse(normalized.substring(0, 2));
  final m = int.parse(normalized.substring(2, 4));
  return Duration(hours: h, minutes: m);
}

/// Compose local DateTime from a base date and HHmm time.
DateTime atLocalTime(DateTime date, String hhmm) {
  final d = parseHHmm(hhmm);
  return DateTime(date.year, date.month, date.day, d.inHours, d.inMinutes % 60);
}

/// Format YYYY-MM-DD.
String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
