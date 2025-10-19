import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ExperiencePage extends StatefulWidget {
  const ExperiencePage({super.key});

  @override
  State<ExperiencePage> createState() => _ExperiencePageState();
}

class _ExperiencePageState extends State<ExperiencePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool isLoading = true;
  Map<String, dynamic> experienceData = {
    'projects': [],
    'workshops': [],
    'clubs': [],
    'volunteering': [],
  };

  @override
  void initState() {
    super.initState();
    _loadExperienceData();
  }

  Future<String?> _getUserDocId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    
    if (microsoftDocId != null) {
      return microsoftDocId;
    } else if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    return null;
  }

  Future<void> _loadExperienceData() async {
    try {
      setState(() => isLoading = true);
      
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      final doc = await _firestore.collection('users').doc(docId).get();
      
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          experienceData = {
            'projects': data?['projects'] ?? [],
            'workshops': data?['workshops'] ?? [],
            'clubs': data?['clubs'] ?? [],
            'volunteering': data?['volunteering'] ?? [],
          };
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading experience: $e');
      _showErrorMessage('Failed to load experience data');
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteItem(String category, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final docId = await _getUserDocId();
      if (docId == null) return;

      List<dynamic> items = List.from(experienceData[category]);
      
      // Delete associated files from Storage if they exist
      final item = items[index];
      if (item['certificateUrl'] != null) {
        try {
          await FirebaseStorage.instance.refFromURL(item['certificateUrl']).delete();
        } catch (e) {
          debugPrint('Error deleting certificate: $e');
        }
      }
      
      items.removeAt(index);

      await _firestore.collection('users').doc(docId).update({
        category: items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSuccessMessage('Deleted successfully');
      await _loadExperienceData();
    } catch (e) {
      _showErrorMessage('Failed to delete item');
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4ECDC4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCategorySection({
  required String title,
  required IconData icon,
  required String category,
  required List<dynamic> items,
}) {
  final displayItems = items.length > 2 ? items.sublist(0, 2) : items;
  final hasMore = items.length > 2;

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16.0),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.1),
          spreadRadius: 1,
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0097b2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Icon(icon, color: const Color(0xFF0097b2), size: 24.0),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0e0259),
                  ),
                ),
              ),
              InkWell(
                onTap: () async {
                  Widget formPage;
                  switch (category) {
                    case 'projects':
                      formPage = ProjectFormPage();
                      break;
                    case 'workshops':
                      formPage = WorkshopFormPage();
                      break;
                    case 'clubs':
                      formPage = ClubFormPage();
                      break;
                    case 'volunteering':
                      formPage = VolunteeringFormPage();
                      break;
                    default:
                      return;
                  }
                  
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => formPage),
                  );
                  if (result == true) {
                    await _loadExperienceData();
                  }
                },
                borderRadius: BorderRadius.circular(12.0),
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECDC4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Color(0xFF0097b2),
                    size: 24.0,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
            child: Text(
              'No $title added yet. Tap + to add.',
              style: TextStyle(
                fontSize: 14.0,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final item = displayItems[index];
              return _buildExperienceItem(
                item: item,
                category: category,
                index: index,
              );
            },
          ),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CategoryDetailPage(
                        title: title,
                        icon: icon,
                        category: category,
                        items: items,
                        onUpdate: _loadExperienceData,
                        onDelete: _deleteItem,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0097b2).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: const Color(0xFF0097b2).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'See all ${items.length} items',
                        style: const TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0097b2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: Color(0xFF0097b2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

  Widget _buildExperienceItem({
    required Map<String, dynamic> item,
    required String category,
    required int index,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF95E1D3).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: const Color(0xFF95E1D3).withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] ?? 'Untitled',
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0e0259),
                  ),
                ),
                if (item['organization'] != null && item['organization'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      item['organization'],
                      style: TextStyle(
                        fontSize: 14.0,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (item['role'] != null && item['role'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Role: ${item['role']}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['hours'] != null && item['hours'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Hours: ${item['hours']}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['year'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Year: ${item['year']}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['startDate'] != null || item['endDate'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '${item['startDate'] ?? 'N/A'} - ${item['endDate'] ?? 'Present'}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['link'] != null && item['link'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item['link'],
                            style: TextStyle(
                              fontSize: 13.0,
                              color: const Color(0xFF0097b2),
                              decoration: TextDecoration.underline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (item['certificateUrl'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.verified, size: 16, color: Colors.green[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Certificate attached',
                          style: TextStyle(
                            fontSize: 13.0,
                            color: Colors.green[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (item['description'] != null && item['description'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      item['description'],
                      style: TextStyle(
                        fontSize: 14.0,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8.0),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20.0),
            onSelected: (value) async {
              if (value == 'edit') {
                Widget formPage;
                switch (category) {
                  case 'projects':
                    formPage = ProjectFormPage(existingItem: item, itemIndex: index);
                    break;
                  case 'workshops':
                    formPage = WorkshopFormPage(existingItem: item, itemIndex: index);
                    break;
                  case 'clubs':
                    formPage = ClubFormPage(existingItem: item, itemIndex: index);
                    break;
                  case 'volunteering':
                    formPage = VolunteeringFormPage(existingItem: item, itemIndex: index);
                    break;
                  default:
                    return;
                }
                
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => formPage),
                );
                if (result == true) {
                  await _loadExperienceData();
                }
              } else if (value == 'delete') {
                await _deleteItem(category, index);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Color(0xFF0097b2), size: 20),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Delete'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.grey[50],
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF006B7A),
            Color(0xFF0097b2),
            Color(0xFF0e0259),
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Experience',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadExperienceData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16.0, bottom: 80.0),
                            child: Column(
                              children: [
                                _buildCategorySection(
                                  title: 'Projects',
                                  icon: Icons.work_outline,
                                  category: 'projects',
                                  items: experienceData['projects'],
                                ),
                                _buildCategorySection(
                                  title: 'Workshops',
                                  icon: Icons.school_outlined,
                                  category: 'workshops',
                                  items: experienceData['workshops'],
                                ),
                                _buildCategorySection(
                                  title: 'Student Clubs',
                                  icon: Icons.groups_outlined,
                                  category: 'clubs',
                                  items: experienceData['clubs'],
                                ),
                                _buildCategorySection(
                                  title: 'Volunteering',
                                  icon: Icons.volunteer_activism_outlined,
                                  category: 'volunteering',
                                  items: experienceData['volunteering'],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () {
        // TODO: Implement CV generation
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CV generation coming soon!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      backgroundColor: const Color(0xFF0097b2),
      icon: const Icon(Icons.description, color: Colors.white),
      label: const Text(
        'Generate CV',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
}

class CategoryDetailPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final String category;
  final List<dynamic> items;
  final Function onUpdate;
  final Function(String, int) onDelete;

  const CategoryDetailPage({
    super.key,
    required this.title,
    required this.icon,
    required this.category,
    required this.items,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF006B7A),
              Color(0xFF0097b2),
              Color(0xFF0e0259),
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20.0),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildDetailItem(context, item, index);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(BuildContext context, Map<String, dynamic> item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'] ?? 'Untitled',
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0e0259),
                  ),
                ),
                if (item['organization'] != null && item['organization'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      item['organization'],
                      style: TextStyle(
                        fontSize: 14.0,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (item['role'] != null && item['role'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Role: ${item['role']}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['hours'] != null && item['hours'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Hours: ${item['hours']}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['year'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      'Year: ${item['year']}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['startDate'] != null || item['endDate'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '${item['startDate'] ?? 'N/A'} - ${item['endDate'] ?? 'Present'}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (item['link'] != null && item['link'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        Icon(Icons.link, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item['link'],
                            style: const TextStyle(
                              fontSize: 13.0,
                              color: Color(0xFF0097b2),
                              decoration: TextDecoration.underline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (item['certificateUrl'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.verified, size: 16, color: Colors.green[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Certificate attached',
                          style: TextStyle(
                            fontSize: 13.0,
                            color: Colors.green[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (item['description'] != null && item['description'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      item['description'],
                      style: TextStyle(
                        fontSize: 14.0,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8.0),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20.0),
            onSelected: (value) async {
              if (value == 'edit') {
                Widget formPage;
                switch (category) {
                  case 'projects':
                    formPage = ProjectFormPage(existingItem: item, itemIndex: index);
                    break;
                  case 'workshops':
                    formPage = WorkshopFormPage(existingItem: item, itemIndex: index);
                    break;
                  case 'clubs':
                    formPage = ClubFormPage(existingItem: item, itemIndex: index);
                    break;
                  case 'volunteering':
                    formPage = VolunteeringFormPage(existingItem: item, itemIndex: index);
                    break;
                  default:
                    return;
                }
                
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => formPage),
                );
                if (result == true) {
                  await onUpdate();
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              } else if (value == 'delete') {
                await onDelete(category, index);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Color(0xFF0097b2), size: 20),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Delete'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===================== PROJECT FORM =====================
class ProjectFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const ProjectFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends State<ProjectFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _linkController;
  late TextEditingController _descriptionController;
  
  String? _startMonth;
  int? _startYear;
  String? _endMonth;
  int? _endYear;
  bool _isCurrentlyActive = false;
  bool _isSaving = false;

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _linkController = TextEditingController(text: widget.existingItem?['link'] ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _isCurrentlyActive = widget.existingItem?['isCurrentlyActive'] ?? false;
    
    if (widget.existingItem?['startDate'] != null) {
      final parts = widget.existingItem!['startDate'].split(' ');
      if (parts.length == 2) {
        _startMonth = parts[0];
        _startYear = int.tryParse(parts[1]);
      }
    }
    
    if (widget.existingItem?['endDate'] != null && widget.existingItem!['endDate'] != 'Present') {
      final parts = widget.existingItem!['endDate'].split(' ');
      if (parts.length == 2) {
        _endMonth = parts[0];
        _endYear = int.tryParse(parts[1]);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
    _linkController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<String?> _getUserDocId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    
    if (microsoftDocId != null) {
      return microsoftDocId;
    } else if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    return null;
  }

  Future<void> _saveProject() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      final projectItem = {
        'title': _titleController.text.trim(),
        'organization': _organizationController.text.trim(),
        'link': _linkController.text.trim(),
        'startDate': _startMonth != null && _startYear != null ? '$_startMonth $_startYear' : null,
        'endDate': _isCurrentlyActive ? 'Present' : (_endMonth != null && _endYear != null ? '$_endMonth $_endYear' : null),
        'description': _descriptionController.text.trim(),
        'isCurrentlyActive': _isCurrentlyActive,
      };

      final doc = await _firestore.collection('users').doc(docId).get();
      List<dynamic> items = doc.data()?['projects'] ?? [];

      if (widget.existingItem != null && widget.itemIndex != null) {
        items[widget.itemIndex!] = projectItem;
      } else {
        items.add(projectItem);
      }

      await _firestore.collection('users').doc(docId).update({
        'projects': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving project: $e');
      _showErrorMessage('Failed to save project');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF006B7A), Color(0xFF0097b2), Color(0xFF0e0259)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.existingItem != null ? 'Edit Project' : 'Add Project',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextField(
                              controller: _titleController,
                              label: 'Project Title *',
                              hint: 'e.g., AI Research Project',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a project title';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _organizationController,
                              label: 'Organization',
                              hint: 'e.g., Google Developer Student Club',
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _linkController,
                              label: 'Link/Attachment',
                              hint: 'e.g., https://github.com/yourproject',
                            ),
                            const SizedBox(height: 16.0),
                            _buildDatePicker(
                              label: 'Start Date',
                              selectedMonth: _startMonth,
                              selectedYear: _startYear,
                              onMonthChanged: (month) => setState(() => _startMonth = month),
                              onYearChanged: (year) => setState(() => _startYear = year),
                            ),
                            const SizedBox(height: 16.0),
                            CheckboxListTile(
                              title: const Text('Currently working on this'),
                              value: _isCurrentlyActive,
                              onChanged: (value) {
                                setState(() {
                                  _isCurrentlyActive = value ?? false;
                                  if (_isCurrentlyActive) {
                                    _endMonth = null;
                                    _endYear = null;
                                  }
                                });
                              },
                              activeColor: const Color(0xFF0097b2),
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (!_isCurrentlyActive)
                              _buildDatePicker(
                                label: 'End Date',
                                selectedMonth: _endMonth,
                                selectedYear: _endYear,
                                onMonthChanged: (month) => setState(() => _endMonth = month),
                                onYearChanged: (year) => setState(() => _endYear = year),
                              ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'Describe your project...',
                              maxLines: 5,
                            ),
                            const SizedBox(height: 24.0),
                            _buildSaveButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required String? selectedMonth,
    required int? selectedYear,
    required Function(String?) onMonthChanged,
    required Function(int?) onYearChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: selectedMonth,
                decoration: _inputDecoration('Month'),
                items: _months.map((month) {
                  return DropdownMenuItem(value: month, child: Text(month));
                }).toList(),
                onChanged: onMonthChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: selectedYear,
                decoration: _inputDecoration('Year'),
                items: List.generate(26, (index) => 2025 - index).map((year) {
                  return DropdownMenuItem(value: year, child: Text('$year'));
                }).toList(),
                onChanged: onYearChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0097b2), Color(0xFF006B7A)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0097b2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveProject,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

// ===================== WORKSHOP FORM =====================
class WorkshopFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const WorkshopFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<WorkshopFormPage> createState() => _WorkshopFormPageState();
}

class _WorkshopFormPageState extends State<WorkshopFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  
  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _yearController;
  late TextEditingController _descriptionController;
  
  File? _certificateFile;
  String? _existingCertificateUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _yearController = TextEditingController(text: widget.existingItem?['year']?.toString() ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _existingCertificateUrl = widget.existingItem?['certificateUrl'];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
    _yearController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<String?> _getUserDocId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    
    if (microsoftDocId != null) {
      return microsoftDocId;
    } else if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    return null;
  }

  Future<void> _pickCertificate() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _certificateFile = File(image.path);
        });
      }
    } catch (e) {
      _showErrorMessage('Failed to pick image');
    }
  }

  Future<String?> _uploadCertificate(String userId) async {
    if (_certificateFile == null) return _existingCertificateUrl;

    try {
      final String fileName = 'workshops/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = _storage.ref().child(fileName);
      await ref.putFile(_certificateFile!);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading certificate: $e');
      return null;
    }
  }

  Future<void> _saveWorkshop() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      String? certificateUrl = await _uploadCertificate(docId);

      final workshopItem = {
        'title': _titleController.text.trim(),
        'organization': _organizationController.text.trim(),
        'year': int.tryParse(_yearController.text.trim()),
        'description': _descriptionController.text.trim(),
        'certificateUrl': certificateUrl,
      };

      final doc = await _firestore.collection('users').doc(docId).get();
      List<dynamic> items = doc.data()?['workshops'] ?? [];

      if (widget.existingItem != null && widget.itemIndex != null) {
        items[widget.itemIndex!] = workshopItem;
      } else {
        items.add(workshopItem);
      }

      await _firestore.collection('users').doc(docId).update({
        'workshops': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving workshop: $e');
      _showErrorMessage('Failed to save workshop');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF006B7A), Color(0xFF0097b2), Color(0xFF0e0259)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.existingItem != null ? 'Edit Workshop' : 'Add Workshop',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextField(
                              controller: _titleController,
                              label: 'Workshop Title *',
                              hint: 'e.g., Machine Learning Workshop',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a workshop title';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _organizationController,
                              label: 'Organization',
                              hint: 'e.g., IEEE Student Branch',
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _yearController,
                              label: 'Year *',
                              hint: 'e.g., 2024',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a year';
                                }
                                final year = int.tryParse(value.trim());
                                if (year == null || year < 2000 || year > 2025) {
                                  return 'Please enter a valid year (2000-2025)';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'What did you learn?',
                              maxLines: 5,
                            ),
                            const SizedBox(height: 16.0),
                            _buildCertificatePicker(),
                            const SizedBox(height: 24.0),
                            _buildSaveButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCertificatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Certificate',
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        InkWell(
          onTap: _pickCertificate,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file, color: const Color(0xFF0097b2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _certificateFile != null
                        ? 'Certificate selected'
                        : _existingCertificateUrl != null
                            ? 'Certificate uploaded (tap to change)'
                            : 'Tap to upload certificate',
                    style: TextStyle(
                      color: _certificateFile != null || _existingCertificateUrl != null
                          ? const Color(0xFF0097b2)
                          : Colors.grey[600],
                    ),
                  ),
                ),
                if (_certificateFile != null || _existingCertificateUrl != null)
                  Icon(Icons.check_circle, color: Colors.green[600]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0097b2), Color(0xFF006B7A)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0097b2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveWorkshop,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

// ===================== CLUB FORM =====================
class ClubFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const ClubFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<ClubFormPage> createState() => _ClubFormPageState();
}

class _ClubFormPageState extends State<ClubFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  File? _certificateFile;
  String? _existingCertificateUrl;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  
  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _roleController;
  late TextEditingController _hoursController;
  late TextEditingController _descriptionController;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _roleController = TextEditingController(text: widget.existingItem?['role'] ?? '');
    _hoursController = TextEditingController(text: widget.existingItem?['hours']?.toString() ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _existingCertificateUrl = widget.existingItem?['certificateUrl'];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
    _roleController.dispose();
    _hoursController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<String?> _getUserDocId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    
    if (microsoftDocId != null) {
      return microsoftDocId;
    } else if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    return null;
  }

  Future<void> _pickCertificate() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _certificateFile = File(image.path);
        });
      }
    } catch (e) {
      _showErrorMessage('Failed to pick image');
    }
  }

  Future<String?> _uploadCertificate(String userId) async {
    if (_certificateFile == null) return _existingCertificateUrl;

    try {
      final String fileName = 'clubs/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = _storage.ref().child(fileName);
      await ref.putFile(_certificateFile!);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading certificate: $e');
      return null;
    }
  }

  Future<void> _saveClub() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _isSaving = true);

  try {
    final docId = await _getUserDocId();
    if (docId == null) {
      _showErrorMessage('Unable to identify user');
      return;
    }

    String? certificateUrl = await _uploadCertificate(docId);

    final clubItem = {
      'title': _titleController.text.trim(),
      'organization': _organizationController.text.trim(),
      'role': _roleController.text.trim(),
      'hours': int.tryParse(_hoursController.text.trim()),
      'description': _descriptionController.text.trim(),
      'certificateUrl': certificateUrl,
    };

    final doc = await _firestore.collection('users').doc(docId).get();
    List<dynamic> items = doc.data()?['clubs'] ?? [];

    if (widget.existingItem != null && widget.itemIndex != null) {
      items[widget.itemIndex!] = clubItem;
    } else {
      items.add(clubItem);
    }

    await _firestore.collection('users').doc(docId).update({
      'clubs': items,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      Navigator.pop(context, true);
    }
  } catch (e) {
    debugPrint('Error saving club: $e');
    _showErrorMessage('Failed to save club');
  } finally {
    setState(() => _isSaving = false);
  }
}

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCertificatePicker() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Certificate (Optional)',
        style: TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0e0259),
        ),
      ),
      const SizedBox(height: 8.0),
      InkWell(
        onTap: _pickCertificate,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(Icons.upload_file, color: const Color(0xFF0097b2)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _certificateFile != null
                      ? 'Certificate selected'
                      : _existingCertificateUrl != null
                          ? 'Certificate uploaded (tap to change)'
                          : 'Tap to upload certificate',
                  style: TextStyle(
                    color: _certificateFile != null || _existingCertificateUrl != null
                        ? const Color(0xFF0097b2)
                        : Colors.grey[600],
                  ),
                ),
              ),
              if (_certificateFile != null || _existingCertificateUrl != null)
                Icon(Icons.check_circle, color: Colors.green[600]),
            ],
          ),
        ),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF006B7A), Color(0xFF0097b2), Color(0xFF0e0259)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.existingItem != null ? 'Edit Club' : 'Add Club',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextField(
                              controller: _titleController,
                              label: 'Club Name *',
                              hint: 'e.g., Robotics Club',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a club name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _organizationController,
                              label: 'Organization',
                              hint: 'e.g., University Engineering Department',
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _roleController,
                              label: 'Role *',
                              hint: 'e.g., President, Member, Volunteer',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your role';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _hoursController,
                              label: 'Participation Hours',
                              hint: 'e.g., 50',
                              validator: (value) {
                                if (value != null && value.trim().isNotEmpty) {
                                  final hours = int.tryParse(value.trim());
                                  if (hours == null || hours < 0) {
                                    return 'Please enter valid hours';
                                  }
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildCertificatePicker(),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'Describe your activities and contributions...',
                              maxLines: 5,
                            ),
                            const SizedBox(height: 24.0),
                            _buildSaveButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          keyboardType: label.contains('Hours') ? TextInputType.number : TextInputType.text,
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0097b2), Color(0xFF006B7A)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0097b2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveClub,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

// ===================== VOLUNTEERING FORM =====================
class VolunteeringFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const VolunteeringFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<VolunteeringFormPage> createState() => _VolunteeringFormPageState();
}

class _VolunteeringFormPageState extends State<VolunteeringFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  
  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _hoursController;
  late TextEditingController _descriptionController;
  
  File? _certificateFile;
  String? _existingCertificateUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _hoursController = TextEditingController(text: widget.existingItem?['hours']?.toString() ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _existingCertificateUrl = widget.existingItem?['certificateUrl'];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
    _hoursController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<String?> _getUserDocId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    
    if (microsoftDocId != null) {
      return microsoftDocId;
    } else if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    return null;
  }

  Future<void> _pickCertificate() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _certificateFile = File(image.path);
        });
      }
    } catch (e) {
      _showErrorMessage('Failed to pick image');
    }
  }

  Future<String?> _uploadCertificate(String userId) async {
    if (_certificateFile == null) return _existingCertificateUrl;

    try {
      final String fileName = 'volunteering/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = _storage.ref().child(fileName);
      await ref.putFile(_certificateFile!);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading certificate: $e');
      return null;
    }
  }

  Future<void> _saveVolunteering() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      String? certificateUrl = await _uploadCertificate(docId);

      final volunteeringItem = {
        'title': _titleController.text.trim(),
        'organization': _organizationController.text.trim(),
        'hours': int.tryParse(_hoursController.text.trim()),
        'description': _descriptionController.text.trim(),
        'certificateUrl': certificateUrl,
      };

      final doc = await _firestore.collection('users').doc(docId).get();
      List<dynamic> items = doc.data()?['volunteering'] ?? [];

      if (widget.existingItem != null && widget.itemIndex != null) {
        items[widget.itemIndex!] = volunteeringItem;
      } else {
        items.add(volunteeringItem);
      }

      await _firestore.collection('users').doc(docId).update({
        'volunteering': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving volunteering: $e');
      _showErrorMessage('Failed to save volunteering');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF006B7A), Color(0xFF0097b2), Color(0xFF0e0259)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.existingItem != null ? 'Edit Volunteering' : 'Add Volunteering',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextField(
                              controller: _titleController,
                              label: 'Title *',
                              hint: 'e.g., Community Cleanup Volunteer',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a title';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _organizationController,
                              label: 'Organization',
                              hint: 'e.g., Red Crescent Society',
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _hoursController,
                              label: 'Hours *',
                              hint: 'e.g., 25',
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter hours';
                                }
                                final hours = int.tryParse(value.trim());
                                if (hours == null || hours < 0) {
                                  return 'Please enter valid hours';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'Describe your volunteering activities...',
                              maxLines: 5,
                            ),
                            const SizedBox(height: 16.0),
                            _buildCertificatePicker(),
                            const SizedBox(height: 24.0),
                            _buildSaveButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCertificatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Certificate',
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        InkWell(
          onTap: _pickCertificate,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file, color: const Color(0xFF0097b2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _certificateFile != null
                        ? 'Certificate selected'
                        : _existingCertificateUrl != null
                            ? 'Certificate uploaded (tap to change)'
                            : 'Tap to upload certificate',
                    style: TextStyle(
                      color: _certificateFile != null || _existingCertificateUrl != null
                          ? const Color(0xFF0097b2)
                          : Colors.grey[600],
                    ),
                  ),
                ),
                if (_certificateFile != null || _existingCertificateUrl != null)
                  Icon(Icons.check_circle, color: Colors.green[600]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          keyboardType: label.contains('Hours') ? TextInputType.number : TextInputType.text,
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0097b2), Color(0xFF006B7A)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0097b2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveVolunteering,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}

