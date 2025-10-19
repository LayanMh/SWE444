import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/recurring_lecture.dart';
import 'microsoft_auth_service.dart';

class MicrosoftCalendarEvent {
  const MicrosoftCalendarEvent({
    required this.id,
    required this.subject,
    required this.start,
    required this.end,
    required this.isAllDay,
    this.location,
    this.seriesMasterId,
    this.eventType,
    this.bodyContent,
  });

  final String id;
  final String subject;
  final DateTime? start;
  final DateTime? end;
  final bool isAllDay;
  final String? location;
  final String? seriesMasterId;
  final String? eventType;
  final String? bodyContent;

  factory MicrosoftCalendarEvent.fromJson(Map<String, dynamic> json) {
    final rawLocation =
        (json['location'] as Map<String, dynamic>?)?['displayName'] as String?;
    final trimmedLocation = rawLocation?.trim();
    final masterId = (json['seriesMasterId'] as String?)?.trim();
    final type = (json['type'] as String?)?.trim();
    final content =
        (json['body'] as Map<String, dynamic>?)?['content'] as String?;

    return MicrosoftCalendarEvent(
      id: json['id'] as String? ?? '',
      subject: json['subject'] as String? ?? 'Untitled event',
      start: _parseGraphDateTime(json['start'] as Map<String, dynamic>?),
      end: _parseGraphDateTime(json['end'] as Map<String, dynamic>?),
      isAllDay: json['isAllDay'] as bool? ?? false,
      location: (trimmedLocation == null || trimmedLocation.isEmpty)
          ? null
          : trimmedLocation,
      seriesMasterId: (masterId == null || masterId.isEmpty) ? null : masterId,
      eventType: type,
      bodyContent: content,
    );
  }
}

class MicrosoftCalendarService {
  MicrosoftCalendarService._();

  static const String _host = 'graph.microsoft.com';
  static const Duration _defaultRange = Duration(days: 120);
  static const int _semesterStartMonth = 8;
  static const int _semesterStartDay = 24;

  static DateTime resolveSemesterStart([DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final anchor = DateTime(now.year, _semesterStartMonth, _semesterStartDay);
    if (now.isBefore(anchor)) {
      return DateTime(now.year - 1, _semesterStartMonth, _semesterStartDay);
    }
    return anchor;
  }

  static Future<List<MicrosoftCalendarEvent>> fetchUpcomingEvents(
    MicrosoftAccount account, {
    Duration range = _defaultRange,
    DateTime? start,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final startUtc = (start ?? resolveSemesterStart()).toUtc();
    final Duration effectiveRange = range <= Duration.zero
        ? _defaultRange
        : range;
    final DateTime proposedEnd = startUtc.add(effectiveRange);
    final DateTime minEnd = nowUtc.add(const Duration(days: 30));
    var endUtc = proposedEnd.isAfter(minEnd) ? proposedEnd : minEnd;
    if (!endUtc.isAfter(startUtc)) {
      endUtc = startUtc.add(_defaultRange);
    }

    final uri = Uri.https(_host, '/v1.0/me/calendarView', <String, String>{
      'startDateTime': startUtc.toIso8601String(),
      'endDateTime': endUtc.toIso8601String(),
      r'$orderby': 'start/dateTime',
      r'$top': '50',
      r'$select':
          'id,subject,start,end,isAllDay,location,seriesMasterId,type,body',
    });

    final response = await http.get(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer ${account.accessToken}',
        'Prefer': 'outlook.timezone="UTC"',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final items = decoded is Map<String, dynamic>
          ? decoded['value'] as List<dynamic>? ?? <dynamic>[]
          : <dynamic>[];

      if (items.isEmpty) {
        // No events: just return empty list
        return [];
      }

      final events = items
          .map(
            (dynamic item) =>
                MicrosoftCalendarEvent.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      events.sort((a, b) {
        final aStart = a.start;
        final bStart = b.start;
        if (aStart == null && bStart == null) {
          return 0;
        }
        if (aStart == null) {
          return 1;
        }
        if (bStart == null) {
          return -1;
        }
        return aStart.compareTo(bStart);
      });

      return events;
    } else if (response.statusCode == 404) {
      // ✅ No calendar yet → treat like empty
      return [];
    } else {
      // ❌ Real error (bad token, server issue, etc.)
      throw Exception(
        'Failed to load events (${response.statusCode}): ${response.body}',
      );
    }
  }

  static Future<MicrosoftCalendarEvent> addWeeklyRecurringLecture({
    required MicrosoftAccount account,
    required RecurringLecture lecture,
  }) async {
    final semesterStart = resolveSemesterStart();
    var startLocal = _nextOccurrenceLocal(
      dayOfWeek: lecture.dayOfWeek,
      minutes: lecture.startMinutes,
      from: semesterStart,
    );

    if (startLocal.isAfter(lecture.semesterEnd)) {
      startLocal = _nextOccurrenceLocal(
        dayOfWeek: lecture.dayOfWeek,
        minutes: lecture.startMinutes,
      );
    }

    final durationMinutes = math.max(
      1,
      lecture.endMinutes - lecture.startMinutes,
    );
    final endLocal = startLocal.add(Duration(minutes: durationMinutes));
    final startUtc = startLocal.toUtc();
    final endUtc = endLocal.toUtc();

    final body = <String, dynamic>{
      'subject': '${lecture.courseCode} - ${lecture.courseName}',
      'body': <String, String>{
        'contentType': 'Text',
        'content': 'Section ${lecture.section}',
      },
      if (lecture.classroom.trim().isNotEmpty)
        'location': <String, String>{'displayName': lecture.classroom.trim()},
      'start': <String, String>{
        'dateTime': startUtc.toIso8601String(),
        'timeZone': 'UTC',
      },
      'end': <String, String>{
        'dateTime': endUtc.toIso8601String(),
        'timeZone': 'UTC',
      },
      'recurrence': <String, dynamic>{
        'pattern': <String, dynamic>{
          'type': 'weekly',
          'interval': 1,
          'daysOfWeek': <String>[_mapDayOfWeek(lecture.dayOfWeek)],
        },
        'range': <String, String>{
          'type': 'endDate',
          'startDate': _formatDate(startLocal),
          'endDate': _formatDate(lecture.semesterEnd),
        },
      },
    };

    final response = await http.post(
      Uri.https(_host, '/v1.0/me/events'),
      headers: <String, String>{
        'Authorization': 'Bearer ${account.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'Failed to create calendar event (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response while creating calendar event.');
    }

    return MicrosoftCalendarEvent.fromJson(decoded);
  }

  static Future<void> deleteLecture({
    required MicrosoftAccount account,
    required String eventId,
    String? seriesMasterId,
  }) async {
    final masterId = seriesMasterId?.trim();
    final targetId = (masterId != null && masterId.isNotEmpty)
        ? masterId
        : eventId;
    final uri = Uri.https(_host, '/v1.0/me/events/$targetId');

    final response = await http.delete(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer ${account.accessToken}',
      },
    );

    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete event (${response.statusCode}): ${response.body}',
      );
    }
  }

  static DateTime _nextOccurrenceLocal({
    required int dayOfWeek,
    required int minutes,
    DateTime? from,
  }) {
    final baseDate = from ?? DateTime.now();
    final normalizedBase = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
    );
    final baseWeekday = normalizedBase.weekday % 7;
    final diff = (dayOfWeek - baseWeekday + 7) % 7;
    final targetDate = normalizedBase.add(Duration(days: diff));
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    var start = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      hours,
      mins,
    );

    if (!start.isAfter(baseDate)) {
      start = start.add(const Duration(days: 7));
    }

    return start;
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _mapDayOfWeek(int dayOfWeek) {
    const names = <String>[
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];

    if (dayOfWeek < 0 || dayOfWeek >= names.length) {
      throw ArgumentError.value(dayOfWeek, 'dayOfWeek', 'Must be 0-6');
    }
    return names[dayOfWeek];
  }
}

DateTime? _parseGraphDateTime(Map<String, dynamic>? value) {
  if (value == null) {
    return null;
  }

  final raw = value['dateTime'];
  if (raw is! String || raw.isEmpty) {
    return null;
  }

  final timeZone = value['timeZone'] as String?;
  final normalized = _normalizeGraphDateTime(raw, timeZone);

  try {
    final parsed = DateTime.parse(normalized);
    return parsed.isUtc ? parsed.toLocal() : parsed;
  } catch (_) {
    try {
      final fallback = DateTime.parse(raw);
      return fallback.isUtc ? fallback.toLocal() : fallback;
    } catch (_) {
      return null;
    }
  }
}

String _normalizeGraphDateTime(String raw, String? timeZone) {
  final hasExplicitOffset =
      raw.endsWith('Z') ||
      (raw.length >= 6 &&
          (raw[raw.length - 6] == '+' || raw[raw.length - 6] == '-') &&
          raw[raw.length - 3] == ':');

  if (hasExplicitOffset) {
    return raw;
  }

  if (timeZone != null && timeZone.toUpperCase() == 'UTC') {
    return '${raw}Z';
  }

  return raw;
}
