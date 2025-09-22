import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/lecture.dart';
import '../providers/schedule_provider.dart';
import '../services/google_auth_service.dart';
import '../services/google_calendar_service.dart'as calendar;
import '../services/firebase_lecture_service.dart';



class AddLectureScreen extends StatefulWidget {
  const AddLectureScreen({super.key});

  @override
  State<AddLectureScreen> createState() => _AddLectureScreenState();
}

class _AddLectureScreenState extends State<AddLectureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  final _uuid = const Uuid();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addLecture() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);

    try {
      final section = _controller.text.trim();

      // Fetch from Firestore
      final lecture = await FirebaseLectureService.getLectureBySection(section);

      if (lecture == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Section not found in Firestore.')),
        );
        return;
      }

      final newLecture = Lecture(
        id: _uuid.v4(), // local unique ID
        courseCode: lecture.courseCode,
        courseName: lecture.courseName,
        section: lecture.section,
        classroom: lecture.classroom,
        dayOfWeek: lecture.dayOfWeek,
        startTime: lecture.startTime,
        endTime: lecture.endTime,
      );

      // Add to provider state
      Provider.of<ScheduleProvider>(context, listen: false)
          .addLecture(newLecture);

      // 👉 Add to Google Calendar
      final account = await GoogleAuthService.ensureSignedIn();
      if (!mounted) return;

      if (account == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Google sign-in cancelled.')),
        );
      } else {
        try {
          await GoogleCalendarService.addWeeklyRecurringLecture(
            account: account,
            lecture: newLecture.toRecurringLecture(),
          );
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Lecture added to Google Calendar.')),
          );
        } catch (error) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('Google Calendar error: $error')),
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
                decoration: const InputDecoration(
                  labelText: 'Enter Section Number',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
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
