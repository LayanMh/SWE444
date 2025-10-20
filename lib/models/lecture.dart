import 'recurring_lecture.dart';

class Lecture {
  final String id;
  final String courseCode;
  final String courseName;
  final String section;
  final String classroom;
  final int dayOfWeek;
  final int startTime;
  final int endTime;
  final int hours;

  Lecture({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.classroom,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.hours = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'courseCode': courseCode,
        'courseName': courseName,
        'section': section,
        'classroom': classroom,
        'dayOfWeek': dayOfWeek,
        'startTime': startTime,
        'endTime': endTime,
        'hours': hours,
      };

  ///  Converts a Lecture into a RecurringLecture (for Microsoft Calendar)
  RecurringLecture toRecurringLecture() {
    return RecurringLecture(
      courseCode: courseCode,
      courseName: courseName,
      section: section,
      classroom: classroom,
      dayOfWeek: dayOfWeek,
      startMinutes: startTime,
      endMinutes: endTime,
      semesterEnd: DateTime(2025, 12, 31), // you can later make this dynamic
    );
  }
}
