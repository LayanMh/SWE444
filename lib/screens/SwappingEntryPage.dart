import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'swapping_main.dart'; // Your form page
import 'MySwapRequestPage.dart'; // Your details page

/// 🎯 MAIN ENTRY POINT for Swapping Feature
/// This page checks if user has an existing request and routes accordingly
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

  /// Check if user already has an active swap request
  Future<void> _checkExistingRequest() async {
    try {
      final userId = await _getUserId();
      if (userId == null) {
        setState(() => _loading = false);
        return;
      }

      // Query for any existing request by this user
      final snapshot = await FirebaseFirestore.instance
          .collection("swap_requests")
          .where("userId", isEqualTo: userId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        _existingRequestId = snapshot.docs.first.id;
      }

      setState(() => _loading = false);
    } catch (e) {
      debugPrint("❌ Error checking existing request: $e");
      setState(() => _loading = false);
    }
  }

  /// Get user ID from either Firebase Auth or SharedPreferences (Microsoft login)
  Future<String?> _getUserId() async {
    // Check for Microsoft user first
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    if (microsoftDocId != null) return microsoftDocId;

    // Check for Firebase Auth user
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

    // 🎯 ROUTING LOGIC:
    // If user has an existing request → Show request details page
    // If user has NO request → Show form to create new request
    
    if (_existingRequestId != null) {
      return MySwapRequestPage(requestId: _existingRequestId!);
    } else {
      return const SwapRequestPage();
    }
  }
}