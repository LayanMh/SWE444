class RecurringLecture {
  final String courseCode;
  final String courseName;
  final String section;
  final String classroom;

  /// 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  final int dayOfWeek;

  /// Minutes since midnight (e.g., 08:00 → 480)
  final int startMinutes;
  final int endMinutes;

  /// When to stop the weekly recurrence in Google Calendar
  final DateTime semesterEnd;

  const RecurringLecture({
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.classroom,
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    required this.semesterEnd,
  });
}
