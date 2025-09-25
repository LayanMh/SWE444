import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SwapRequestPage extends StatefulWidget {
  const SwapRequestPage({super.key});

  @override
  State<SwapRequestPage> createState() => _SwapRequestPageState();
}

class _SwapRequestPageState extends State<SwapRequestPage> {
  final _formKey = GlobalKey<FormState>();

  String? fromGroup;
  String? toGroup;

  final List<Map<String, String>> specialRequests = [];
  final TextEditingController courseCodeController = TextEditingController();
  String priority = "Must";

  String? userId; // will replace hardcoded uid
  String? major;  // will replace hardcoded major

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        // Extract 9-digit id from email before @
        final email = user.email!;
        final idPart = email.split('@').first;
        if (idPart.length == 9) {
          userId = idPart;
        }

        // Get major from Firestore
        final doc = await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .get();

        if (doc.exists && doc.data() != null) {
          major = doc["major"];
        }
      }
      setState(() {});
    } catch (e) {
      debugPrint("Error loading user data: $e");
    }
  }

  bool _validateCourseCode(String code) {
    final regex = RegExp(r'^[A-Z]{2,3}[0-9]{3}$');
    return regex.hasMatch(code);
  }

  void _addSpecialRequest() {
    if (_validateCourseCode(courseCodeController.text)) {
      setState(() {
        specialRequests.add({
          "code": courseCodeController.text,
          "priority": priority,
        });
        courseCodeController.clear();
        priority = "Must";
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Course code must look like CSC101"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _removeSpecialRequest(int index) {
    setState(() {
      specialRequests.removeAt(index);
    });
  }

  Future<void> _submitRequest() async {
    if (_formKey.currentState!.validate()) {
      if (userId == null || major == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("User data not loaded yet"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      try {
        await FirebaseFirestore.instance.collection("swap_requests").add({
          "userId": userId,      // ✅ dynamic from email
          "major": major,        // ✅ dynamic from Firestore
          "fromGroup": int.parse(fromGroup!),
          "toGroup": int.parse(toGroup!),
          "status": "open",
          "createdAt": FieldValue.serverTimestamp(),
          "specialRequests": specialRequests,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Swap request posted successfully"),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          fromGroup = null;
          toGroup = null;
          specialRequests.clear();
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: const Text("Swapping Request"),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: userId == null || major == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Group Info Card
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Group Information",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 15),
                              DropdownButtonFormField<String>(
                                value: fromGroup,
                                decoration: const InputDecoration(
                                  labelText: "From Group *",
                                  border: OutlineInputBorder(),
                                ),
                                items: List.generate(
                                  5,
                                  (i) => DropdownMenuItem(
                                    value: (i + 1).toString(),
                                    child: Text("Group ${i + 1}"),
                                  ),
                                ),
                                validator: (value) =>
                                    value == null ? "Required" : null,
                                onChanged: (val) =>
                                    setState(() => fromGroup = val),
                              ),
                              const SizedBox(height: 15),
                              DropdownButtonFormField<String>(
                                value: toGroup,
                                decoration: const InputDecoration(
                                  labelText: "To Group *",
                                  border: OutlineInputBorder(),
                                ),
                                items: List.generate(
                                  5,
                                  (i) => DropdownMenuItem(
                                    value: (i + 1).toString(),
                                    child: Text("Group ${i + 1}"),
                                  ),
                                ),
                                validator: (value) =>
                                    value == null ? "Required" : null,
                                onChanged: (val) =>
                                    setState(() => toGroup = val),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Special Requests Card
                      Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Special Requests",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 15),
                              TextFormField(
                                controller: courseCodeController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  labelText: "Course Code (e.g., CSC101)",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 15),
                              DropdownButtonFormField<String>(
                                value: priority,
                                decoration: const InputDecoration(
                                  labelText: "Priority",
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: "Must", child: Text("Must")),
                                  DropdownMenuItem(
                                      value: "Optional",
                                      child: Text("Optional")),
                                ],
                                onChanged: (val) =>
                                    setState(() => priority = val!),
                              ),
                              const SizedBox(height: 15),
                              ElevatedButton.icon(
                                onPressed: _addSpecialRequest,
                                icon: const Icon(Icons.add),
                                label: const Text("Add Course"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.tertiary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 15),
                              specialRequests.isEmpty
                                  ? const Text("No courses added")
                                  : Column(
                                      children: specialRequests
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                        final i = entry.key;
                                        final c = entry.value;
                                        return Card(
                                          child: ListTile(
                                            title: Text(c["code"]!),
                                            subtitle: Text(
                                                "Priority: ${c["priority"]}"),
                                            trailing: IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              onPressed: () =>
                                                  _removeSpecialRequest(i),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitRequest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.tertiary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "Submit Request",
                            style: TextStyle(fontSize: 16),
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
