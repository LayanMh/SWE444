import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ NEW
import 'home_page.dart';
import 'MySwapRequestPage.dart'; // ✅ NEW: For navigation from edit mode

class SwapRequestPage extends StatefulWidget {
  final String? existingRequestId;
  final Map<String, dynamic>? initialData;

  const SwapRequestPage({super.key, this.existingRequestId, this.initialData});

  @override
  State<SwapRequestPage> createState() => _SwapRequestPageState();
}

class _SwapRequestPageState extends State<SwapRequestPage> {
  final _formKey = GlobalKey<FormState>();

  String? fromGroup;
  String? toGroup;
  String? userMajor;
  String? userGender;
  int? userLevel;
  String? userId; // ✅ NEW
  String? studentName; // ✅ NEW
  String? studentEmail; // ✅ NEW

  final List<Map<String, String>> haveCourses = [];
  final List<Map<String, String>> wantCourses = [];
  final List<String> deletedCourses = []; // ✅ KEEPING: field name stays as deletedCourses for database compatibility

  final haveCourseCodeController = TextEditingController();
  final haveSectionController = TextEditingController();
  final wantCourseCodeController = TextEditingController();
  final wantSectionController = TextEditingController();
  final deletedCourseController = TextEditingController(); // ✅ KEEPING: controller name stays same

  String priority = "Must";
  bool _loadingUser = true;
  bool _loadingGroups = false;
  List<int> availableGroups = [];

  // for collapsible sections
  bool showHave = false;
  bool showWant = false;
  bool showDelete = false; // ✅ KEEPING: internal variable name (only UI text changes)

  int _selectedIndex = 2; // ✅ NEW: Default to home tab

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    if (widget.initialData != null) _loadExistingData(widget.initialData!);
  }

  void _loadExistingData(Map<String, dynamic> data) {
    setState(() {
      fromGroup = data["fromGroup"]?.toString();
      toGroup = data["toGroup"]?.toString();
      final special = data["specialRequests"] ?? {};
      
      // ✅ FIXED: Properly convert from Map<String, dynamic> to Map<String, String>
      if (special["have"] != null) {
        for (var item in special["have"]) {
          haveCourses.add(Map<String, String>.from(item as Map));
        }
      }
      
      if (special["want"] != null) {
        for (var item in special["want"]) {
          wantCourses.add(Map<String, String>.from(item as Map));
        }
      }
      
      deletedCourses.addAll((data["deletedCourses"] as List?)?.cast<String>() ?? []);
    });
  }

  Future<void> _fetchUserData() async {
    try {
      // ✅ NEW: Get userId from either Firebase Auth or SharedPreferences
      userId = await _getUserId();
      if (userId == null) throw Exception("User not logged in");

      final doc = await FirebaseFirestore.instance.collection("users").doc(userId).get();
      if (!doc.exists) throw Exception("User not found");

      final data = doc.data()!;
      userMajor = _extractValue(data["major"]);
      userGender = _extractValue(data["gender"]);
      userLevel = _extractIntValue(data["level"]);
      
      // ✅ NEW: Extract student name and email
      final fName = _extractValue(data["FName"]) ?? "";
      final lName = _extractValue(data["LName"]) ?? "";
      studentName = "$fName $lName".trim();
      studentEmail = _extractValue(data["email"]) ?? "";

      await _fetchGroups();
    } catch (e) {
      _showMsg("Error loading user info: $e", true);
    } finally {
      setState(() => _loadingUser = false);
    }
  }

  // ✅ NEW: Get user ID from either Firebase Auth or SharedPreferences
  Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    if (microsoftDocId != null) return microsoftDocId;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  String? _extractValue(dynamic field) {
    if (field is List && field.isNotEmpty) return field.first.toString();
    return field?.toString();
  }

  int? _extractIntValue(dynamic field) {
    if (field is List && field.isNotEmpty) {
      final val = field.first;
      return val is int ? val : int.tryParse(val.toString());
    }
    return field is int ? field : int.tryParse(field.toString());
  }

  Future<void> _fetchGroups() async {
    if (userMajor == null || userGender == null || userLevel == null) return;
    setState(() => _loadingGroups = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection("Groups")
          .where("Major", isEqualTo: userMajor!.trim())
          .where("Gender", isEqualTo: userGender!.trim())
          .where("Level", isEqualTo: userLevel)
          .get();

      final groups = snapshot.docs
          .map((doc) => _extractIntValue(doc.data()["Number"]))
          .whereType<int>()
          .toList()
        ..sort();

      setState(() => availableGroups = groups);
    } catch (e) {
      _showMsg("Error fetching groups: $e", true);
    } finally {
      setState(() => _loadingGroups = false);
    }
  }

  bool _isValidCourseCode(String code) => RegExp(r'^[A-Z]{2,4}[0-9]{3}$').hasMatch(code);
  bool _isValidSection(String section) => RegExp(r'^[0-9]{5}$').hasMatch(section); // ✅ CHANGED: Exactly 5 digits

  void _addHaveCourse() {
    final code = haveCourseCodeController.text.trim().toUpperCase();
    final section = haveSectionController.text.trim();
    if (!_isValidCourseCode(code)) return _showMsg("Invalid course code (e.g., CSC111)", true);
    if (!_isValidSection(section)) return _showMsg("Section must be exactly 5 digits", true); // ✅ CHANGED message
    setState(() {
      haveCourses.add({"course": code, "section": section});
      haveCourseCodeController.clear();
      haveSectionController.clear();
    });
  }

  void _addWantCourse() {
    final code = wantCourseCodeController.text.trim().toUpperCase();
    final section = wantSectionController.text.trim();
    if (!_isValidCourseCode(code)) return _showMsg("Invalid course code (e.g., SWE486)", true);
    if (!_isValidSection(section)) return _showMsg("Section must be exactly 5 digits", true); // ✅ CHANGED message
    setState(() {
      wantCourses.add({"course": code, "section": section, "priority": priority});
      wantCourseCodeController.clear();
      wantSectionController.clear();
      priority = "Must";
    });
  }

  void _addDeletedCourse() { // ✅ KEEPING: function name stays same
    final code = deletedCourseController.text.trim().toUpperCase();
    if (!_isValidCourseCode(code)) return _showMsg("Invalid course code (e.g., MATH101)", true);
    setState(() {
      deletedCourses.add(code);
      deletedCourseController.clear();
    });
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      final data = {
        "userId": userId, // ✅ CHANGED: Use stored userId
        "studentName": studentName, // ✅ NEW: For matching page and PDF
        "studentEmail": studentEmail, // ✅ NEW: For matching page and PDF
        "major": userMajor,
        "gender": userGender,
        "level": userLevel,
        "fromGroup": int.parse(fromGroup!),
        "toGroup": int.parse(toGroup!),
        "specialRequests": {"have": haveCourses, "want": wantCourses},
        "deletedCourses": deletedCourses, // ✅ KEEPING: database field name stays same
        "status": "open",
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(), // ✅ NEW
      };

      String requestId;
      if (widget.existingRequestId != null) {
        await FirebaseFirestore.instance
            .collection("swap_requests")
            .doc(widget.existingRequestId)
            .update({...data, "updatedAt": FieldValue.serverTimestamp()});
        requestId = widget.existingRequestId!;
        _showMsg("Request updated successfully!", false);
      } else {
        final docRef = await FirebaseFirestore.instance.collection("swap_requests").add(data);
        requestId = docRef.id;
        _showMsg("Swap request posted successfully!", false);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MySwapRequestPage(requestId: requestId)),
        );
      }
    } catch (e) {
      _showMsg("Error: $e", true);
    }
  }

  void _showMsg(String msg, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  // ✅ NEW: Handle bottom navigation
  void _onNavTap(int index) {
    if (index == 2) return; // Already on swapping
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
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0097B2), Color(0xFF0E0259)],
          ),
        ),
        child: SafeArea(
          bottom: false, // ✅ NEW: Don't apply safe area to bottom for nav bar
          child: _loadingUser
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 30, 20, 100), // ✅ CHANGED: Extra bottom padding for nav bar
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with centered title
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                            onPressed: () {
                              // ✅ FIXED: If editing, go back to details page, not home
                              if (widget.existingRequestId != null) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MySwapRequestPage(requestId: widget.existingRequestId!),
                                  ),
                                );
                              } else {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (_) => const HomePage()),
                                );
                              }
                            },
                          ),
                          const Expanded(
                            child: Text(
                              "Swapping Request",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 48), // For symmetry
                        ],
                      ),
                      const SizedBox(height: 25),

                      // Main card
                      Card(
                        color: Colors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle("Group Information", const Color(0xFF0E0259)),
                                _loadingGroups
                                    ? const Center(child: CircularProgressIndicator())
                                    : _buildGroupCard(),
                                const SizedBox(height: 20),

                                _buildExpandableSection(
                                  "Additional Courses I Have",
                                  const Color(0xFF0097B2),
                                  showHave,
                                  () => setState(() => showHave = !showHave),
                                  _buildHaveSection(),
                                ),
                                const SizedBox(height: 10),

                                _buildExpandableSection(
                                  "Additional Courses I Want",
                                  const Color(0xFF0E0259),
                                  showWant,
                                  () => setState(() => showWant = !showWant),
                                  _buildWantSection(),
                                ),
                                const SizedBox(height: 10),

                                _buildExpandableSection(
                                  "Completed Main Courses", // ✅ ONLY UI TEXT CHANGED - field name stays "deletedCourses"
                                  Colors.green, // ✅ Color changed to green
                                  showDelete, // ✅ KEEPING: variable name stays same
                                  () => setState(() => showDelete = !showDelete),
                                  _buildDeleteSection(), // ✅ KEEPING: function name stays same
                                ),
                                const SizedBox(height: 30),
                                _buildSubmitButton(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

  Widget _buildSectionTitle(String text, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        const SizedBox(height: 5),
        Container(height: 1.5, color: color.withOpacity(0.7)),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildGroupCard() => Column(
        children: [
          _buildDropdown("From Group *", fromGroup, availableGroups, (val) {
            setState(() {
              fromGroup = val;
              toGroup = null;
            });
          }),
          const SizedBox(height: 15),
          _buildDropdown(
            "To Group *",
            toGroup,
            availableGroups.where((g) => fromGroup == null || g.toString() != fromGroup).toList(),
            (val) => setState(() => toGroup = val),
          ),
        ],
      );

  Widget _buildDropdown(String label, String? value, List<int> items, void Function(String?) onChanged) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: items.map((num) => DropdownMenuItem(value: num.toString(), child: Text("Group $num"))).toList(),
        validator: (v) => v == null ? "Required" : null,
        onChanged: onChanged,
      );

  Widget _buildExpandableSection(String title, Color color, bool expanded, VoidCallback onToggle, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, color: color),
            ],
          ),
        ),
        if (expanded) ...[const SizedBox(height: 10), content],
      ],
    );
  }

  Widget _buildHaveSection() => Column(
        children: [
          _buildCourseInput(haveCourseCodeController, haveSectionController),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _addHaveCourse,
            icon: const Icon(Icons.add),
            label: const Text("Add Course"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0097B2), foregroundColor: Colors.white),
          ),
          const SizedBox(height: 10),
          _buildList(haveCourses),
        ],
      );

  Widget _buildWantSection() => Column(
        children: [
          _buildCourseInput(wantCourseCodeController, wantSectionController),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: priority,
            decoration: const InputDecoration(labelText: "Priority", border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: "Must", child: Text("Must")),
              DropdownMenuItem(value: "Optional", child: Text("Optional")),
            ],
            onChanged: (val) => setState(() => priority = val!),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _addWantCourse,
            icon: const Icon(Icons.add),
            label: const Text("Add Course"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0E0259), foregroundColor: Colors.white),
          ),
          const SizedBox(height: 10),
          _buildList(wantCourses),
        ],
      );

  // ✅ KEEPING: function name stays same, only UI text changes
  Widget _buildDeleteSection() => Column(
        children: [
          TextFormField(
            controller: deletedCourseController,
            decoration: const InputDecoration(
              labelText: "Course Code (e.g., MATH101)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _addDeletedCourse, // ✅ KEEPING: function name
            icon: const Icon(Icons.check_circle_outline), // ✅ Icon changed to checkmark
            label: const Text("Add Completed Course"), // ✅ UI TEXT changed
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, // ✅ Color changed to green
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _buildDeletedList(), // ✅ KEEPING: function name
        ],
      );

  Widget _buildCourseInput(TextEditingController codeCtrl, TextEditingController sectionCtrl) => Column(children: [
        TextFormField(
          controller: codeCtrl,
          decoration: const InputDecoration(labelText: "Course Code (e.g., CSC111)", border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: sectionCtrl,
          decoration: const InputDecoration(
            labelText: "Section Number (5 digits)", // ✅ CHANGED: "4–7 digits" → "5 digits"
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          maxLength: 5, // ✅ NEW: Limit input to 5 characters
        ),
      ]);

  Widget _buildList(List<Map<String, String>> list) => list.isEmpty
      ? const Text("No courses added yet.")
      : Column(
          children: list.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            return Card(
              child: ListTile(
                title: Text("${c["course"]} — Section ${c["section"]}${c["priority"] != null ? ' (${c["priority"]})' : ''}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => list.removeAt(i)),
                ),
              ),
            );
          }).toList(),
        );

  // ✅ KEEPING: function name stays same, only UI text changes
  Widget _buildDeletedList() => deletedCourses.isEmpty
      ? const Text("No completed courses added yet.") // ✅ UI TEXT changed
      : Column(
          children: deletedCourses.asMap().entries.map((entry) {
            final i = entry.key;
            final code = entry.value;
            return Card(
              child: ListTile(
                title: Text(code),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => deletedCourses.removeAt(i)),
                ),
              ),
            );
          }).toList(),
        );

  Widget _buildSubmitButton() => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _submitRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0E0259),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            widget.existingRequestId != null ? "Update Request" : "Submit Request",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      );

  @override
  void dispose() {
    haveCourseCodeController.dispose();
    haveSectionController.dispose();
    wantCourseCodeController.dispose();
    wantSectionController.dispose();
    deletedCourseController.dispose(); // ✅ KEEPING: controller name
    super.dispose();
  }
}