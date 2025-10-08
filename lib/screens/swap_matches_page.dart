import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SwapMatchesPage extends StatefulWidget {
  final String userId;
  final String userRequestId;
  final Map<String, dynamic> userRequestData;

  const SwapMatchesPage({
    super.key,
    required this.userId,
    required this.userRequestId,
    required this.userRequestData,
  });

  @override
  State<SwapMatchesPage> createState() => _SwapMatchesPageState();
}

class _SwapMatchesPageState extends State<SwapMatchesPage> {
  bool _loading = true;
  List<Map<String, dynamic>> matches = [];

  @override
  void initState() {
    super.initState();
    _fetchMatches();
  }

  /// 🔹 Fetch matching swap requests
  Future<void> _fetchMatches() async {
    try {
      final userData = widget.userRequestData;
      final fromGroup = userData["fromGroup"];
      final toGroup = userData["toGroup"];
      final major = userData["major"];
      final level = userData["level"];
      final gender = userData["gender"];

      final snapshot = await FirebaseFirestore.instance
          .collection("swap_requests")
          .where("major", isEqualTo: major)
          .where("gender", isEqualTo: gender)
          .where("level", isEqualTo: level)
          .where("fromGroup", isEqualTo: toGroup)
          .where("toGroup", isEqualTo: fromGroup)
          .where("status", isEqualTo: "open")
          .get();

      final results = snapshot.docs.map((doc) {
        final data = doc.data();
        data["id"] = doc.id;
        return data;
      }).toList();

      setState(() {
        matches = results;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error fetching matches: $e");
      setState(() => _loading = false);
    }
  }

  /// 🔹 Send confirmation and reserve both requests
  Future<void> _sendConfirmation(Map<String, dynamic> match) async {
    try {
      final senderId = widget.userId;
      final receiverId = match["userId"];
      final senderRequestId = widget.userRequestId;
      final receiverRequestId = match["id"];

      final senderRef =
          FirebaseFirestore.instance.collection("swap_requests").doc(senderRequestId);
      final receiverRef =
          FirebaseFirestore.instance.collection("swap_requests").doc(receiverRequestId);

      final senderSnap = await senderRef.get();
      final receiverSnap = await receiverRef.get();

      if (!senderSnap.exists || !receiverSnap.exists) {
        _showSnack("One of the swap requests no longer exists.", isError: true);
        return;
      }

      final senderStatus = senderSnap.data()?["status"];
      final receiverStatus = receiverSnap.data()?["status"];

      if (senderStatus != "open" || receiverStatus != "open") {
        _showSnack("One of the requests is already reserved or closed.", isError: true);
        return;
      }

      // 🔹 Reserve both requests for 6 hours
      final now = DateTime.now();
      final expiresAt = Timestamp.fromDate(now.add(const Duration(hours: 6)));

      final batch = FirebaseFirestore.instance.batch();
      batch.update(senderRef, {
        "status": "pending_confirmation",
        "partnerRequestId": receiverRequestId,
        "confirmationBy": senderId,
        "confirmationExpiresAt": expiresAt,
      });
      batch.update(receiverRef, {
        "status": "pending_confirmation",
        "partnerRequestId": senderRequestId,
        "confirmationBy": senderId,
        "confirmationExpiresAt": expiresAt,
      });
      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        _showSnack("Confirmation sent successfully ✅");
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingForConfirmationPage(
              expiresAt: expiresAt,
              partnerName: match["studentName"] ?? "Student",
            ),
          ),
        );
      }
    } catch (e) {
      _showSnack("Error sending confirmation: $e", isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0097B2), Color(0xFF0E0259)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(
          child: matches.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 25),
                    child: Text(
                      "No matching offers found yet.\nIf a reserved match expires, you'll be able to try again.",
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: matches.length,
                  itemBuilder: (context, index) =>
                      _buildMatchCard(context, matches[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildAppBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  "Matching Offers",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40), // for symmetry
          ],
        ),
      );

  Widget _buildMatchCard(BuildContext context, Map<String, dynamic> match) {
    final from = match["fromGroup"]?.toString() ?? "-";
    final to = match["toGroup"]?.toString() ?? "-";
    final name = match["studentName"] ?? "Student";

    return Card(
      elevation: 5,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              "From Group $from → To Group $to",
              style: const TextStyle(color: Colors.black87, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _viewMatchDetails(match),
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                label: const Text("View Details"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _viewMatchDetails(Map<String, dynamic> match) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Match Details",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal),
              ),
              const SizedBox(height: 10),
              Text("From Group: ${match["fromGroup"]}"),
              Text("To Group: ${match["toGroup"]}"),
              const SizedBox(height: 25),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () => _sendConfirmation(match),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text("Send Confirmation"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

/// 🕒 Live Waiting Page — Auto-Updates When Partner Confirms
class WaitingForConfirmationPage extends StatefulWidget {
  final Timestamp expiresAt;
  final String partnerName;

  const WaitingForConfirmationPage({
    super.key,
    required this.expiresAt,
    required this.partnerName,
  });

  @override
  State<WaitingForConfirmationPage> createState() =>
      _WaitingForConfirmationPageState();
}

class _WaitingForConfirmationPageState
    extends State<WaitingForConfirmationPage> {
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _startExpiryTimer();
  }

  /// Automatically mark expired after 6 hours
  void _startExpiryTimer() {
    final duration =
        widget.expiresAt.toDate().difference(DateTime.now());
    Future.delayed(duration, () {
      if (mounted && !_expired) {
        setState(() => _expired = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final expiryTime = widget.expiresAt.toDate();
    final remaining = expiryTime.difference(DateTime.now());
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: const Text("Waiting for Confirmation"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("swap_requests")
            .where("status", isEqualTo: "confirmed")
            .snapshots(),
        builder: (context, snapshot) {
          // 🔹 Case 1 – confirmed
          if (snapshot.hasData &&
              snapshot.data!.docs.isNotEmpty &&
              !_expired) {
            return _buildConfirmed(context);
          }

          // 🔹 Case 2 – expired
          if (_expired || DateTime.now().isAfter(expiryTime)) {
            return _buildExpired(context);
          }

          // 🔹 Default – still pending
          return _buildPending(context, hours, minutes);
        },
      ),
    );
  }

  Widget _buildConfirmed(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified, size: 80, color: Colors.green),
              const SizedBox(height: 20),
              Text(
                "Your swap with ${widget.partnerName} has been CONFIRMED!",
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Generate PDF"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      );

  Widget _buildExpired(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_off, size: 80, color: Colors.redAccent),
              const SizedBox(height: 20),
              const Text(
                "Reservation expired.",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent),
              ),
              const SizedBox(height: 10),
              const Text(
                "The 6-hour period ended before confirmation.",
                style: TextStyle(color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _buildPending(
      BuildContext context, int hours, int minutes) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_bottom,
                  size: 70, color: Colors.teal),
              const SizedBox(height: 20),
              Text(
                "Waiting for ${widget.partnerName} to confirm...",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                "If no response is received within 6 hours, "
                "the reservation will expire.",
                style: TextStyle(color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Text(
                "Time left: $hours h $minutes m",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.teal),
              ),
            ],
          ),
        ),
      );
}

