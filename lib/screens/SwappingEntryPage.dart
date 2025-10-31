import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'swapping_main.dart';
import 'MySwapRequestPage.dart';

/// MAIN ENTRY POINT for the Swapping Feature
/// Checks if the user has an existing request and routes accordingly.
class SwappingEntryPage extends StatefulWidget {
  const SwappingEntryPage({super.key});

  @override
  State<SwappingEntryPage> createState() => _SwappingEntryPageState();
}

class _SwappingEntryPageState extends State<SwappingEntryPage> {
  bool _loading = true;
  String? _existingRequestId;

  @override
  void initState() {
    super.initState();
    _checkExistingRequest();
  }

  /// Checks if user already has an active swap request
  Future<void> _checkExistingRequest() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        setState(() => _loading = false);
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection("swap_requests")
          .where("userId", isEqualTo: userId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        _existingRequestId = snapshot.docs.first.id;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showInfoPopup();
        });
      }

      setState(() => _loading = false);
    } catch (e) {
      debugPrint("Error checking existing request: $e");
      setState(() => _loading = false);
    }
  }

  /// Displays an information dialog for users without an existing request
  void _showInfoPopup() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Absherk Swapping is Easy Now!",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0097B2),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Process Overview:",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Color(0xFF0E0259),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "• Fill out your current group and the group you wish to move to.\n"
                "• Optionally, list the extra courses you have, want, or have completed.\n"
                "• Submit your swap request.\n"
                "• Once another student's request matches yours, both will be notified automatically.\n"
                "• Finally, you can view the generated PDF.\n",
                style: TextStyle(
                  fontSize: 15.2,
                  height: 1.55,
                  color: Colors.black87,
                ),
              ),
              const Divider(thickness: 1, height: 28, color: Color(0xFFE0E0E0)),
              const Text(
                "Important Notes:",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color(0xFFFBEAEA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "• You can only have one swap request per semester.\n"
                  "• Once confirmed, your request cannot be deleted or modified.\n",
                  style: TextStyle(
                    fontSize: 14.8,
                    height: 1.5,
                    color: Colors.redAccent,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "Enjoy the journey.",
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0097B2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF0097B2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    "Got it",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Retrieves the user ID from Firebase Auth or SharedPreferences (Microsoft login)
  Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    if (microsoftDocId != null) return microsoftDocId;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0097B2), Color(0xFF0E0259)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    return _existingRequestId != null
        ? MySwapRequestPage(requestId: _existingRequestId!)
        : const SwapRequestPage();
  }
}
