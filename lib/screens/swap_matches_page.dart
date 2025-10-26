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
  bool _hasMustPriorityMatch = false;
  String? _missingMustCourseMessage;

  @override
  void initState() {
    super.initState();
    _fetchAndSortMatches();
  }

  /// 🔹 Fetch and intelligently sort matching swap requests
  Future<void> _fetchAndSortMatches() async {
    try {
      final userData = widget.userRequestData;
      final fromGroup = userData["fromGroup"];
      final toGroup = userData["toGroup"];
      final major = userData["major"];
      final level = userData["level"];
      final gender = userData["gender"];

      // Extract user's additional course preferences
      final specialRequests = userData["specialRequests"] ?? {};
      final myWantCourses = (specialRequests["want"] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // Step 1: Fetch base matches (gender, major, level, reverse groups, open status)
      final snapshot = await FirebaseFirestore.instance
          .collection("swap_requests")
          .where("major", isEqualTo: major)
          .where("gender", isEqualTo: gender)
          .where("level", isEqualTo: level)
          .where("fromGroup", isEqualTo: toGroup)
          .where("toGroup", isEqualTo: fromGroup)
          .where("status", isEqualTo: "open")
          .get();

      final allMatches = snapshot.docs.map((doc) {
        final data = doc.data();
        data["id"] = doc.id;
        return data;
      }).toList();

      // Step 2: Calculate match scores based on additional courses
      final scoredMatches = allMatches.map((match) {
        final score = _calculateMatchScore(match, myWantCourses);
        return {
          ...match,
          "matchScore": score["score"],
          "matchedMustCourses": score["matchedMustCourses"],
          "matchedOptionalCourses": score["matchedOptionalCourses"],
          "totalMatchedCourses": score["totalMatchedCourses"],
        };
      }).toList();

      // Step 3: Sort by match score (higher score = better match)
      scoredMatches.sort((a, b) => (b["matchScore"] as int).compareTo(a["matchScore"] as int));

      // Step 4: Check if any match satisfies "Must" priority courses
      _hasMustPriorityMatch = _checkMustPriorityMatch(scoredMatches, myWantCourses);

      // Step 5: Generate message if "Must" courses are not matched
      if (!_hasMustPriorityMatch && myWantCourses.any((c) => c["priority"] == "Must")) {
        final mustCourses = myWantCourses
            .where((c) => c["priority"] == "Must")
            .map((c) => "${c["course"]} (Section ${c["section"]})")
            .join(", ");
        _missingMustCourseMessage = 
            "⚠️ No exact matches found for your MUST courses: $mustCourses\n\nShowing best available matches:";
      }

      setState(() {
        matches = scoredMatches;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ Error fetching matches: $e");
      setState(() => _loading = false);
    }
  }

  /// 🔹 Calculate match score based on additional courses
  Map<String, dynamic> _calculateMatchScore(
    Map<String, dynamic> match,
    List<Map<String, dynamic>> myWantCourses,
  ) {
    int score = 0;
    int matchedMustCourses = 0;
    int matchedOptionalCourses = 0;

    final matchSpecialRequests = match["specialRequests"] ?? {};
    final matchHaveCourses = (matchSpecialRequests["have"] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // Check each course I want against what the match has
    for (final wantCourse in myWantCourses) {
      final wantCourseCode = wantCourse["course"];
      final wantSection = wantCourse["section"];
      final priority = wantCourse["priority"] ?? "Optional";

      // Check if match has this course
      final hasMatch = matchHaveCourses.any((haveCourse) {
        return haveCourse["course"] == wantCourseCode && 
               haveCourse["section"] == wantSection;
      });

      if (hasMatch) {
        if (priority == "Must") {
          score += 100; // High score for "Must" matches
          matchedMustCourses++;
        } else {
          score += 10; // Lower score for "Optional" matches
          matchedOptionalCourses++;
        }
      }
    }

    return {
      "score": score,
      "matchedMustCourses": matchedMustCourses,
      "matchedOptionalCourses": matchedOptionalCourses,
      "totalMatchedCourses": matchedMustCourses + matchedOptionalCourses,
    };
  }

  /// 🔹 Check if any match satisfies all "Must" priority courses
  bool _checkMustPriorityMatch(
    List<Map<String, dynamic>> matches,
    List<Map<String, dynamic>> myWantCourses,
  ) {
    final mustCourses = myWantCourses.where((c) => c["priority"] == "Must").toList();
    if (mustCourses.isEmpty) return true; // No "Must" courses required

    // Check if at least one match has all "Must" courses
    return matches.any((match) {
      final matchedMust = match["matchedMustCourses"] as int;
      return matchedMust == mustCourses.length;
    });
  }

  /// 🔹 Send confirmation and reserve both requests
  Future<void> _sendConfirmation(Map<String, dynamic> match) async {
    try {
      final senderId = widget.userId;
      final receiverId = match["userId"];
      final senderRequestId = widget.userRequestId;
      final receiverRequestId = match["id"];

      final senderRef = FirebaseFirestore.instance
          .collection("swap_requests")
          .doc(senderRequestId);
      final receiverRef = FirebaseFirestore.instance
          .collection("swap_requests")
          .doc(receiverRequestId);

      final senderSnap = await senderRef.get();
      final receiverSnap = await receiverRef.get();

      if (!senderSnap.exists || !receiverSnap.exists) {
        _showSnack("One of the swap requests no longer exists.", isError: true);
        return;
      }

      final senderStatus = senderSnap.data()?["status"];
      final receiverStatus = receiverSnap.data()?["status"];

      if (senderStatus != "open" || receiverStatus != "open") {
        _showSnack("One of the requests is already reserved or closed.",
            isError: true);
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
        if (_missingMustCourseMessage != null) _buildWarningBanner(),
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
                      _buildMatchCard(context, matches[index], index),
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

  Widget _buildWarningBanner() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade700, width: 2),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade800, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _missingMustCourseMessage!,
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildMatchCard(
      BuildContext context, Map<String, dynamic> match, int index) {
    final from = match["fromGroup"]?.toString() ?? "-";
    final to = match["toGroup"]?.toString() ?? "-";
    final name = match["studentName"] ?? "Student";
    final matchScore = match["matchScore"] as int;
    final matchedMust = match["matchedMustCourses"] as int;
    final matchedOptional = match["matchedOptionalCourses"] as int;
    final totalMatched = match["totalMatchedCourses"] as int;

    // Determine match quality badge
    String badgeText = "";
    Color badgeColor = Colors.grey;
    if (matchedMust > 0) {
      badgeText = "✨ PERFECT MATCH";
      badgeColor = Colors.green;
    } else if (matchedOptional > 0) {
      badgeText = "✓ Good Match";
      badgeColor = Colors.blue;
    } else {
      badgeText = "Basic Match";
      badgeColor = Colors.grey;
    }

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
            // Match rank badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Rank #${index + 1}",
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
            if (totalMatched > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Matched Courses:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (matchedMust > 0)
                      Text(
                        "✓ $matchedMust MUST priority course(s)",
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (matchedOptional > 0)
                      Text(
                        "✓ $matchedOptional Optional course(s)",
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _viewMatchDetails(match),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text("View Details"),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _sendConfirmation(match),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text("Select"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _viewMatchDetails(Map<String, dynamic> match) {
    final specialRequests = match["specialRequests"] ?? {};
    final haveCourses = (specialRequests["have"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final wantCourses = (specialRequests["want"] as List?)?.cast<Map<String, dynamic>>() ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal),
                  ),
                  const SizedBox(height: 15),
                  _buildDetailRow("Student Name", match["studentName"] ?? "N/A"),
                  _buildDetailRow("From Group", match["fromGroup"]?.toString() ?? "-"),
                  _buildDetailRow("To Group", match["toGroup"]?.toString() ?? "-"),
                  _buildDetailRow("Major", match["major"] ?? "N/A"),
                  _buildDetailRow("Level", match["level"]?.toString() ?? "N/A"),
                  _buildDetailRow("Gender", match["gender"] ?? "N/A"),
                  const SizedBox(height: 20),
                  if (haveCourses.isNotEmpty) ...[
                    const Text(
                      "Additional Courses They Have:",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...haveCourses.map((course) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            "• ${course["course"]} - Section ${course["section"]}",
                            style: const TextStyle(fontSize: 14),
                          ),
                        )),
                    const SizedBox(height: 15),
                  ],
                  if (wantCourses.isNotEmpty) ...[
                    const Text(
                      "Courses They Want:",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...wantCourses.map((course) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            "• ${course["course"]} - Section ${course["section"]} (${course["priority"]})",
                            style: const TextStyle(fontSize: 14),
                          ),
                        )),
                    const SizedBox(height: 15),
                  ],
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _sendConfirmation(match);
                      },
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
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              "$label:",
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
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
    final duration = widget.expiresAt.toDate().difference(DateTime.now());
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

  Widget _buildPending(BuildContext context, int hours, int minutes) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_bottom, size: 70, color: Colors.teal),
              const SizedBox(height: 20),
              Text(
                "Waiting for ${widget.partnerName} to confirm...",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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