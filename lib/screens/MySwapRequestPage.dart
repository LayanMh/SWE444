import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';
import 'swapping_main.dart';
import 'swap_matches_page.dart' as matches;
import 'generate_pdf_page.dart' as pdf;
import 'dart:async';

class MySwapRequestPage extends StatefulWidget {
  final String requestId;

  const MySwapRequestPage({super.key, required this.requestId});

  @override
  State<MySwapRequestPage> createState() => _MySwapRequestPageState();
}

class _MySwapRequestPageState extends State<MySwapRequestPage> {
  static const Color kTeal = Color(0xFF0097B2);
  static const Color kIndigo = Color(0xFF0E0259);

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _popupShown = false;
  StreamSubscription<DocumentSnapshot>? _subscription;
  Timer? _expiryCheckTimer; // ✅ NEW: For auto-expiry check
  int _selectedIndex = 2; // ✅ NEW: For bottom navigation

  @override
  void initState() {
    super.initState();
    _subscribeToRequest();
    _startExpiryCheck(); // ✅ NEW
  }

  void _subscribeToRequest() {
    _subscription = FirebaseFirestore.instance
        .collection("swap_requests")
        .doc(widget.requestId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) {
        // ✅ NEW: Navigate to home if request is deleted
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
        return;
      }
      setState(() => _data = doc.data());
      _checkIncomingConfirmation();
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  // ✅ NEW: Periodically check if pending_confirmation has expired
  void _startExpiryCheck() {
    _expiryCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (_data == null) return;
      
      final status = _data?["status"];
      final expiresAt = _data?["confirmationExpiresAt"] as Timestamp?;
      
      if (status == "pending_confirmation" && expiresAt != null) {
        final now = DateTime.now();
        if (now.isAfter(expiresAt.toDate())) {
          await _handleExpiry();
        }
      }
    });
  }

  // ✅ NEW: Handle expiry of confirmation
  Future<void> _handleExpiry() async {
    try {
      final partnerId = _data?["partnerRequestId"];
      final batch = FirebaseFirestore.instance.batch();
      
      final myRef = FirebaseFirestore.instance.collection("swap_requests").doc(widget.requestId);
      batch.update(myRef, {
        "status": "open",
        "partnerRequestId": FieldValue.delete(),
        "confirmationBy": FieldValue.delete(),
        "confirmationExpiresAt": FieldValue.delete(),
      });
      
      if (partnerId != null) {
        final partnerRef = FirebaseFirestore.instance.collection("swap_requests").doc(partnerId);
        batch.update(partnerRef, {
          "status": "open",
          "partnerRequestId": FieldValue.delete(),
          "confirmationBy": FieldValue.delete(),
          "confirmationExpiresAt": FieldValue.delete(),
        });
      }
      
      await batch.commit();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("⏰ Confirmation expired - request is now open again"),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      debugPrint("❌ Error handling expiry: $e");
    }
  }

  void _checkIncomingConfirmation() async {
    if (_popupShown || _data == null) return;

    final status = _data?["status"];
    final confirmationBy = _data?["confirmationBy"];
    final partnerId = _data?["partnerRequestId"];
    final myUserId = _data?["userId"]; // ✅ NEW

    // ✅ IMPROVED: Only show dialog if someone ELSE requested confirmation from me
    if (status == "pending_confirmation" &&
        confirmationBy != null &&
        confirmationBy != myUserId && // ✅ NEW: Check it's not my own request
        partnerId != null) {
      _popupShown = true;

      final partnerDoc = await FirebaseFirestore.instance
          .collection("swap_requests")
          .doc(partnerId)
          .get();

      final partnerData = partnerDoc.data() ?? {};
      final partnerName = partnerData["studentName"] ?? "Another student";
      final from = partnerData["fromGroup"]?.toString() ?? "-";
      final to = partnerData["toGroup"]?.toString() ?? "-";

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.notification_important, color: Colors.teal),
              SizedBox(width: 10),
              Text("Swap Confirmation Request"),
            ],
          ),
          content: Text(
            "$partnerName wants to swap with you!\n\nFrom Group $from → To Group $to\n\nDo you want to confirm this swap?",
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _declineSwap(partnerId);
                _popupShown = false; // ✅ NEW: Reset flag
              },
              child: const Text("Decline", style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _confirmSwap(partnerId);
              },
              child: const Text("Confirm"),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _confirmSwap(String partnerId) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final myRef = FirebaseFirestore.instance.collection("swap_requests").doc(widget.requestId);
      final partnerRef = FirebaseFirestore.instance.collection("swap_requests").doc(partnerId);

      batch.update(myRef, {
        "status": "confirmed",
        "confirmedBy": _data?["userId"],
        "confirmationExpiresAt": FieldValue.delete(),
        "confirmedAt": FieldValue.serverTimestamp(), // ✅ NEW
      });
      batch.update(partnerRef, {
        "status": "confirmed",
        "confirmedBy": _data?["userId"],
        "confirmationExpiresAt": FieldValue.delete(),
        "confirmedAt": FieldValue.serverTimestamp(), // ✅ NEW
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("✅ Swap confirmed successfully!"),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      debugPrint("❌ Error confirming swap: $e");
    }
  }

  Future<void> _declineSwap(String partnerId) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final myRef = FirebaseFirestore.instance.collection("swap_requests").doc(widget.requestId);
      final partnerRef = FirebaseFirestore.instance.collection("swap_requests").doc(partnerId);

      batch.update(myRef, {
        "status": "open",
        "partnerRequestId": FieldValue.delete(),
        "confirmationBy": FieldValue.delete(),
        "confirmationExpiresAt": FieldValue.delete(),
      });
      batch.update(partnerRef, {
        "status": "open",
        "partnerRequestId": FieldValue.delete(),
        "confirmationBy": FieldValue.delete(),
        "confirmationExpiresAt": FieldValue.delete(),
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Swap request declined"),
        backgroundColor: Colors.orange,
      ));
    } catch (e) {
      debugPrint("❌ Error declining swap: $e");
    }
  }

  // ✅ NEW: Handle bottom navigation
  void _onNavTap(int index) {
    if (index == 2) return; // Already on home/swapping
    setState(() => _selectedIndex = index);
    
    switch (index) {
      case 0:
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/calendar');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/experience');
        break;
      case 4:
        Navigator.pushReplacementNamed(context, '/community');
        break;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _expiryCheckTimer?.cancel(); // ✅ NEW
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kTeal, kIndigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false, // ✅ NEW: Don't apply safe area to bottom for nav bar
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _data == null
                  ? const Center(child: Text("No request found.", style: TextStyle(color: Colors.white)))
                  : _buildContent(),
        ),
      ),
      // ✅ NEW: Bottom Navigation Bar
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded), label: 'Schedule'),
          BottomNavigationBarItem(icon: ImageIcon(AssetImage('assets/images/logo.png')), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.school_rounded), label: 'Experience'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Community'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final fromGroup = _data!["fromGroup"]?.toString() ?? "-";
    final toGroup = _data!["toGroup"]?.toString() ?? "-";
    final major = _data!["major"] ?? "-";
    final level = _data!["level"]?.toString() ?? "-";
    final gender = _data!["gender"] ?? "-";
    final userId = _data!["userId"] ?? "";
    final status = _data!["status"] ?? "open";
    final expiresAt = _data?["confirmationExpiresAt"] as Timestamp?; // ✅ NEW
    final confirmationBy = _data?["confirmationBy"]; // ✅ NEW
    final myUserId = _data!["userId"]; // ✅ NEW

    Color statusColor;
    String statusText;
    Widget? statusSubtitle; // ✅ NEW
    
    switch (status) {
      case "pending_confirmation":
        statusColor = const Color(0xFFFF9800); // ✅ Material Orange - Clear & Visible
        // ✅ NEW: Show different text based on who's waiting
        if (confirmationBy == myUserId) {
          statusText = "Waiting for Response";
          if (expiresAt != null) {
            statusSubtitle = _buildCountdown(expiresAt);
          }
        } else {
          statusText = "Confirmation Requested";
          statusSubtitle = const Text(
            "Someone wants to swap with you!",
            style: TextStyle(color: Color(0xFFFF9800), fontSize: 12),
          );
        }
        break;
      case "confirmed":
        statusColor = const Color(0xFF4CAF50); // ✅ Material Green - Clear & Visible
        statusText = "Confirmed";
        statusSubtitle = const Text(
          "Your swap is confirmed!",
          style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12),
        );
        break;
      default:
        statusColor = const Color(0xFF2196F3); // ✅ Material Blue - Clear & Visible (instead of grey)
        statusText = "Open";
        statusSubtitle = const Text(
          "Looking for matches...",
          style: TextStyle(color: Color(0xFF2196F3), fontSize: 12),
        );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 100), // ✅ CHANGED: Extra bottom padding for nav bar
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          const Center(
            child: Text(
              "My Swap Request",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 25),
          _statusCard(statusText, statusColor, statusSubtitle), // ✅ CHANGED: Added subtitle
          const SizedBox(height: 30),
          _detailsCard(fromGroup, toGroup, major, level, gender),
          const SizedBox(height: 25),
          _actionButtons(userId, status, confirmationBy == myUserId), // ✅ CHANGED: Added isWaiting parameter
        ],
      ),
    );
  }

  // ✅ NEW: Live countdown timer
  Widget _buildCountdown(Timestamp expiresAt) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final remaining = expiresAt.toDate().difference(DateTime.now());
        if (remaining.isNegative) {
          return const Text("Expired", style: TextStyle(color: Colors.red, fontSize: 12));
        }
        
        final hours = remaining.inHours;
        final minutes = remaining.inMinutes % 60;
        final seconds = remaining.inSeconds % 60;
        
        return Text(
          "⏰ Time left: ${hours}h ${minutes}m ${seconds}s",
          style: const TextStyle(color: Color(0xFFFF9800), fontSize: 12, fontWeight: FontWeight.w600), // ✅ Updated color
        );
      },
    );
  }

  // ✅ CHANGED: Added subtitle parameter
  Widget _statusCard(String text, Color color, Widget? subtitle) => Center(
        child: Container(
          padding: const EdgeInsets.all(16), // ✅ CHANGED: padding for subtitle
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                "CURRENT STATUS: $text",
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1.1,
                ),
              ),
              // ✅ NEW: Show subtitle if provided
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                subtitle,
              ],
            ],
          ),
        ),
      );

  Widget _detailsCard(
      String from, String to, String major, String level, String gender) {
    // ✅ NEW: Extract courses to display
    final specialRequests = _data!["specialRequests"] ?? {};
    final haveCourses = (specialRequests["have"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    final wantCourses = (specialRequests["want"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    final deletedCourses = (_data!["deletedCourses"] as List?)?.cast<String>() ?? [];
    
    return Card(
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Request Details", kIndigo),
            _detailRow(Icons.group, "From Group", "Group $from"),
            _detailRow(Icons.swap_horiz, "To Group", "Group $to"),
            _detailRow(Icons.computer, "Major", major),
            _detailRow(Icons.school, "Level", "Level $level"),
            _detailRow(Icons.person, "Gender", gender),
            
            // ✅ NEW: Show Additional Courses
            if (haveCourses.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle("Additional Courses I Have", const Color(0xFF0097B2)),
              ...haveCourses.map((course) => Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF0097B2), size: 16),
                    const SizedBox(width: 8),
                    Text("${course["course"]} - Section ${course["section"]}", 
                      style: const TextStyle(fontSize: 14)),
                  ],
                ),
              )),
            ],
            
            // ✅ NEW: Show Courses I Want
            if (wantCourses.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle("Additional Courses I Want", const Color(0xFF0E0259)),
              ...wantCourses.map((course) {
                final priority = course["priority"] ?? "Optional";
                final isRequired = priority == "Must";
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 8),
                  child: Row(
                    children: [
                      Icon(
                        isRequired ? Icons.star : Icons.star_border, 
                        color: isRequired ? Colors.amber : const Color(0xFF0E0259), 
                        size: 16
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${course["course"]} - Section ${course["section"]} ($priority)", 
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isRequired ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            
            // ✅ NEW: Show Completed Courses
            if (deletedCourses.isNotEmpty) ...[
              const SizedBox(height: 20),
              _sectionTitle("Completed Main Courses", Colors.green),
              ...deletedCourses.map((course) => Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(course, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  // ✅ CHANGED: Added isWaiting parameter
  Widget _actionButtons(String userId, String status, bool isWaiting) {
    final isPending = status == "pending_confirmation";
    final isConfirmed = status == "confirmed";

    return Column(
      children: [
        if (isConfirmed)
          _primaryBtn(
            color: Colors.green,
            icon: Icons.picture_as_pdf,
            label: "Generate PDF",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => pdf.GeneratePdfPage(myRequestId: widget.requestId),
                ),
              );
            },
          ),
        if (!isConfirmed && !isPending) // ✅ CHANGED: Hide edit when pending
          _primaryBtn(
            color: kIndigo,
            icon: Icons.edit,
            label: "Edit Request",
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => SwapRequestPage(
                    existingRequestId: widget.requestId,
                    initialData: _data!,
                  ),
                ),
              );
            },
          ),
        // ✅ NEW: Show waiting message when user is waiting for confirmation
        if (isPending && isWaiting)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0), // ✅ Light orange background
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF9800)), // ✅ Orange border
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_bottom, color: Color(0xFFFF9800)), // ✅ Orange icon
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Waiting for the other student to confirm your request...",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (!isConfirmed)
          _primaryBtn(
            color: Colors.redAccent,
            icon: Icons.delete_outline,
            label: "Delete Request",
            onPressed: _deleteRequest,
          ),
        const SizedBox(height: 16),
        if (status == "open")
          _outlineBtn(
            icon: Icons.group_outlined,
            label: "Find Matches",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => matches.SwapMatchesPage(
                    userId: userId,
                    userRequestId: widget.requestId,
                    userRequestData: _data!,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _sectionTitle(String title, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
              decorationThickness: 1.5,
            ),
          ),
          const SizedBox(height: 10),
        ],
      );

  Widget _detailRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: kIndigo, size: 22),
            const SizedBox(width: 10),
            Text("$label: ",
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
          ],
        ),
      );

  Widget _primaryBtn({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: ElevatedButton.icon(
          icon: Icon(icon, size: 22),
          label: Text(label,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            elevation: 3,
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onPressed,
        ),
      );

  Widget _outlineBtn({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: OutlinedButton.icon(
          icon: Icon(icon, color: kTeal, size: 22),
          label: Text(label,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: kTeal)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kTeal, width: 1.8),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onPressed,
        ),
      );

  Future<void> _deleteRequest() async {
    // ✅ NEW: Added confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Request?"),
        content: const Text("Are you sure you want to delete your swap request? This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    
    try {
      final docRef = FirebaseFirestore.instance
          .collection("swap_requests")
          .doc(widget.requestId);
      final snapshot = await docRef.get();
      final data = snapshot.data();
      final partnerId = data?["partnerRequestId"];

      if (partnerId != null) {
        await FirebaseFirestore.instance
            .collection("swap_requests")
            .doc(partnerId)
            .update({
          "status": "open",
          "confirmationBy": FieldValue.delete(),
          "confirmedBy": FieldValue.delete(),
          "partnerRequestId": FieldValue.delete(),
          "confirmationExpiresAt": FieldValue.delete(),
        });
      }

      await docRef.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Request deleted successfully."),
        backgroundColor: Colors.redAccent,
      ));

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      debugPrint("❌ Error deleting: $e");
    }
  }
}