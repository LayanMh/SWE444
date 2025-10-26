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

  @override
  void initState() {
    super.initState();
    _subscribeToRequest();
  }

  void _subscribeToRequest() {
    _subscription = FirebaseFirestore.instance
        .collection("swap_requests")
        .doc(widget.requestId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      setState(() => _data = doc.data());
      _checkIncomingConfirmation();
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      setState(() => _loading = false);
    });
  }

  void _checkIncomingConfirmation() async {
    if (_popupShown || _data == null) return;

    final status = _data?["status"];
    final confirmationBy = _data?["confirmationBy"];
    final partnerId = _data?["partnerRequestId"];

    if (status == "pending_confirmation" &&
        confirmationBy != null &&
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Swap Confirmation Request"),
          content: Text(
            "$partnerName wants to swap:\n\nFrom Group $from → To Group $to\n\nDo you want to confirm this swap?",
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _declineSwap(partnerId);
              },
              child: const Text("Decline",
                  style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
      final myRef = FirebaseFirestore.instance
          .collection("swap_requests")
          .doc(widget.requestId);
      final partnerRef =
          FirebaseFirestore.instance.collection("swap_requests").doc(partnerId);

      batch.update(myRef, {
        "status": "confirmed",
        "confirmedBy": _data?["userId"],
        "confirmationExpiresAt": FieldValue.delete(),
      });
      batch.update(partnerRef, {
        "status": "confirmed",
        "confirmedBy": _data?["userId"],
        "confirmationExpiresAt": FieldValue.delete(),
      });

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Swap confirmed successfully ✅"),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      debugPrint("❌ Error confirming swap: $e");
    }
  }

  Future<void> _declineSwap(String partnerId) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final myRef = FirebaseFirestore.instance
          .collection("swap_requests")
          .doc(widget.requestId);
      final partnerRef =
          FirebaseFirestore.instance.collection("swap_requests").doc(partnerId);

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
        content: Text("Swap declined."),
        backgroundColor: Colors.redAccent,
      ));
    } catch (e) {
      debugPrint("❌ Error declining swap: $e");
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
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
          icon:
              const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
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
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : _data == null
                  ? const Center(
                      child: Text("No request found.",
                          style: TextStyle(color: Colors.white)))
                  : _buildContent(),
        ),
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

    Color statusColor;
    String statusText;
    switch (status) {
      case "pending_confirmation":
        statusColor = Colors.orange;
        statusText = "Pending Confirmation";
        break;
      case "confirmed":
        statusColor = Colors.green;
        statusText = "Confirmed";
        break;
      default:
        statusColor = Colors.grey.shade300;
        statusText = "Open";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
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
          _statusCard(statusText, statusColor),
          const SizedBox(height: 30),
          _detailsCard(fromGroup, toGroup, major, level, gender),
          const SizedBox(height: 25),
          _actionButtons(userId, status),
        ],
      ),
    );
  }

  Widget _statusCard(String text, Color color) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
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
          child: Text(
            "CURRENT STATUS: $text",
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.1,
            ),
          ),
        ),
      );

  Widget _detailsCard(
      String from, String to, String major, String level, String gender) {
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
          ],
        ),
      ),
    );
  }

  Widget _actionButtons(String userId, String status) {
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
        if (!isConfirmed)
          _primaryBtn(
            color: kIndigo,
            icon: Icons.edit,
            label: isPending ? "View Status" : "Edit Request",
            onPressed: () {
              if (isPending) return;
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