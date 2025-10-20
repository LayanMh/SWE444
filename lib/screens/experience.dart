import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';

// Import the form pages
import 'projects_page.dart';
import 'workshops_page.dart';
import 'clubs_page.dart';
import 'volunteering_page.dart';

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
                        formPage = const ProjectFormPage();
                        break;
                      case 'workshops':
                        formPage = const WorkshopFormPage();
                        break;
                      case 'clubs':
                        formPage = const ClubFormPage();
                        break;
                      case 'volunteering':
                        formPage = const VolunteeringFormPage();
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