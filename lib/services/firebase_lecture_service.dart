import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lecture.dart';

class FirebaseLectureService {
  // keep as a getter to avoid early init issues
  static CollectionReference<Map<String, dynamic>> get _timetables =>
      FirebaseFirestore.instance.collection('timetables');

  /// OLD: unchanged (still returns a single Lecture using the first slot)
  static Future<Lecture?> getLectureBySection(String section) async {
    final trimmed = section.trim();
    if (trimmed.isEmpty) return null;

    final q = await _timetables
        .where('section', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;

    final doc = q.docs.first;
    final data = doc.data();

    // if arrays exist, take the first slot to preserve old behavior
    int _first(List? list, int fallback) {
      if (list == null || list.isEmpty) return fallback;
      final v = list.first;
      return (v is num) ? v.toInt() : fallback;
    }

    final dayList  = (data['dayOfWeek'] as List?) ?? const [];
    final startList= (data['startTime'] as List?) ?? const [];
    final endList  = (data['endTime'] as List?) ?? const [];

    return Lecture(
      id: doc.id,
      courseCode: (data['courseCode'] ?? '').toString(),
      courseName: (data['courseName'] ?? '').toString(),
      section: (data['section'] ?? '').toString(),
      classroom: (data['classroom'] ?? '').toString(),
      dayOfWeek: _first(dayList, 0),
      startTime: _first(startList, 0),
      endTime: _first(endList, 0),
      hour: (data['hour'] as num?)?.toInt() ?? 0,

    );
  }

  /// NEW: returns one Lecture per (dayOfWeek[i], startTime[i], endTime[i])
  static Future<List<Lecture>> getLecturesBySectionMulti(String section) async {
    final trimmed = section.trim();
    if (trimmed.isEmpty) return [];

    final q = await _timetables
        .where('section', isEqualTo: trimmed)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return [];

    final doc = q.docs.first;
    final data = doc.data();

    final List dayList   = List.from(data['dayOfWeek'] ?? const []);
    final List startList = List.from(data['startTime'] ?? const []);
    final List endList   = List.from(data['endTime'] ?? const []);

    // use the shortest length to stay safe
    final len = [dayList.length, startList.length, endList.length]
        .reduce((a, b) => a < b ? a : b);

    final results = <Lecture>[];
    for (var i = 0; i < len; i++) {
      results.add(
        Lecture(
          id: doc.id, // base id; we’ll make per-day ids when saving
          courseCode: (data['courseCode'] ?? '').toString(),
          courseName: (data['courseName'] ?? '').toString(),
          section: (data['section'] ?? '').toString(),
          classroom: (data['classroom'] ?? '').toString(),
          dayOfWeek: (dayList[i] as num?)?.toInt() ?? 0,
          startTime: (startList[i] as num?)?.toInt() ?? 0,
          endTime: (endList[i] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return results;
  }
}
