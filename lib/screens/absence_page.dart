// lib/screens/absence_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import 'package:firebase_auth/firebase_auth.dart';


Stream<QuerySnapshot<Map<String, dynamic>>> streamMyAbsences() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    // If not signed in, return an empty stream
    return const Stream.empty();
  }

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('absences')
      .orderBy('start', descending: true) // newest first
      .snapshots();
}


class AbsencePage extends StatelessWidget {
  const AbsencePage({super.key});

  String _formatRange(String startIso, String endIso) {
    final s = DateTime.tryParse(startIso)?.toLocal();
    final e = DateTime.tryParse(endIso)?.toLocal();
    if (s == null) return '';
    final f = DateFormat('EEE, MMM d • hh:mm a');
    if (e == null) return f.format(s);
    return '${f.format(s)} – ${DateFormat('hh:mm a').format(e)}';
  }

  Color _statusBg(String status, BuildContext ctx) {
    switch (status) {
      case 'absent': return Colors.red.withOpacity(0.12);
      case 'cancelled': return Colors.orange.withOpacity(0.12);
      default: return Theme.of(ctx).colorScheme.surfaceVariant.withOpacity(0.4);
    }
  }

  @override
 Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Absences")),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: streamMyAbsences(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text("No absences recorded."));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final title = data['title'] ?? "Unknown class";
              final status = data['status'] ?? "unknown";
              final start = (data['start'] as Timestamp?)?.toDate();
              final formattedDate =
                  start != null ? DateFormat("MMM d, yyyy – hh:mm a").format(start) : "No date";

              return ListTile(
                leading: Icon(
                  status == 'absent'
                      ? Icons.close
                      : status == 'cancelled'
                          ? Icons.cancel
                          : Icons.check,
                  color: status == 'absent'
                      ? Colors.red
                      : status == 'cancelled'
                          ? Colors.orange
                          : Colors.green,
                ),
                title: Text(title),
                subtitle: Text("$status • $formattedDate"),
              );
            },
          );
        },
      ),
    );
  }
}
