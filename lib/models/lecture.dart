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
  final int hour;        //  course credit hours

  Lecture({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.classroom,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.hour = 0,       //  default 
  });

  /// Factory constructor to create Lecture from Firestore document
  factory Lecture.fromFirestore(Map<String, dynamic> data, String id) {
    return Lecture(
      id: id,
      courseCode: data['courseCode'] ?? 'UNKNOWN',
      courseName: data['courseName'] ?? 'Untitled',
      section: data['section'] ?? '',
      classroom: data['classroom'] ?? '',
      dayOfWeek: (data['dayOfWeek'] as List?)?.first ?? 0, // handles list
      startTime: (data['startTime'] as List?)?.first ?? 0, // handles list
      endTime: (data['endTime'] as List?)?.first ?? 0,     // handles list
      hour: (data['hour'] as num?)?.toInt() ?? 0,          // added
    );
  }

  /// Convert to recurring lecture for Microsoft Calendar
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
