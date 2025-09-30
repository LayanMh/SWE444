import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart'; // For FilteringTextInputFormatter

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GPA Calculator"),
        backgroundColor: const Color(0xFF0097B2),
      ),
      body: currentGpa == null
          ? const Center(child: CircularProgressIndicator()) // still loading
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Current Info Card ---
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Your Info",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0097B2))),
                              const SizedBox(height: 12),
                              Text(
                                "Current GPA: ${currentGpa!.toStringAsFixed(2)} / 5.0",
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: creditsController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                decoration: const InputDecoration(
                                  labelText: "Completed Credits",
                                  border: OutlineInputBorder(),
                                ),
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return "Completed credits are required";
                                  }
                                  final num? parsed = int.tryParse(val);
                                  if (parsed == null) {
                                    return "Please enter a valid number";
                                  }
                                  if (parsed < 0|| parsed > 300) {
                                    return "Completed credits must be between 0 and 300";
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- Add Courses Card ---
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Add Courses",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0097B2))),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: addCourse,
                                icon: const Icon(Icons.add),
                                label: const Text("Add Course"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0097B2),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: courses.length,
                                itemBuilder: (_, i) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller:
                                            courses[i].creditController,
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
                                          final num? parsed =
                                              int.tryParse(val);
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
                                              value: g, child: Text(g)))
                                          .toList(),
                                      onChanged: (v) => setState(() =>
                                          courses[i].selectedGrade = v!),
                                    ),
                                    IconButton(
                                      onPressed: () => removeCourse(i),
                                      icon: const Icon(Icons.remove_circle,
                                          color: Colors.red),
                                    ),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- Calculate Button ---
                      Center(
                        child: ElevatedButton(
                          onPressed: calculateGpa,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0097B2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 40, vertical: 12),
                          ),
                          child: const Text("Calculate GPA",
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- Expected GPA Result ---
                      if (expectedGpa != null)
                        Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                "Expected GPA: ${expectedGpa!.toStringAsFixed(2)} / 5.0",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0097B2),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class CourseInput {
  final TextEditingController creditController;
  String selectedGrade;
  CourseInput({required this.creditController, required this.selectedGrade});
}