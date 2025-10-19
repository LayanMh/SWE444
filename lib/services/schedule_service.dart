import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lecture.dart';
import 'attendance_service.dart';
import 'microsoft_auth_service.dart';
import 'microsoft_calendar_service.dart';

class ScheduleEntry {
  ScheduleEntry({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.section,
    required this.classroom,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.calendarEventId,
    this.calendarSeriesMasterId,
  });

  final String id;
  final String courseCode;
  final String courseName;
  final String section;
  final String classroom;
  final int dayOfWeek; // 0..6
  final int startTime; // minutes
  final int endTime; // minutes
  final String? calendarEventId;
  final String? calendarSeriesMasterId;

  factory ScheduleEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Schedule document ${snapshot.id} missing data.');
    }

    String? _trimmed(String key) {
      final value = data[key];
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return null;
    }

    int _toMinutes(String key) {
      final value = data[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    return ScheduleEntry(
      id: snapshot.id,
      courseCode: (data['courseCode'] as String?)?.trim() ?? 'UNKNOWN',
      courseName: (data['courseName'] as String?)?.trim() ?? 'Untitled',
      section: (data['section'] as String?)?.trim() ?? '',
      classroom: (data['classroom'] as String?)?.trim() ?? '',
      dayOfWeek: _toMinutes('dayOfWeek'),
      startTime: _toMinutes('startTime'),
      endTime: _toMinutes('endTime'),
      calendarEventId: _trimmed('calendarEventId'),
      calendarSeriesMasterId: _trimmed('calendarSeriesMasterId'),
    );
  }

  Lecture toLecture() {
    return Lecture(
      id: id,
      courseCode: courseCode,
      courseName: courseName,
      section: section,
      classroom: classroom,
      dayOfWeek: dayOfWeek,
      startTime: startTime,
      endTime: endTime,
    );
  }
}

class ScheduleService {
  ScheduleService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<String> _resolveUserDocId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      return uid;
    }

    final prefs = await SharedPreferences.getInstance();
    final fallbackId = prefs.getString('microsoft_user_doc_id');
    if (fallbackId != null && fallbackId.isNotEmpty) {
      return fallbackId;
    }

    throw StateError('You must be signed in to manage your schedule.');
  }

  static Stream<List<ScheduleEntry>> watchSchedule() {
    return Stream.fromFuture(_resolveUserDocId()).asyncExpand((docId) {
      return _db
          .collection('users')
          .doc(docId)
          .collection('schedule')
          .orderBy('courseCode')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(ScheduleEntry.fromSnapshot)
                .toList(growable: false),
          );
    });
  }

  static Future<void> deleteEntry(ScheduleEntry entry) async {
    final docId = await _resolveUserDocId();
    final docRef = _db
        .collection('users')
        .doc(docId)
        .collection('schedule')
        .doc(entry.id);

    final account = await MicrosoftAuthService.ensureSignedIn();
    if (account == null) {
      throw StateError('Microsoft sign-in required to delete a course.');
    }

    await _deleteEntryWithAccount(
      account: account,
      entry: entry,
      docRef: docRef,
    );
  }

  static Future<ScheduleBulkDeleteResult> deleteAllEntries() async {
    final docId = await _resolveUserDocId();
    final collection = _db
        .collection('users')
        .doc(docId)
        .collection('schedule');
    final snapshot = await collection.get();

    if (snapshot.docs.isEmpty) {
      return const ScheduleBulkDeleteResult(deletedCount: 0, failedCount: 0);
    }

    final account = await MicrosoftAuthService.ensureSignedIn();
    if (account == null) {
      throw StateError('Microsoft sign-in required to delete courses.');
    }

    var deleted = 0;
    var failed = 0;
    Object? firstError;

    for (final doc in snapshot.docs) {
      final entry = ScheduleEntry.fromSnapshot(doc);
      try {
        await _deleteEntryWithAccount(
          account: account,
          entry: entry,
          docRef: doc.reference,
        );
        deleted += 1;
      } catch (error) {
        failed += 1;
        firstError ??= error;
      }
    }

    return ScheduleBulkDeleteResult(
      deletedCount: deleted,
      failedCount: failed,
      error: firstError,
    );
  }

  static Future<void> _deleteEntryWithAccount({
    required MicrosoftAccount account,
    required ScheduleEntry entry,
    required DocumentReference<Map<String, dynamic>> docRef,
  }) async {
    final _CalendarDeleteTarget? target = await _resolveDeleteTarget(
      account,
      entry,
      docRef,
    );

    if (target == null) {
      throw StateError(
        'Unable to locate the calendar event for section ${entry.section}.',
      );
    }

    await MicrosoftCalendarService.deleteLecture(
      account: account,
      eventId: target.eventId,
      seriesMasterId: target.seriesMasterId,
    );

    await AttendanceService.clearCourse(entry.courseCode);

    await docRef.delete();
  }

  static Future<_CalendarDeleteTarget?> _resolveDeleteTarget(
    MicrosoftAccount account,
    ScheduleEntry entry,
    DocumentReference<Map<String, dynamic>> docRef,
  ) async {
    final String? eventId = entry.calendarEventId;
    final String? seriesMasterId = entry.calendarSeriesMasterId;

    if (eventId != null && eventId.isNotEmpty) {
      return _CalendarDeleteTarget(
        eventId: eventId,
        seriesMasterId: (seriesMasterId != null && seriesMasterId.isNotEmpty)
            ? seriesMasterId
            : null,
      );
    }

    try {
      final events = await MicrosoftCalendarService.fetchUpcomingEvents(
        account,
      );
      for (final event in events) {
        if (_matchesEvent(event, entry)) {
          final resolvedSeriesId = _resolveSeriesId(event);
          final target = _CalendarDeleteTarget(
            eventId: resolvedSeriesId ?? event.id,
            seriesMasterId: resolvedSeriesId,
          );
          try {
            await docRef.set({
              'calendarEventId': target.eventId,
              if (target.seriesMasterId != null)
                'calendarSeriesMasterId': target.seriesMasterId,
            }, SetOptions(merge: true));
          } catch (_) {
            // Ignore persistence errors; deletion can proceed.
          }
          return target;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static bool _matchesEvent(MicrosoftCalendarEvent event, ScheduleEntry entry) {
    final subject = event.subject.toUpperCase();
    final normalizedCourseCode = entry.courseCode.toUpperCase();
    if (!subject.contains(normalizedCourseCode)) {
      return false;
    }

    final body = event.bodyContent?.toLowerCase() ?? '';
    if (entry.section.isNotEmpty) {
      final sectionNeedle = 'section ${entry.section}'.toLowerCase();
      if (!body.contains(sectionNeedle)) {
        return false;
      }
    }

    final start = event.start;
    if (start != null) {
      final eventDay = start.weekday % 7;
      if (entry.dayOfWeek != eventDay) {
        return false;
      }
      final eventMinutes = start.hour * 60 + start.minute;
      if ((eventMinutes - entry.startTime).abs() > 5) {
        return false;
      }
    }

    return true;
  }

  static String? _resolveSeriesId(MicrosoftCalendarEvent event) {
    final candidate = event.seriesMasterId?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
    final type = event.eventType?.toLowerCase();
    if (type == 'seriesmaster') {
      return event.id;
    }
    return null;
  }
}

class _CalendarDeleteTarget {
  const _CalendarDeleteTarget({required this.eventId, this.seriesMasterId});

  final String eventId;
  final String? seriesMasterId;
}

class ScheduleBulkDeleteResult {
  const ScheduleBulkDeleteResult({
    required this.deletedCount,
    required this.failedCount,
    this.error,
  });

  final int deletedCount;
  final int failedCount;
  final Object? error;

  bool get hasFailures => failedCount > 0;
}
