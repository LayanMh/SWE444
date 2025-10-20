import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/lecture.dart';
import '../providers/schedule_provider.dart';
import '../services/microsoft_auth_service.dart';
import '../services/microsoft_calendar_service.dart';
import '../services/firebase_lecture_service.dart';
import '../services/schedule_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddLectureScreen extends StatefulWidget {
  const AddLectureScreen({super.key});

  @override
  State<AddLectureScreen> createState() => _AddLectureScreenState();
}

class _AddLectureScreenState extends State<AddLectureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addLecture() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final scheduleProvider = Provider.of<ScheduleProvider>(
      context,
      listen: false,
    );

    setState(() => _isLoading = true);

    try {
      List<ScheduleEntry>? remoteSchedule;
      try {
        remoteSchedule = await ScheduleService.fetchScheduleOnce();
      } catch (_) {
        remoteSchedule = null;
      }

      if (!mounted) return;
      if (remoteSchedule != null) {
        scheduleProvider.replaceLectures(
          remoteSchedule.map((entry) => entry.toLecture()),
        );
      }

      final section = _controller.text.trim();

      if (scheduleProvider.containsSection(section)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This section is already in your schedule.'),
          ),
        );
        return;
      }

      final firebaseLectures =
          await FirebaseLectureService.getLecturesBySectionMulti(section);
      if (!mounted) return;

      if (firebaseLectures.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Section not found. Please check the number and try again.',
            ),
          ),
        );
        return;
      }

      // Validate total registered hours before adding
      final currentLectures = scheduleProvider.lectures;
      final totalHours = currentLectures.fold<int>(0, (sum, l) => sum + l.hour);
      final newHour = firebaseLectures.first.hour;

      if (totalHours + newHour > 20) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'You already have $totalHours hours. Adding '
              '${firebaseLectures.first.courseCode} '
              '(${newHour}h) would exceed the 20-hour limit.',
            ),
          ),
        );
        return;
      }

      final firebaseUser = FirebaseAuth.instance.currentUser;
      String? userDocId;

      if (firebaseUser != null) {
        userDocId = firebaseUser.uid;
      } else {
        final prefs = await SharedPreferences.getInstance();
        userDocId = prefs.getString('microsoft_user_doc_id');
      }

      if (userDocId == null || userDocId.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('You must be signed in to save this section.'),
          ),
        );
        return;
      }

      String describeLecture(Lecture lecture) {
        final sectionPart =
            lecture.section.isNotEmpty ? ' section ${lecture.section}' : '';
        return '${lecture.courseCode}$sectionPart';
      }

      final newLectures = firebaseLectures
          .map(
            (lecture) => Lecture(
              id: '${lecture.section}_${lecture.dayOfWeek}',
              courseCode: lecture.courseCode,
              courseName: lecture.courseName,
              section: lecture.section,
              classroom: lecture.classroom,
              dayOfWeek: lecture.dayOfWeek,
              startTime: lecture.startTime,
              endTime: lecture.endTime,
              hour: lecture.hour,
            ),
          )
          .toList(growable: false);

      final Set<String> conflictSummaries = <String>{};
      for (final candidate in newLectures) {
        final conflictingLecture =
            scheduleProvider.findTimeConflict(candidate);
        if (conflictingLecture != null) {
          conflictSummaries.add(
            '${describeLecture(candidate)} overlaps '
            '${describeLecture(conflictingLecture)}',
          );
        }
      }

      if (conflictSummaries.isNotEmpty) {
        final summary = conflictSummaries.join('; ');
        final message = conflictSummaries.length == 1
            ? 'Time conflict: $summary. Remove the conflicting section first.'
            : 'Time conflicts: $summary. Remove the conflicting sections first.';
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
          ),
        );
        return;
      }

      final addedLectures = <Lecture>[];

      for (final newLecture in newLectures) {
        final userScheduleRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userDocId)
            .collection('schedule')
            .doc(newLecture.id);

        try {
          await userScheduleRef.set({
            'courseCode': newLecture.courseCode,
            'courseName': newLecture.courseName,
            'section': newLecture.section,
            'classroom': newLecture.classroom,
            'dayOfWeek': newLecture.dayOfWeek,
            'startTime': newLecture.startTime,
            'endTime': newLecture.endTime,
            'addedAt': FieldValue.serverTimestamp(),
            'status': 'active',
          }, SetOptions(merge: true));
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text('Failed to save section: $error')),
          );
          continue;
        }

        scheduleProvider.addLecture(newLecture);
        addedLectures.add(newLecture);
      }

      if (addedLectures.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No lectures were added to your schedule.'),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            addedLectures.length == 1
                ? 'Lecture added to your schedule.'
                : '${addedLectures.length} lectures added to your schedule.',
          ),
        ),
      );

      final account = await MicrosoftAuthService.ensureSignedIn();
      if (!mounted) return;

      if (account == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Microsoft sign-in cancelled.')),
        );
      } else {
        for (final lecture in addedLectures) {
          try {
            final createdEvent =
                await MicrosoftCalendarService.addWeeklyRecurringLecture(
              account: account,
              lecture: lecture.toRecurringLecture(),
            );

            final userScheduleRef = FirebaseFirestore.instance
                .collection('users')
                .doc(userDocId)
                .collection('schedule')
                .doc(lecture.id);

            await userScheduleRef.set({
              'calendarEventId': createdEvent.id,
              if (createdEvent.seriesMasterId != null &&
                  createdEvent.seriesMasterId!.isNotEmpty)
                'calendarSeriesMasterId': createdEvent.seriesMasterId,
            }, SetOptions(merge: true));
          } catch (error) {
            messenger.showSnackBar(
              SnackBar(content: Text('Microsoft Calendar error: $error')),
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Section')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                decoration: const InputDecoration(
                  labelText: 'Enter Section Number',
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Section number is required';
                  }
                  if (!RegExp(r'^\d{5}$').hasMatch(trimmed)) {
                    return 'Section number must be 5 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _addLecture,
                      child: const Text('Add Lecture'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
