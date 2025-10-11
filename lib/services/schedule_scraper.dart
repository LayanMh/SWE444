import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'timetable_provider.dart';

class ScrapeInputs {
  final String uid;
  final String? courseCode; // optional, can be inferred during scrape
  final String section;

  ScrapeInputs({
    required this.uid,
    this.courseCode,
    required this.section,
  });
}

Map<String, dynamic> errorResult(String code, String message) => {
      'code': code,
      'message': message,
      'totalSaved': 0,
      'meetings': <dynamic>[],
    };

String normalizeCourseCode(String raw) => raw.replaceAll(' ', '').toUpperCase();

String _eventId({
  required String courseCode,
  required String section,
  required DateTime start,
}) {
  final date = DateFormat('yyyy-MM-dd').format(start);
  final time = DateFormat('HHmm').format(start);
  return '$courseCode:$section:$date:$time';
}

/// Expand weekly patterns into concrete DateTimes between [start] and [end] inclusive.
Iterable<({DateTime start, DateTime end, int weekday, String classroom})>
    _expandOccurrences({
  required DateTime start,
  required DateTime end,
  required List<MeetingPattern> patterns,
}) sync* {
  // Align to first Monday of/after term start for iteration convenience.
  final startMonday = start.weekday == DateTime.monday
      ? DateTime(start.year, start.month, start.day)
      : DateTime(start.year, start.month, start.day)
          .add(Duration(days: (8 - start.weekday) % 7));

  for (final p in patterns) {
    // Find first date on/after termStart matching weekday
    final delta = (p.weekday - DateTime.monday) % 7;
    DateTime first = startMonday.add(Duration(days: delta));
    if (first.isBefore(start)) {
      first = first.add(const Duration(days: 7));
    }

    for (var d = first; !d.isAfter(end); d = d.add(const Duration(days: 7))) {
      final s = atLocalTime(d, p.startHHmm);
      final e = atLocalTime(d, p.endHHmm);
      yield (start: s, end: e, weekday: p.weekday, classroom: p.classroom);
    }
  }
}

/// Writes an occurrence doc idempotently: on first create sets createdAt; on update preserves it.
Future<void> _upsertOccurrence({
  required String uid,
  required String eventId,
  required Map<String, dynamic> data,
}) async {
  final ref = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('schedule')
      .doc(eventId);

  final snap = await ref.get();
  final nowFields = {
    'updatedAt': FieldValue.serverTimestamp(),
  };

  if (snap.exists) {
    await ref.set({...data, ...nowFields}, SetOptions(merge: true));
  } else {
    await ref.set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      ...nowFields,
    });
  }
}

/// Main entry: scrape timetable and persist expanded occurrences.
/// Returns a summary map as specified in the prompt.
Future<Map<String, dynamic>> scrapeAndSave({
  required ScrapeInputs inputs,
  required TimetableProvider provider,
}) async {
  try {
    final normalizedCode =
        inputs.courseCode != null ? normalizeCourseCode(inputs.courseCode!) : null;
    final result = await provider.fetch(
      courseCode: normalizedCode,
      section: inputs.section,
    );

    if (result == null || result.meetings.isEmpty) {
      return {
        'courseCode': normalizedCode ?? '',
        'courseName': result?.courseName ?? '',
        'section': inputs.section,
        'classroom': '',
        'totalSaved': 0,
        'meetings': <dynamic>[],
      };
    }

    final occurrences = _expandOccurrences(
      start: DateTime(result.termStart.year, result.termStart.month, result.termStart.day),
      end: DateTime(result.termEnd.year, result.termEnd.month, result.termEnd.day),
      patterns: result.meetings,
    );

    int saved = 0;
    final meetingsSummary = <Map<String, dynamic>>[];

    for (final occ in occurrences) {
      final eventId = _eventId(
        courseCode: result.courseCode,
        section: result.section,
        start: occ.start,
      );
      final data = {
        'courseCode': result.courseCode,
        'courseName': result.courseName,
        'section': result.section,
        'classroom': occ.classroom,
        'start': Timestamp.fromDate(occ.start.toUtc()),
        'end': Timestamp.fromDate(occ.end.toUtc()),
        'weekday': occ.weekday,
        'source': 'scraper',
      };

      await _upsertOccurrence(uid: inputs.uid, eventId: eventId, data: data);
      saved += 1;
      meetingsSummary.add({
        'eventId': eventId,
        'startIso': occ.start.toUtc().toIso8601String(),
        'endIso': occ.end.toUtc().toIso8601String(),
        'weekday': occ.weekday,
      });
    }

    // classroom in summary: prefer first meeting's classroom if consistent
    final classroom = result.meetings.isNotEmpty ? result.meetings.first.classroom : '';

    return {
      'courseCode': result.courseCode,
      'courseName': result.courseName,
      'section': result.section,
      'classroom': classroom,
      'totalSaved': saved,
      'meetings': meetingsSummary,
    };
  } catch (e) {
    return errorResult('SCRAPER_ERROR', e.toString());
  }
}
