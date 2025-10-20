import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lecture.dart';

class FirebaseLectureService {
  static Future<List<Lecture>> getLectureBySection(String sectionId) async {
    // 🔹 Find document by section field, not by name
    final querySnapshot = await FirebaseFirestore.instance
        .collection('timetables')
        .where('section', isEqualTo: sectionId)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) return [];

    final data = querySnapshot.docs.first.data();

    final List<int> days = List<int>.from(data['dayOfWeek'] ?? []);
    final List<int> startTimes = List<int>.from(data['startTime'] ?? []);
    final List<int> endTimes = List<int>.from(data['endTime'] ?? []);
    final int hours = data['hours'] ?? 0;

    final lectures = <Lecture>[];

    for (int i = 0; i < days.length; i++) {
      lectures.add(
        Lecture(
          id: sectionId,
          courseCode: data['courseCode'] ?? '',
          courseName: data['courseName'] ?? '',
          section: sectionId,
          classroom: data['classroom'] ?? '',
          dayOfWeek: days[i],
          startTime: startTimes[i],
          endTime: endTimes[i],
          hours: hours,
        ),
      );
    }

    return lectures;
  }
}
