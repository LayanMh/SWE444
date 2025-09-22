import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/lecture.dart';
import '../models/recurring_lecture.dart';

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

class GoogleCalendarService {
  static Future<void> addWeeklyRecurringLecture({
    required GoogleSignInAccount account,
    required RecurringLecture lecture,
    String calendarId = 'primary',
    String timeZoneId = 'Asia/Riyadh',
  }) async {
    final headers = await account.authHeaders;
    final client = GoogleAuthClient(headers);
    final api = calendar.CalendarApi(client);

    try {
      final startLocal = _nextOccurrenceLocal(
        dayOfWeek: lecture.dayOfWeek,
        minutes: lecture.startMinutes,
      );
      final duration = Duration(
        minutes: lecture.endMinutes - lecture.startMinutes,
      );
      final endLocal = startLocal.add(duration);

      final untilUtc = _endOfDayUtc(lecture.semesterEnd);
      final rrule = 'RRULE:FREQ=WEEKLY;UNTIL=${_formatUtcForRRule(untilUtc)}';

      final event = calendar.Event(
        summary: '${lecture.courseCode} - ${lecture.courseName}',
        location: lecture.classroom.isNotEmpty ? lecture.classroom : null,
        description: 'Section ${lecture.section}',
        start: calendar.EventDateTime(dateTime: startLocal, timeZone: timeZoneId),
        end: calendar.EventDateTime(dateTime: endLocal, timeZone: timeZoneId),
        recurrence: [rrule],
      );

      await api.events.insert(event, calendarId);
    } finally {
      client.close();
    }
  }

  static DateTime _nextOccurrenceLocal({required int dayOfWeek, required int minutes}) {
    final now = DateTime.now();
    final todayIdx = now.weekday % 7; // Mon=1..Sun=7 mapped to 0..6
    final diff = (dayOfWeek - todayIdx + 7) % 7;
    final base = DateTime(now.year, now.month, now.day).add(Duration(days: diff));

    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    var start = DateTime(base.year, base.month, base.day, hours, mins);

    if (!start.isAfter(now)) {
      start = start.add(const Duration(days: 7));
    }
    return start;
  }

  static DateTime _endOfDayUtc(DateTime localDate) {
    return DateTime(localDate.year, localDate.month, localDate.day, 23, 59, 59).toUtc();
  }

  static String _formatUtcForRRule(DateTime dtUtc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dtUtc.year}${two(dtUtc.month)}${two(dtUtc.day)}T'
        '${two(dtUtc.hour)}${two(dtUtc.minute)}${two(dtUtc.second)}Z';
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
