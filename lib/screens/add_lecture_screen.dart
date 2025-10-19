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

      final lecture = await FirebaseLectureService.getLectureBySection(section);
      if (!mounted) return;

      if (lecture == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Section not found in Firestore.')),
        );
        return;
      }

      final newLecture = Lecture(
        id: lecture.section,
        courseCode: lecture.courseCode,
        courseName: lecture.courseName,
        section: lecture.section,
        classroom: lecture.classroom,
        dayOfWeek: lecture.dayOfWeek,
        startTime: lecture.startTime,
        endTime: lecture.endTime,
      );

      final conflictingLecture = scheduleProvider.findTimeConflict(newLecture);
      if (conflictingLecture != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Time conflict with ${conflictingLecture.courseCode} section ${conflictingLecture.section}.',
            ),
          ),
        );
        return;
      }

      // Save lecture under current user's schedule in Firestore
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

      final userScheduleRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('schedule')
          .doc(newLecture.id);

      try {
        await userScheduleRef.set({
          'courseCode': lecture.courseCode,
          'courseName': lecture.courseName,
          'section': lecture.section,
          'classroom': lecture.classroom,
          'dayOfWeek': lecture.dayOfWeek,
          'startTime': lecture.startTime,
          'endTime': lecture.endTime,
          'addedAt': FieldValue.serverTimestamp(),
          'status': 'active',
        }, SetOptions(merge: true));
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to save section: $error')),
        );
        return;
      }

      scheduleProvider.addLecture(newLecture);

      messenger.showSnackBar(
        const SnackBar(content: Text('Lecture added to your schedule.')),
      );

      final account = await MicrosoftAuthService.ensureSignedIn();
      if (!mounted) return;

      if (account == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Microsoft sign-in cancelled.')),
        );
      } else {
        try {
          final createdEvent =
              await MicrosoftCalendarService.addWeeklyRecurringLecture(
                account: account,
                lecture: newLecture.toRecurringLecture(),
              );
          try {
            await userScheduleRef.set({
              'calendarEventId': createdEvent.id,
              if (createdEvent.seriesMasterId != null &&
                  createdEvent.seriesMasterId!.isNotEmpty)
                'calendarSeriesMasterId': createdEvent.seriesMasterId,
            }, SetOptions(merge: true));
          } catch (_) {
            // If we fail to persist the event id, continue; deletion flow can fall back.
          }
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Lecture added to Microsoft Calendar.'),
            ),
          );
        } catch (error) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('Microsoft Calendar error: $error')),
          );
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
