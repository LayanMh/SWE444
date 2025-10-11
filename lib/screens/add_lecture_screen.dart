import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/schedule_scraper.dart';
import '../services/providers/ksu_edugate_provider.dart';

class AddLectureScreen extends StatefulWidget {
  const AddLectureScreen({super.key});

  @override
  State<AddLectureScreen> createState() => _AddLectureScreenState();
}

class _AddLectureScreenState extends State<AddLectureScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sectionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _addLecture() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);

    try {
      // Resolve uid
      final firebaseUser = FirebaseAuth.instance.currentUser;
      String? uid = firebaseUser?.uid;
      if (uid == null || uid.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        uid = prefs.getString('microsoft_user_doc_id');
      }
      if (uid == null || uid.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('You must be signed in.')),
        );
        return;
      }

      final inputs = ScrapeInputs(
        uid: uid,
        section: _sectionController.text.trim(),
      );

      final summary = await scrapeAndSave(
        inputs: inputs,
        provider: KsuEdugateProvider(enableLogging: true),
      );

      if (!mounted) return;

      final total = summary['totalSaved'] ?? 0;
      if (total == 0) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No meetings found for this section.')),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Saved $total occurrences to your schedule.')),
      );

      Navigator.pop(context, summary);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Scrape error: $e')),
      );
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
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Section
                TextFormField(
                  controller: _sectionController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Section (e.g., 201)',
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Section is required';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _addLecture,
                        child: const Text('Add Section'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

