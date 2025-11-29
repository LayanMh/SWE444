import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // For FilteringTextInputFormatter

import 'home_page.dart';


class GpaCalculator extends StatefulWidget {
  const GpaCalculator({super.key});

  @override
  State<GpaCalculator> createState() => _GpaCalculatorState();
}

class _GpaCalculatorState extends State<GpaCalculator> {
  final _formKey = GlobalKey<FormState>();
  final creditsController = TextEditingController();
  final List<CourseInput> courses = [];
  double? expectedGpa;
  double? currentGpa;

  final Map<String, double> gradeValues = const {
    "A+": 5.0,
    "A": 4.75,
    "B+": 4.5,
    "B": 4.0,
    "C+": 3.5,
    "C": 3.0,
    "D+": 2.5,
    "D": 2.0,
    "F": 1.0,
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentGpa();
  }

  Future<void> _loadCurrentGpa() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final microsoftDocId = prefs.getString('microsoft_user_doc_id');

      DocumentSnapshot<Map<String, dynamic>>? doc;

      // Check if this is a Microsoft user
      if (microsoftDocId != null) {
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(microsoftDocId)
            .get();
      } else {
        // Regular Firebase Auth user
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          doc = await FirebaseFirestore.instance
              .collection("users")
              .doc(uid)
              .get();
        }
      }

      if (doc != null && doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey("GPA")) {
          setState(() {
            currentGpa = (data["GPA"] as num).toDouble();
          });
        } else {
          setState(() {
            currentGpa = 0.0;
          });
        }
      } else {
        setState(() {
          currentGpa = 0.0;
        });
      }
    } catch (e) {
      debugPrint("Error loading GPA: $e");
      setState(() => currentGpa = 0.0);
    }
  }

  void calculateGpa() {
    if (!_formKey.currentState!.validate()) return;

    final baseGpa = currentGpa ?? 0.0;
    final baseCredits = int.tryParse(creditsController.text.trim()) ?? 0;
    double totalPoints = baseGpa * baseCredits;
    int updatedCredits = baseCredits;

    for (final course in courses) {
      final credit = int.tryParse(course.creditController.text.trim()) ?? 0;
      final gradeValue = gradeValues[course.selectedGrade] ?? 0.0;
      totalPoints += credit * gradeValue;
      updatedCredits += credit;
    }

    setState(() {
      expectedGpa =
          updatedCredits > 0 ? totalPoints / updatedCredits : baseGpa;
    });
  }

  void addCourse() {
    setState(() {
      courses.add(CourseInput(
        creditController: TextEditingController(),
        selectedGrade: "A",
      ));
    });
  }

  void removeCourse(int index) => setState(() => courses.removeAt(index));

  void _onNavTap(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color kBg = Color(0xFFE6F3FF);
    const Color kTopBar = Color(0xFF0D4F94);
    const Color kCard = Colors.white;
    const Color kButton = Color(0xFF4A98E9);
    const double radius = 20;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: BoxDecoration(
                color: kTopBar,
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "GPA Calculator",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ],
              ),
            ),
            Expanded(
              child: currentGpa == null
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kCard,
                                borderRadius: BorderRadius.circular(radius),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Your Info",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: kTopBar,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Current GPA: ${currentGpa!.toStringAsFixed(2)} / 5.0",
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: kTopBar,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: creditsController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    decoration: InputDecoration(
                                      labelText: "Completed Credits",
                                      labelStyle: TextStyle(color: kTopBar),
                                      filled: true,
                                      fillColor: Colors.white,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: const BorderRadius.all(Radius.circular(14)),
                                        borderSide: BorderSide(color: kTopBar.withOpacity(0.4)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: const BorderRadius.all(Radius.circular(14)),
                                        borderSide: BorderSide(color: kTopBar, width: 1.4),
                                      ),
                                    ),
                                    validator: (val) {
                                      if (val == null || val.isEmpty) {
                                        return "Completed credits are required";
                                      }
                                      final num? parsed = int.tryParse(val);
                                      if (parsed == null) {
                                        return "Please enter a valid number";
                                      }
                                      if (parsed < 0 || parsed > 300) {
                                        return "Completed credits must be between 0 and 300";
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 26),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kCard,
                                borderRadius: BorderRadius.circular(radius),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Add Courses",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: kTopBar,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: addCourse,
                                    icon: const Icon(Icons.add),
                                    label: const Text("Add Course"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kButton,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 18,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: courses.length,
                                    itemBuilder: (_, i) => Container(
                                      margin: const EdgeInsets.symmetric(vertical: 6),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: kTopBar.withOpacity(0.12)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: courses[i].creditController,
                                              keyboardType: TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter.digitsOnly
                                              ],
                                              decoration: const InputDecoration(
                                                labelText: "Credit Hours",
                                                border: OutlineInputBorder(),
                                              ),
                                              validator: (val) {
                                                if (val == null || val.isEmpty) {
                                                  return "Credit hours are required";
                                                }
                                                final num? parsed = int.tryParse(val);
                                                if (parsed == null) {
                                                  return "Please enter a valid number";
                                                }
                                                if (parsed < 1 || parsed > 12) {
                                                  return "Enter a valid number";
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          DropdownButton<String>(
                                            value: courses[i].selectedGrade,
                                            items: gradeValues.keys
                                                .map((g) => DropdownMenuItem(
                                                      value: g,
                                                      child: Text(g),
                                                    ))
                                                .toList(),
                                            onChanged: (v) => setState(
                                              () => courses[i].selectedGrade = v!,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => removeCourse(i),
                                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 36),
                            Center(
                              child: ElevatedButton(
                                onPressed: calculateGpa,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kButton,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 40,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  elevation: 6,
                                ),
                                child: const Text(
                                  "Calculate GPA",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (expectedGpa != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: kCard,
                                  borderRadius: BorderRadius.circular(radius),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 6,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  "Expected GPA: ${expectedGpa!.toStringAsFixed(2)} / 5.0",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: kTopBar,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 2,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_rounded),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage('assets/images/logo.png')),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school_rounded),
            label: 'Experience',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_rounded),
            label: 'Community',
          ),
        ],
      ),
    );
  }
}

class CourseInput {
  final TextEditingController creditController;
  String selectedGrade;
  CourseInput({required this.creditController, required this.selectedGrade});
}
