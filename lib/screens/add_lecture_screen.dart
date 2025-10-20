import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lecture.dart';
import '../providers/schedule_provider.dart';
import '../services/microsoft_auth_service.dart';
import '../services/microsoft_calendar_service.dart';
import '../services/firebase_lecture_service.dart';

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
      final section = _controller.text.trim();

      if (scheduleProvider.containsSection(section)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This section is already in your schedule.'),
          ),
        );
        return;
      }

      // 🔹 Fetch all lectures for this section
      final lectures = await FirebaseLectureService.getLectureBySection(section);

      if (lectures.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Section not found in Firestore.')),
        );
        return;
      }

      // 🔹 Get current user
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
          .collection('schedule');

      // 🔹 Calculate total hours before adding
      final currentSchedule = await userScheduleRef.get();
      int currentHours = 0;
      for (final doc in currentSchedule.docs) {
        currentHours += (doc.data()['hours'] ?? 0) as int;
      }

      final int newSectionHours = lectures.first.hours;
      if (currentHours + newSectionHours > 20) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Adding this section exceeds 20 total hours.'),
          ),
        );
        return;
      }

      // 🔹 Add each lecture session
      for (final newLecture in lectures) {
        final conflict = scheduleProvider.findTimeConflict(newLecture);
        if (conflict != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Time conflict with ${conflict.courseCode} section ${conflict.section}.',
              ),
            ),
          );
          return;
        }

        final lectureDocId = '${newLecture.id}_${newLecture.dayOfWeek}';
        await userScheduleRef.doc(lectureDocId).set({
          'courseCode': newLecture.courseCode,
          'courseName': newLecture.courseName,
          'section': newLecture.section,
          'classroom': newLecture.classroom,
          'dayOfWeek': newLecture.dayOfWeek,
          'startTime': newLecture.startTime,
          'endTime': newLecture.endTime,
          'hours': newLecture.hours,
          'addedAt': FieldValue.serverTimestamp(),
          'status': 'active',
        }, SetOptions(merge: true));

        scheduleProvider.addLecture(newLecture);
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Lecture added to your schedule.')),
      );

      // 🔹 Microsoft Calendar integration
      final account = await MicrosoftAuthService.ensureSignedIn();
      if (!mounted) return;

      if (account != null) {
        for (final newLecture in lectures) {
          try {
            final createdEvent =
                await MicrosoftCalendarService.addWeeklyRecurringLecture(
              account: account,
              lecture: newLecture.toRecurringLecture(),
            );

            await userScheduleRef
                .doc('${newLecture.id}_${newLecture.dayOfWeek}')
                .set({
              'calendarEventId': createdEvent.id,
              if (createdEvent.seriesMasterId != null &&
                  createdEvent.seriesMasterId!.isNotEmpty)
                'calendarSeriesMasterId': createdEvent.seriesMasterId,
            }, SetOptions(merge: true));
          } catch (error) {
            messenger.showSnackBar(
              SnackBar(content: Text('Calendar sync error: $error')),
            );
          }
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Lecture(s) added to Microsoft Calendar.'),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Microsoft sign-in cancelled.')),
        );
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
