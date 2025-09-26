import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lecture.dart';

class FirebaseLectureService {
  static final CollectionReference<Map<String, dynamic>> _timetables =
      FirebaseFirestore.instance.collection('timetables');

  static Future<Lecture?> getLectureBySection(String section) async {
    final trimmedSection = section.trim();
    if (trimmedSection.isEmpty) {
      return null;
    }

    final querySnapshot = await _timetables
        .where('section', isEqualTo: trimmedSection)
        .limit(1)
        .get();
    if (querySnapshot.docs.isEmpty) {
      return null;
    }

    final doc = querySnapshot.docs.first;
    final data = doc.data();

    int toInt(String key) => (data[key] as num?)?.toInt() ?? 0;

    return Lecture(
      id: data['id'] as String? ?? doc.id,
      courseCode: data['courseCode'] as String? ?? '',
      courseName: data['courseName'] as String? ?? '',
      section: data['section'] as String? ?? '',
      classroom: data['classroom'] as String? ?? '',
      dayOfWeek: toInt('dayOfWeek'),
      startTime: toInt('startTime'),
      endTime: toInt('endTime'),
    );
  }
}
