import 'package:flutter/foundation.dart';
import '../models/lecture.dart';

class ScheduleProvider with ChangeNotifier {
  final List<Lecture> _lectures = [];

  List<Lecture> get lectures => List.unmodifiable(_lectures);

  /// Add a lecture to the schedule
  void addLecture(Lecture lecture) {
    _lectures.add(lecture);
    notifyListeners();
  }

  /// Remove a lecture by its id
  void removeLecture(String id) {
    _lectures.removeWhere((lecture) => lecture.id == id);
    notifyListeners();
  }

  /// Update an existing lecture
  void updateLecture(Lecture updated) {
    final index = _lectures.indexWhere((l) => l.id == updated.id);
    if (index != -1) {
      _lectures[index] = updated;
      notifyListeners();
    }
  }

  /// Clear all lectures
  void clearLectures() {
    _lectures.clear();
    notifyListeners();
  }
}
