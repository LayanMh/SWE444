import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';
import 'swapping_main.dart';
import 'swap_matches_page.dart' as matches;
import 'generate_pdf_page.dart' as pdf;
import 'dart:async';
import '../services/noti_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/microsoft_auth_service.dart';
import '../services/microsoft_calendar_service.dart';
import '../models/lecture.dart';
import '../services/firebase_lecture_service.dart';

const String _kTitleNewSwapRequest = 'New Swap Request';
const String _kTitleSwapConfirmed = 'Swap Confirmed';
const String _kTitleSwapDeclined = 'Swap Declined';
const String _kTitleSwapTimeout = 'Swap Request Timed Out';
const String _kBodySwapTimeout =
    'No confirmation was received in time; the swap request is open again.';

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
  Timer? _expiryCheckTimer;
  int _selectedIndex = 2;

  @override
  void initState() {
    super.initState();
    _subscribeToRequest();
    _startExpiryCheck();
  }

  void _subscribeToRequest() {
    ensureSwapNotificationRelay(widget.requestId);

    _subscription = FirebaseFirestore.instance
        .collection("swap_requests")
        .doc(widget.requestId)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) {
        stopSwapNotificationRelay(widget.requestId);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
        return;
      }
      final data = doc.data();
      if (mounted) {
        setState(() => _data = data);
        _checkIncomingConfirmation();
      }
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _loading = false);
    });
  }

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
        final partnerRef =
            FirebaseFirestore.instance.collection("swap_requests").doc(partnerId);
        final partnerSnapshot = await partnerRef.get();
        if (partnerSnapshot.exists) {
          batch.update(partnerRef, {
            "status": "open",
            "partnerRequestId": FieldValue.delete(),
            "confirmationBy": FieldValue.delete(),
            "confirmationExpiresAt": FieldValue.delete(),
          });
        } else {
          debugPrint(
            "⚠️ Partner request $partnerId missing while handling expiry for ${widget.requestId}.",
          );
        }
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
    final myUserId = _data?["userId"];

    if (status == "pending_confirmation" &&
        confirmationBy != null &&
        confirmationBy != myUserId &&
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
              Text("Swap Confirmation"),
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
                _popupShown = false;
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
      final partnerSnapshot = await partnerRef.get();
      if (!partnerSnapshot.exists) {
        _showSnack("Swap partner request no longer exists.", isError: true);
        return;
      }

      batch.update(myRef, {
        "status": "confirmed",
        "confirmedBy": _data?["userId"],
        "confirmationExpiresAt": FieldValue.delete(),
        "confirmedAt": FieldValue.serverTimestamp(),
      });
      batch.update(partnerRef, {
        "status": "confirmed",
        "confirmedBy": _data?["userId"],
        "confirmationExpiresAt": FieldValue.delete(),
        "confirmedAt": FieldValue.serverTimestamp(),
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
      final partnerSnapshot = await partnerRef.get();
      if (!partnerSnapshot.exists) {
        _showSnack("Swap partner request no longer exists.", isError: true);
        return;
      }

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
      debugPrint("Error declining swap: $e");
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
      ),
    );
  }

  void _onNavTap(int index) {
    if (index == 2) return;
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
    _expiryCheckTimer?.cancel();
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
          bottom: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _data == null
                  ? const Center(child: Text("No request found.", style: TextStyle(color: Colors.white)))
                  : _buildContent(),
        ),
      ),
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
    final expiresAt = _data?["confirmationExpiresAt"] as Timestamp?;
    final confirmationBy = _data?["confirmationBy"];
    final myUserId = _data!["userId"];
    final isPending = status == "pending_confirmation";
    final isConfirmed = status == "confirmed";
    final canEdit = !isPending && !isConfirmed;

    Color statusColor;
    String statusText;
    Widget? statusSubtitle;
    
    switch (status) {
      case "pending_confirmation":
        statusColor = const Color(0xFFFF9800);
        if (confirmationBy == myUserId) {
          statusText = "Waiting for confirmation";
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
        statusColor = const Color.fromARGB(255, 16, 80, 32);
        statusText = "Confirmed";
        statusSubtitle = const Text(
          "Your swap is confirmed!",
          style: TextStyle(color: Color.fromARGB(255, 16, 80, 32), fontSize: 12),
        );
        break;
      default:
        statusColor = const Color.fromARGB(255, 14, 2, 89);
        statusText = "Open";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 100),
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
          _statusCard(statusText, statusColor, statusSubtitle),
          const SizedBox(height: 30),
          _detailsCard(fromGroup, toGroup, major, level, gender, canEdit),
          const SizedBox(height: 25),
          _actionButtons(userId, status, confirmationBy == myUserId),
        ],
      ),
    );
  }

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
          "Time left: ${hours}h ${minutes}m ${seconds}s",
          style: const TextStyle(color: Color(0xFFFF9800), fontSize: 12, fontWeight: FontWeight.w600),
        );
      },
    );
  }

  Widget _statusCard(String text, Color color, Widget? subtitle) => Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color, width: 2),
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
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                subtitle,
              ],
            ],
          ),
        ),
      );

  Widget _detailsCard(
      String from, String to, String major, String level, String gender, bool canEdit) {
    final specialRequests = _data!["specialRequests"] ?? {};
    final haveCourses = (specialRequests["have"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    final wantCourses = (specialRequests["want"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    final deletedCourses = (_data!["deletedCourses"] as List?)?.cast<String>() ?? [];
    final isConfirmed = _data!["status"] == "confirmed";
    
    return Card(
      color: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Request Details",
                  style: TextStyle(
                    color: kIndigo,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              
                Row(
                  children: [
                    if (canEdit)
                      Container(
                        decoration: BoxDecoration(
                          color: kIndigo.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.edit, color: kIndigo, size: 22),
                          tooltip: "Edit Request",
                          onPressed: _openEditRequest,
                        ),
                      ),
                    
                    if (isConfirmed) ...[
                      if (canEdit) const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 24),
                          tooltip: "Update Schedule",
                          onPressed: _updateScheduleAutomatically,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 15),
            _detailRow(Icons.group, "From Group", "Group $from"),
            _detailRow(Icons.swap_horiz, "To Group", "Group $to"),
            _detailRow(Icons.computer, "Major", major),
            _detailRow(Icons.school, "Level", "Level $level"),
            _detailRow(Icons.person, "Gender", gender),
            
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
        if (isPending && isWaiting)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF9800)),
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_bottom, color: Color(0xFFFF9800)),
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
        if (status == "open") ...[
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
          const SizedBox(height: 16),
        ],
        if (!isConfirmed)
          _primaryBtn(
            color: Colors.redAccent,
            icon: Icons.delete_outline,
            label: "Delete Request",
            onPressed: _deleteRequest,
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
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onPressed,
        ),
      );

  void _openEditRequest() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SwapRequestPage(
          existingRequestId: widget.requestId,
          initialData: _data!,
        ),
      ),
    );
  }

  Future<void> _deleteRequest() async {
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

      if (!snapshot.exists) {
        _showDeleteResult(success: false, message: "Request not found or already deleted.");
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      batch.delete(docRef);

      if (partnerId != null) {
        final partnerRef =
            FirebaseFirestore.instance.collection("swap_requests").doc(partnerId);
        final partnerSnapshot = await partnerRef.get();
        if (partnerSnapshot.exists) {
          batch.update(partnerRef, {
            "status": "open",
            "confirmationBy": FieldValue.delete(),
            "confirmedBy": FieldValue.delete(),
            "partnerRequestId": FieldValue.delete(),
            "confirmationExpiresAt": FieldValue.delete(),
          });
        } else {
          debugPrint(
              "⚠️ Partner request $partnerId already missing when deleting ${widget.requestId}.");
        }
      }

      await batch.commit();

      if (!mounted) return;
      _showDeleteResult(success: true);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      debugPrint("❌ Error deleting: $e");
      if (!mounted) return;
      _showDeleteResult(success: false, message: "Failed to delete request. Please try again.");
    }
  }

  void _showDeleteResult({required bool success, String? message}) {
    final text = message ??
        (success
            ? "Request deleted successfully."
            : "Failed to delete request. Please try again.");
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: success ? Colors.redAccent : Colors.red,
    ));
  }

  Future<void> _updateScheduleAutomatically() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );

      final partnerId = _data?["partnerRequestId"];
      if (partnerId == null) {
        Navigator.pop(context);
        _showSnack("Partner information not found", isError: true);
        return;
      }

      final partnerDoc = await FirebaseFirestore.instance
          .collection("swap_requests")
          .doc(partnerId)
          .get();

      if (!partnerDoc.exists) {
        Navigator.pop(context);
        _showSnack("Partner swap data not found", isError: true);
        return;
      }

      final partnerData = partnerDoc.data()!;
      
      final toGroup = _data!["toGroup"];
      final major = _data!["major"];
      final gender = _data!["gender"];
      final level = _data!["level"];

      final groupLectures = await _fetchGroupCourses(toGroup, major, gender, level);
      final additionalLectures = await _calculateMatchedCourses(partnerData);

      Navigator.pop(context);

      final confirmed = await _showScheduleUpdateConfirmation(groupLectures, additionalLectures);
      
      if (confirmed == true) {
        await _addCoursesToSchedule(groupLectures, additionalLectures);
      }

    } catch (e) {
      Navigator.pop(context);
      _showSnack("Error updating schedule: $e", isError: true);
    }
  }

  Future<List<Lecture>> _fetchGroupCourses(
    dynamic groupNumber, 
    String major, 
    String gender, 
    dynamic level
  ) async {
    try {
      final groupSnapshot = await FirebaseFirestore.instance
          .collection("Groups")
          .where("Major", isEqualTo: major)
          .where("Gender", isEqualTo: gender)
          .where("Level", isEqualTo: level)
          .where("Number", isEqualTo: groupNumber)
          .limit(1)
          .get();

      if (groupSnapshot.docs.isEmpty) {
        debugPrint("⚠️ No group found for Number=$groupNumber, Major=$major, Gender=$gender, Level=$level");
        return [];
      }

      final groupData = groupSnapshot.docs.first.data();
      final sectionsArray = groupData["sections"] as List?;
      
      if (sectionsArray == null || sectionsArray.isEmpty) {
        debugPrint("⚠️ Group has no sections");
        return [];
      }

      List<Lecture> allLectures = [];
      for (final sectionNumber in sectionsArray) {
        final section = sectionNumber.toString();
        
        final lectures = await FirebaseLectureService.getLecturesBySectionMulti(section);
        
        final convertedLectures = lectures.map((lecture) => Lecture(
          id: '${lecture.section}_${lecture.dayOfWeek}',
          courseCode: lecture.courseCode,
          courseName: lecture.courseName,
          section: lecture.section,
          classroom: lecture.classroom,
          dayOfWeek: lecture.dayOfWeek,
          startTime: lecture.startTime,
          endTime: lecture.endTime,
          hour: lecture.hour,
        )).toList();
        
        allLectures.addAll(convertedLectures);
      }

      debugPrint("✅ Fetched ${allLectures.length} lectures from group $groupNumber");
      return allLectures;
    } catch (e) {
      debugPrint("❌ Error fetching group courses: $e");
      return [];
    }
  }

  Future<List<Lecture>> _calculateMatchedCourses(
    Map<String, dynamic> partnerData
  ) async {
    final mySpecialRequests = _data!["specialRequests"] ?? {};
    final myWantCourses = (mySpecialRequests["want"] as List?)
        ?.map((item) => Map<String, dynamic>.from(item as Map))
        .toList() ?? [];

    final partnerSpecialRequests = partnerData["specialRequests"] ?? {};
    final partnerHaveCourses = (partnerSpecialRequests["have"] as List?)
        ?.map((item) => Map<String, dynamic>.from(item as Map))
        .toList() ?? [];

    final partnerCompletedCourses = (partnerData["deletedCourses"] as List?)
        ?.cast<String>() ?? [];

    final myCompletedCourses = (_data!["deletedCourses"] as List?)
        ?.cast<String>() ?? [];

    List<Lecture> matchedLectures = [];

    for (final wantCourse in myWantCourses) {
      final wantCourseCode = wantCourse["course"];

      final partnerHas = partnerHaveCourses.any((haveCourse) => 
        haveCourse["course"] == wantCourseCode
      );

      final isCompleted = partnerCompletedCourses.contains(wantCourseCode) || 
                          myCompletedCourses.contains(wantCourseCode);

      if (partnerHas && !isCompleted) {
        final matchingHave = partnerHaveCourses.firstWhere(
          (haveCourse) => haveCourse["course"] == wantCourseCode
        );

        final section = matchingHave["section"].toString();
        
        try {
          final lectures = await FirebaseLectureService.getLecturesBySectionMulti(section);
          
          final convertedLectures = lectures.map((lecture) => Lecture(
            id: '${lecture.section}_${lecture.dayOfWeek}',
            courseCode: lecture.courseCode,
            courseName: lecture.courseName,
            section: lecture.section,
            classroom: lecture.classroom,
            dayOfWeek: lecture.dayOfWeek,
            startTime: lecture.startTime,
            endTime: lecture.endTime,
            hour: lecture.hour,
          )).toList();
          
          matchedLectures.addAll(convertedLectures);
          debugPrint("✅ Matched course: $wantCourseCode - Section $section (${convertedLectures.length} lectures)");
        } catch (e) {
          debugPrint("❌ Error fetching matched course $section: $e");
        }
      }
    }

    debugPrint("✅ Total matched lectures: ${matchedLectures.length}");
    return matchedLectures;
  }

  Future<bool?> _showScheduleUpdateConfirmation(
    List<Lecture> groupLectures,
    List<Lecture> additionalLectures,
  ) async {
    final totalCourses = groupLectures.length + additionalLectures.length;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text("Update Schedule?")),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Ready to replace your schedule with $totalCourses class(es):",
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 12),

              if (groupLectures.isNotEmpty) ...[
                const Text(
                  "From Your New Group:",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.blue),
                ),
                const SizedBox(height: 8),
                ...groupLectures.take(5).map((lecture) => _buildLecturePreview(lecture, Colors.blue)),
                if (groupLectures.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "... and ${groupLectures.length - 5} more classes",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                  ),
                const SizedBox(height: 12),
              ],

              if (additionalLectures.isNotEmpty) ...[
                const Text(
                  "Additional Matched Classes:",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.green),
                ),
                const SizedBox(height: 8),
                ...additionalLectures.map((lecture) => _buildLecturePreview(lecture, Colors.green)),
              ],

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Your old schedule will be DELETED and replaced",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text("Replace Schedule"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLecturePreview(Lecture lecture, Color color) {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final dayName = lecture.dayOfWeek >= 0 && lecture.dayOfWeek < days.length 
        ? days[lecture.dayOfWeek] 
        : 'Day ${lecture.dayOfWeek}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.school, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${lecture.courseCode} - Section ${lecture.section}",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  "$dayName • ${lecture.courseName}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ SIMPLIFIED: Clean version with one loading spinner and one success message
  Future<void> _addCoursesToSchedule(
  List<Lecture> groupLectures,
  List<Lecture> additionalLectures,
) async {
  try {
    final messenger = ScaffoldMessenger.of(context);
    
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
        const SnackBar(content: Text('You must be signed in to save sections.')),
      );
      return;
    }

    final allLectures = [...groupLectures, ...additionalLectures];

    // Simple loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    // ===== DELETION PHASE =====
    debugPrint("🗑️ STARTING DELETION PHASE");
    
    // Get existing schedule
    debugPrint("📋 Fetching existing schedule from Firestore...");
    final existingSchedule = await FirebaseFirestore.instance
        .collection('users')
        .doc(userDocId)
        .collection('schedule')
        .get();

    debugPrint("📋 Found ${existingSchedule.docs.length} existing courses");

    // Delete calendar events FIRST
    if (existingSchedule.docs.isNotEmpty) {
      debugPrint("🗑️ Deleting ${existingSchedule.docs.length} calendar events...");
      
      try {
        final account = await MicrosoftAuthService.ensureSignedIn();
        
        if (account != null) {
          int deletedCount = 0;
          for (final doc in existingSchedule.docs) {
            final data = doc.data();
            final eventId = data['calendarEventId'] as String?;
            final seriesMasterId = data['calendarSeriesMasterId'] as String?;
            
            if (eventId != null && eventId.isNotEmpty) {
              try {
                await MicrosoftCalendarService.deleteLecture(
                  account: account,
                  eventId: eventId,
                  seriesMasterId: seriesMasterId,
                );
                deletedCount++;
                debugPrint("✅ Deleted calendar event $deletedCount/${existingSchedule.docs.length}");
                
                // Add small delay to avoid rate limiting
                await Future.delayed(const Duration(milliseconds: 100));
              } catch (e) {
                debugPrint("⚠️ Failed to delete calendar event $eventId: $e");
              }
            }
          }
          debugPrint("✅ Successfully deleted $deletedCount calendar events");
        } else {
          debugPrint("⚠️ No Microsoft account available for calendar deletion");
        }
      } catch (e) {
        debugPrint("❌ Error during calendar deletion: $e");
      }

      // Delete Firestore entries
      debugPrint("🗑️ Deleting ${existingSchedule.docs.length} Firestore entries...");
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in existingSchedule.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        debugPrint("✅ Successfully deleted ${existingSchedule.docs.length} Firestore entries");
      } catch (e) {
        debugPrint("❌ Error deleting Firestore entries: $e");
      }
    } else {
      debugPrint("ℹ️ No existing schedule to delete");
    }

    debugPrint("✅ DELETION PHASE COMPLETE");

    // ===== ADDITION PHASE =====
    debugPrint("➕ STARTING ADDITION PHASE");
    debugPrint("📝 Adding ${allLectures.length} new courses to Firestore...");

    final addedLectures = <Lecture>[];

    for (final newLecture in allLectures) {
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

        addedLectures.add(newLecture);
        debugPrint("✅ Added ${addedLectures.length}/${allLectures.length}: ${newLecture.courseCode}");
      } catch (error) {
        debugPrint("❌ Failed to save ${newLecture.courseCode}: $error");
        continue;
      }
    }

    debugPrint("✅ Successfully added ${addedLectures.length} courses to Firestore");

    // ===== CALENDAR SYNC PHASE =====
    debugPrint("📅 STARTING CALENDAR SYNC PHASE");
    
    try {
      final account = await MicrosoftAuthService.ensureSignedIn();
      
      if (account != null && mounted) {
        int syncedCount = 0;
        for (final lecture in addedLectures) {
          try {
            debugPrint("📅 Syncing ${syncedCount + 1}/${addedLectures.length}: ${lecture.courseCode}...");
            
            final createdEvent = await MicrosoftCalendarService.addWeeklyRecurringLecture(
              account: account,
              lecture: lecture.toRecurringLecture(),
            );

            await FirebaseFirestore.instance
                .collection('users')
                .doc(userDocId)
                .collection('schedule')
                .doc(lecture.id)
                .set({
              'calendarEventId': createdEvent.id,
              if (createdEvent.seriesMasterId != null &&
                  createdEvent.seriesMasterId!.isNotEmpty)
                'calendarSeriesMasterId': createdEvent.seriesMasterId,
            }, SetOptions(merge: true));

            syncedCount++;
            debugPrint("✅ Synced ${lecture.courseCode} to calendar");
            
            // Add delay to avoid rate limiting (429 error)
            await Future.delayed(const Duration(milliseconds: 500));
            
          } catch (error) {
            debugPrint("⚠️ Calendar sync error for ${lecture.courseCode}: $error");
            // Continue with other lectures even if one fails
          }
        }
        debugPrint("✅ Successfully synced $syncedCount/${addedLectures.length} events to calendar");
      } else {
        debugPrint("⚠️ Skipping calendar sync - no Microsoft account");
      }
    } catch (e) {
      debugPrint("❌ Error during calendar sync: $e");
    }

    debugPrint("✅ SCHEDULE REPLACEMENT COMPLETE");
    debugPrint("📊 Summary: Deleted ${existingSchedule.docs.length}, Added ${addedLectures.length}");

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    // Simple success message
    messenger.showSnackBar(
      const SnackBar(
        content: Text('✅ Schedule updated successfully!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    // Navigate to calendar
    Navigator.pushReplacementNamed(context, '/calendar');
    
  } catch (e) {
    debugPrint("❌ FATAL ERROR in _addCoursesToSchedule: $e");
    if (mounted) {
      Navigator.pop(context);
      _showSnack("Error: $e", isError: true);
    }
  }
}
}

// Existing notification relay code (unchanged)
Future<void> _processSwapStatusChange({
  required Map<String, dynamic>? previousData,
  required Map<String, dynamic>? currentData,
  required String myUserId,
}) async {
  if (currentData == null) return;

  final currentStatus = currentData["status"]?.toString();
  final previousStatus = previousData?["status"]?.toString();
  final currentPartnerId = currentData["partnerRequestId"]?.toString();
  final previousPartnerId = previousData?["partnerRequestId"]?.toString();

  if (currentStatus == "pending_confirmation" &&
      previousStatus != "pending_confirmation") {
    final confirmationBy = currentData["confirmationBy"]?.toString();
    if (confirmationBy != null && confirmationBy != myUserId) {
      final partnerNameRaw = await _fetchPartnerName(currentPartnerId);
      final displayName =
          NotiService.formatDisplayName(partnerNameRaw, fallback: "A student");
      await _showSwapNotification(
        title: _kTitleNewSwapRequest,
        body: "$displayName wants to swap courses with you.",
      );
    }
  }

  if (currentStatus == "confirmed" && previousStatus != "confirmed") {
    final confirmedBy = currentData["confirmedBy"]?.toString();
    if (confirmedBy != null && confirmedBy != myUserId) {
      final partnerNameRaw = await _fetchPartnerName(
        currentPartnerId ?? previousPartnerId,
      );
      final displayName =
          NotiService.formatDisplayName(partnerNameRaw, fallback: "Your partner");
      await _showSwapNotification(
        title: _kTitleSwapConfirmed,
        body: "$displayName accepted your swap request.",
      );
    }
  }

  if (previousStatus == "pending_confirmation" && currentStatus == "open") {
    final prevConfirmationBy = previousData?["confirmationBy"]?.toString();
    final prevExpiresAt = previousData?["confirmationExpiresAt"];
    bool timedOut = false;
    if (prevExpiresAt is Timestamp) {
      final expiry = prevExpiresAt.toDate();
      timedOut = DateTime.now().isAfter(expiry);
    }

    if (prevConfirmationBy != null && prevConfirmationBy == myUserId) {
      if (timedOut) {
        await _showSwapNotification(
          title: _kTitleSwapTimeout,
          body: _kBodySwapTimeout,
        );
      } else {
        final partnerNameRaw = await _fetchPartnerName(previousPartnerId);
        final displayName = NotiService.formatDisplayName(
          partnerNameRaw,
          fallback: "Your partner",
        );
        await _showSwapNotification(
          title: _kTitleSwapDeclined,
          body: "$displayName declined your swap request.",
        );
      }
    } else if (timedOut) {
      await _showSwapNotification(
        title: _kTitleSwapTimeout,
        body: _kBodySwapTimeout,
      );
    }
  }
}

Future<void> _showSwapNotification({
  required String title,
  required String body,
}) async {
  try {
    await NotiService.showSwapAlert(title: title, body: body);
  } catch (e) {
    debugPrint("⚠️ Failed to display swap notification locally: $e");
  }
}

Future<String?> _fetchPartnerName(String? partnerRequestId) async {
  if (partnerRequestId == null || partnerRequestId.isEmpty) return null;
  try {
    final partnerDoc = await FirebaseFirestore.instance
        .collection("swap_requests")
        .doc(partnerRequestId)
        .get();
    return partnerDoc.data()?["studentName"]?.toString();
  } catch (e) {
    debugPrint("⚠️ Unable to fetch partner name for $partnerRequestId: $e");
    return null;
  }
}

class _SwapNotificationRelay {
  _SwapNotificationRelay._();

  static final _SwapNotificationRelay instance = _SwapNotificationRelay._();

  StreamSubscription<DocumentSnapshot>? _subscription;
  Map<String, dynamic>? _previousData;
  String? _trackedRequestId;

  void ensureStarted(String requestId) {
    if (_trackedRequestId == requestId && _subscription != null) return;

    _subscription?.cancel();
    _trackedRequestId = requestId;
    _previousData = null;

    _subscription = FirebaseFirestore.instance
        .collection("swap_requests")
        .doc(requestId)
        .snapshots()
        .listen(
      (snapshot) async {
        final currentData = snapshot.data() as Map<String, dynamic>?;
        if (currentData == null) {
          _previousData = null;
          return;
        }

        final myUserId = currentData["userId"]?.toString();
        if (myUserId == null || myUserId.isEmpty) {
          _previousData = Map<String, dynamic>.from(currentData);
          return;
        }

        await _processSwapStatusChange(
          previousData: _previousData,
          currentData: currentData,
          myUserId: myUserId,
        );

        _previousData = Map<String, dynamic>.from(currentData);
      },
      onError: (error) {
        debugPrint("⚠️ Swap notification watcher error: $error");
      },
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _previousData = null;
    _trackedRequestId = null;
  }

  void stopIfMatches(String requestId) {
    if (_trackedRequestId != requestId) return;
    stop();
  }
}

void ensureSwapNotificationRelay(String requestId) =>
    _SwapNotificationRelay.instance.ensureStarted(requestId);

void stopSwapNotificationRelay([String? requestId]) {
  if (requestId == null) {
    _SwapNotificationRelay.instance.stop();
  } else {
    _SwapNotificationRelay.instance.stopIfMatches(requestId);
  }
}
