import 'recurring_lecture.dart';

class Lecture {
  final String id;
  final String courseCode;
  final String courseName;
  final String section;
  final String classroom;
  final int dayOfWeek;   // 0..6
  final int startTime;   // minutes since midnight
  final int endTime;     // minutes since midnight

  Lecture({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.classroom,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  /// Hard-coded semester end for now (change later)
  RecurringLecture toRecurringLecture() {
    return RecurringLecture(
      courseCode: courseCode,
      courseName: courseName,
      section: section,
      classroom: classroom,
      dayOfWeek: dayOfWeek,
      startMinutes: startTime,
      endMinutes: endTime,
      semesterEnd: DateTime(2025, 12, 31),
    );
  }
}
