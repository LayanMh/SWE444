import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // Design colors matching profile page
  static const Color kBg = Color(0xFFE6F3FF);
  static const Color kTopBar = Color(0xFF0D4F94);
  
  final _formKey = GlobalKey<FormState>();

  String? fromGroup;
  String? toGroup;
  String? userMajor;
  String? userGender;
  int? userLevel;
  String? userId;
  String? studentName;
  String? studentEmail;

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

  bool showHave = false;
  bool showWant = false;
  bool showDelete = false;
  bool _addingHaveCourse = false;
  bool _addingWantCourse = false;

  int _selectedIndex = 2;

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
      userId = await _getUserId();
      if (userId == null) throw Exception("User not logged in");

      final doc = await FirebaseFirestore.instance.collection("users").doc(userId).get();
      if (!doc.exists) throw Exception("User not found");

      final data = doc.data()!;
      userMajor = _extractValue(data["major"]);
      userGender = _extractValue(data["gender"]);
      userLevel = _extractIntValue(data["level"]);
      
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
  bool _isValidSection(String section) => RegExp(r'^[0-9]{5}$').hasMatch(section);

  void _addHaveCourse() {
    final code = haveCourseCodeController.text.trim().toUpperCase();
    final section = haveSectionController.text.trim();
    if (!_isValidCourseCode(code)) return _showMsg("Invalid course code (e.g., CSC111)", true);
    if (!_isValidSection(section)) return _showMsg("Section must be exactly 5 digits", true);
    setState(() {
      haveCourses.add({"course": code, "section": section});
      _addingHaveCourse = false;
    });
    haveCourseCodeController.clear();
    haveSectionController.clear();
  }

  void _addWantCourse() {
    final code = wantCourseCodeController.text.trim().toUpperCase();
    final section = wantSectionController.text.trim();
    if (!_isValidCourseCode(code)) return _showMsg("Invalid course code (e.g., SWE486)", true);
    if (!_isValidSection(section)) return _showMsg("Section must be exactly 5 digits", true);
    setState(() {
      wantCourses.add({"course": code, "section": section, "priority": priority});
      _addingWantCourse = false;
      priority = "Must";
    });
    wantCourseCodeController.clear();
    wantSectionController.clear();
  }

  void _startHaveCourseEntry() {
    setState(() {
      _addingHaveCourse = true;
    });
    haveCourseCodeController.clear();
    haveSectionController.clear();
  }

  void _cancelHaveCourseEntry() {
    setState(() {
      _addingHaveCourse = false;
    });
    haveCourseCodeController.clear();
    haveSectionController.clear();
  }

  void _startWantCourseEntry() {
    setState(() {
      _addingWantCourse = true;
      priority = "Must";
    });
    wantCourseCodeController.clear();
    wantSectionController.clear();
  }

  void _cancelWantCourseEntry() {
    setState(() {
      _addingWantCourse = false;
      priority = "Must";
    });
    wantCourseCodeController.clear();
    wantSectionController.clear();
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
      final data = {
        "userId": userId,
        "studentName": studentName,
        "studentEmail": studentEmail,
        "major": userMajor,
        "gender": userGender,
        "level": userLevel,
        "fromGroup": int.parse(fromGroup!),
        "toGroup": int.parse(toGroup!),
        "specialRequests": {"have": haveCourses, "want": wantCourses},
        "deletedCourses": deletedCourses,
        "status": "open",
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
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

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
    );
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
                    onPressed: () {
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
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Swapping Request',
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
              child: _loadingUser
                  ? Center(child: CircularProgressIndicator(color: kTopBar))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                    _buildSectionTitle("Group Information", kTopBar),
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
                                      kTopBar,
                                      showWant,
                                      () => setState(() => showWant = !showWant),
                                      _buildWantSection(),
                                    ),
                                    const SizedBox(height: 10),

                                    _buildExpandableSection(
                                      "Completed Main Courses",
                                      Colors.green,
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
                        ],
                      ),
                    ),
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
          if (_addingHaveCourse) ...[
            _buildCourseInput(haveCourseCodeController, haveSectionController),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addHaveCourse,
                    icon: const Icon(Icons.check),
                    label: const Text("Save Course"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0097B2),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelHaveCourseEntry,
                    child: const Text("Cancel"),
                  ),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _startHaveCourseEntry,
                icon: const Icon(Icons.add),
                label: const Text("Add Course"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0097B2),
                  side: const BorderSide(color: Color(0xFF0097B2), width: 1.5),
                ),
              ),
            ),
          const SizedBox(height: 10),
          _buildList(haveCourses),
        ],
      );

  Widget _buildWantSection() => Column(
        children: [
          if (_addingWantCourse) ...[
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addWantCourse,
                    icon: const Icon(Icons.check),
                    label: const Text("Save Course"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kTopBar,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelWantCourseEntry,
                    child: const Text("Cancel"),
                  ),
                ),
              ],
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _startWantCourseEntry,
                icon: const Icon(Icons.add),
                label: const Text("Add Course"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kTopBar,
                  side: BorderSide(color: kTopBar, width: 1.5),
                ),
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
            icon: const Icon(Icons.check_circle_outline),
            label: const Text("Add Completed Course"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _buildDeletedList(),
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
            labelText: "Section Number (5 digits)",
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          maxLength: 5,
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

  Widget _buildDeletedList() => deletedCourses.isEmpty
      ? const Text("No completed courses added yet.")
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
            backgroundColor: kTopBar,
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
    deletedCourseController.dispose();
    super.dispose();
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