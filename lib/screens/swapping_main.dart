import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';
import 'MySwapRequestPage.dart';

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

  final List<Map<String, String>> haveCourses = [];
  final List<Map<String, String>> wantCourses = [];
  final List<String> deletedCourses = [];

  final haveCourseCodeController = TextEditingController();
  final haveSectionController = TextEditingController();
  final wantCourseCodeController = TextEditingController();
  final wantSectionController = TextEditingController();
  final deletedCourseController = TextEditingController();

  String priority = "Must";
  bool _loadingUser = true;
  bool _loadingGroups = false;
  List<int> availableGroups = [];

  // for collapsible sections
  bool showHave = false;
  bool showWant = false;
  bool showDelete = false;

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
      haveCourses.addAll((special["have"] as List?)?.cast<Map<String, String>>() ?? []);
      wantCourses.addAll((special["want"] as List?)?.cast<Map<String, String>>() ?? []);
      deletedCourses.addAll((data["deletedCourses"] as List?)?.cast<String>() ?? []);
    });
  }

  Future<void> _fetchUserData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("User not logged in");

      final doc = await FirebaseFirestore.instance.collection("users").doc(uid).get();
      if (!doc.exists) throw Exception("User not found");

      final data = doc.data()!;
      userMajor = _extractValue(data["major"]);
      userGender = _extractValue(data["gender"]);
      userLevel = _extractIntValue(data["level"]);

      await _fetchGroups();
    } catch (e) {
      _showMsg("Error loading user info: $e", true);
    } finally {
      setState(() => _loadingUser = false);
    }
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
  bool _isValidSection(String section) => RegExp(r'^[0-9]{4,7}$').hasMatch(section); // ✅ 4–7 digits

  void _addHaveCourse() {
    final code = haveCourseCodeController.text.trim().toUpperCase();
    final section = haveSectionController.text.trim();
    if (!_isValidCourseCode(code)) return _showMsg("Invalid course code (e.g., CSC111)", true);
    if (!_isValidSection(section)) return _showMsg("Section must be 4–7 digits", true);
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
    if (!_isValidSection(section)) return _showMsg("Section must be 4–7 digits", true);
    setState(() {
      wantCourses.add({"course": code, "section": section, "priority": priority});
      wantCourseCodeController.clear();
      wantSectionController.clear();
      priority = "Must";
    });
  }

  void _addDeletedCourse() {
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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final data = {
        "userId": uid,
        "major": userMajor,
        "gender": userGender,
        "level": userLevel,
        "fromGroup": int.parse(fromGroup!),
        "toGroup": int.parse(toGroup!),
        "specialRequests": {"have": haveCourses, "want": wantCourses},
        "deletedCourses": deletedCourses,
        "status": "open",
        "createdAt": FieldValue.serverTimestamp(),
      };

      String requestId;
      if (widget.existingRequestId != null) {
        await FirebaseFirestore.instance
            .collection("swap_requests")
            .doc(widget.existingRequestId)
            .update(data);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
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
          bottom: false,
          child: _loadingUser
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🔹 Back Button
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const HomePage()),
                        ),
                      ),

                      const Text(
                        "Swapping Request",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 25),

                      // ✅ Main white card
                      Card(
                        color: Colors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
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
                                  "Deleted Completed Courses",
                                  Colors.redAccent,
                                  showDelete,
                                  () => setState(() => showDelete = !showDelete),
                                  _buildDeleteSection(),
                                ),
                                const SizedBox(height: 30),
                                _buildSubmitButton(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
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
            availableGroups
                .where((g) => fromGroup == null || g.toString() != fromGroup)
                .toList(),
            (val) => setState(() => toGroup = val),
          ),
        ],
      );

  Widget _buildDropdown(String label, String? value, List<int> items,
          void Function(String?) onChanged) =>
      DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items
            .map((num) => DropdownMenuItem(value: num.toString(), child: Text("Group $num")))
            .toList(),
        validator: (v) => v == null ? "Required" : null,
        onChanged: onChanged,
      );

  Widget _buildExpandableSection(String title, Color color, bool expanded,
      VoidCallback onToggle, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 16)),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, color: color),
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 10),
          content,
        ],
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0097B2),
              foregroundColor: Colors.white,
            ),
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
            decoration: const InputDecoration(
              labelText: "Priority",
              border: OutlineInputBorder(),
            ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E0259),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _buildList(wantCourses),
        ],
      );

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
            onPressed: _addDeletedCourse,
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text("Delete Course"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _buildDeletedList(),
        ],
      );

  Widget _buildCourseInput(
          TextEditingController codeCtrl, TextEditingController sectionCtrl) =>
      Column(children: [
        TextFormField(
          controller: codeCtrl,
          decoration: const InputDecoration(
            labelText: "Course Code (e.g., CSC111)",
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: sectionCtrl,
          decoration: const InputDecoration(
            labelText: "Section Number (4–7 digits)",
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
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
                title: Text("${c["course"]} — Section ${c["section"]}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => list.removeAt(i)),
                ),
              ),
            );
          }).toList(),
        );

  Widget _buildDeletedList() => deletedCourses.isEmpty
      ? const Text("No deleted courses yet.")
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
}