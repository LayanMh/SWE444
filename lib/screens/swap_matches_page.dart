import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';

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
  // Design colors matching profile page
  static const Color kBg = Color(0xFFE6F3FF);
  static const Color kTopBar = Color(0xFF0D4F94);
  
  bool _loading = true;
  List<Map<String, dynamic>> matches = [];
  bool _hasMustPriorityMatch = false;
  String? _missingMustCourseMessage;
  int _selectedIndex = 2;

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
      final myWantCourses = (specialRequests["want"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];

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

      // Filter out the user's own request
      final filteredMatches = allMatches.where((match) => match["id"] != widget.userRequestId).toList();

      // Step 2: Calculate match scores based on additional courses
      final scoredMatches = filteredMatches.map((match) {
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
    int mutualBenefitScore = 0;

    final matchSpecialRequests = match["specialRequests"] ?? {};
    final matchHaveCourses = (matchSpecialRequests["have"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    final matchWantCourses = (matchSpecialRequests["want"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    
    // Get my courses from widget data
    final mySpecialRequests = widget.userRequestData["specialRequests"] ?? {};
    final myHaveCourses = (mySpecialRequests["have"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];

    // DIRECTION 1: Check if THEY HAVE what I WANT
    for (final wantCourse in myWantCourses) {
      final wantCourseCode = wantCourse["course"];
      final priority = wantCourse["priority"] ?? "Optional";

      final hasMatch = matchHaveCourses.any((haveCourse) {
        return haveCourse["course"] == wantCourseCode;
      });

      if (hasMatch) {
        if (priority == "Must") {
          score += 1000;
          matchedMustCourses++;
        } else {
          score += 10;
          matchedOptionalCourses++;
        }
      }
    }

    // DIRECTION 2: Check if I HAVE what THEY WANT
    for (final theirWant in matchWantCourses) {
      final theirWantCourse = theirWant["course"];
      final theirPriority = theirWant["priority"] ?? "Optional";

      final iHaveIt = myHaveCourses.any((myHave) {
        return myHave["course"] == theirWantCourse;
      });

      if (iHaveIt) {
        if (theirPriority == "Must") {
          mutualBenefitScore += 1000;
        } else {
          mutualBenefitScore += 10;
        }
      }
    }

    final totalScore = score + mutualBenefitScore;

    return {
      "score": totalScore,
      "matchedMustCourses": matchedMustCourses,
      "matchedOptionalCourses": matchedOptionalCourses,
      "totalMatchedCourses": matchedMustCourses + matchedOptionalCourses,
      "mutualBenefit": mutualBenefitScore > 0,
    };
  }

  /// 🔹 Check if any match satisfies all "Must" priority courses
  bool _checkMustPriorityMatch(
    List<Map<String, dynamic>> matches,
    List<Map<String, dynamic>> myWantCourses,
  ) {
    final mustCourses = myWantCourses.where((c) => c["priority"] == "Must").toList();
    if (mustCourses.isEmpty) return true;

    return matches.any((match) {
      final matchedMust = match["matchedMustCourses"] as int;
      return matchedMust == mustCourses.length;
    });
  }

  /// 🔹 Send confirmation and reserve both requests
  Future<void> _sendConfirmation(Map<String, dynamic> match) async {
    try {
      final senderId = widget.userId;
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

      // Reserve both requests for 6 hours
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
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
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

  void _navigateToMainTab(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    _navigateToMainTab(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header with stars - matching profile page
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: BoxDecoration(
                color: kTopBar,
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Matching Offers',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: kTopBar))
                  : _buildContent(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xF2EAF3FF),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                active: _selectedIndex == 0,
                onTap: () => _onNavTap(0),
              ),
              _NavItem(
                icon: Icons.event_available_outlined,
                label: 'Schedule',
                active: _selectedIndex == 1,
                onTap: () => _onNavTap(1),
              ),
              _NavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                active: _selectedIndex == 2,
                onTap: () => _onNavTap(2),
              ),
              _NavItem(
                icon: Icons.school_outlined,
                label: 'Experience',
                active: _selectedIndex == 3,
                onTap: () => _onNavTap(3),
              ),
              _NavItem(
                icon: Icons.people_outline,
                label: 'Community',
                active: _selectedIndex == 4,
                onTap: () => _onNavTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        if (_missingMustCourseMessage != null) _buildWarningBanner(),
        Expanded(
          child: matches.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 25),
                    child: Text(
                      "No matching offers found yet.\nCheck back later or adjust your requirements.",
                      style: TextStyle(color: kTopBar.withOpacity(0.6), fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  itemCount: matches.length,
                  itemBuilder: (context, index) =>
                      _buildMatchCard(context, matches[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildWarningBanner() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF9800), width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFF9800), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _missingMustCourseMessage!,
                style: const TextStyle(
                  color: Color(0xFFE65100),
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

    String badgeText = "";
    Color badgeColor = Colors.grey;
    if (matchedMust > 0) {
      badgeText = "⭐ PERFECT MATCH";
      badgeColor = const Color(0xFF4CAF50);
    } else if (matchedOptional > 0) {
      badgeText = "✓ Good Match";
      badgeColor = const Color(0xFF2196F3);
    } else {
      badgeText = "Basic Match";
      badgeColor = const Color(0xFF9E9E9E);
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
              Icon(Icons.person, color: kTopBar),
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
                  color: kTopBar.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kTopBar.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Matched Courses:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: kTopBar,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (matchedMust > 0)
                      Text(
                        "⭐ $matchedMust MUST priority course(s)",
                        style: const TextStyle(
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (matchedOptional > 0)
                      Text(
                        "✓ $matchedOptional Optional course(s)",
                        style: const TextStyle(
                          color: Color(0xFF2196F3),
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
                    foregroundColor: kTopBar,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _sendConfirmation(match),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text("Select"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kTopBar,
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
    final haveCourses = (specialRequests["have"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    final wantCourses = (specialRequests["want"] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final bool isTallDevice = media.size.height >= 820;
        final double heightFactor = isTallDevice ? 0.78 : 0.9;
        final double sheetHeight = media.size.height * heightFactor;
        final double horizontalPadding = media.size.width > 500 ? 32 : 20;

        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: sheetHeight,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ).copyWith(bottom: 24),
                      children: [
                        Text(
                          "Match Details",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: kTopBar,
                          ),
                        ),
                        const SizedBox(height: 15),
                        _buildDetailRow(
                            "Student Name", match["studentName"] ?? "N/A"),
                        _buildDetailRow("From Group",
                            match["fromGroup"]?.toString() ?? "-"),
                        _buildDetailRow(
                            "To Group", match["toGroup"]?.toString() ?? "-"),
                        _buildDetailRow("Major", match["major"] ?? "N/A"),
                        _buildDetailRow(
                            "Level", match["level"]?.toString() ?? "N/A"),
                        _buildDetailRow("Gender", match["gender"] ?? "N/A"),
                        const SizedBox(height: 20),
                        if (haveCourses.isNotEmpty) ...[
                          Text(
                            "Additional Courses They Have:",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: kTopBar,
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
                        const SizedBox(height: 12),
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _sendConfirmation(match);
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text("Send Confirmation"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kTopBar,
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
                  ),
                ],
              ),
            ),
          ),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const inactiveColor = Color(0xFF7A8DA8);
    const activeColor = Color(0xFF2E5D9F);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? activeColor : inactiveColor, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? activeColor : inactiveColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: active ? 26 : 0,
                decoration: BoxDecoration(
                  color: active ? activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}