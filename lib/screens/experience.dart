import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

// Import the form pages
import 'projects_page.dart';
import 'workshops_page.dart';
import 'clubs_page.dart';
import 'volunteering_page.dart';
import 'cv_page.dart';
import 'category_detail_page.dart';

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
  Set<String> expandedItems = {};

  @override
  void initState() {
    super.initState();
    _loadExperienceData();
  }

  String _getItemKey(String category, int index) {
    return '$category-$index';
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
      final docId = await _getUserDocId();
      if (docId == null) {
        if (isLoading && mounted) {
          setState(() => isLoading = false);
          _showErrorMessage('Unable to identify user');
        }
        return;
      }

      final doc = await _firestore.collection('users').doc(docId).get();
      
      if (doc.exists) {
        final data = doc.data();
        if (mounted) {
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
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading experience: $e');
      if (isLoading && mounted) {
        _showErrorMessage('Failed to load experience data');
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _deleteItem(String category, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete Item',
          style: TextStyle(
            color: Color(0xFF01509B),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
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
      
      final item = items[index];
      
      items.removeAt(index);
      if (mounted) {
        setState(() {
          experienceData[category] = items;
        });
      }

      await _firestore.collection('users').doc(docId).update({
        category: items,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      final certificateUrl = item['certificateUrl'];
      if (certificateUrl != null && 
          certificateUrl.toString().trim().isNotEmpty && 
          certificateUrl.toString().contains('firebasestorage.googleapis.com')) {
        try {
          await FirebaseStorage.instance.refFromURL(certificateUrl).delete();
          debugPrint('Certificate deleted successfully');
        } catch (e) {
          debugPrint('Error deleting certificate: $e');
        }
      }
    } catch (e) {
      debugPrint('Error deleting item: $e');
      await _loadExperienceData();
      if (mounted) _showErrorMessage('Failed to delete item');
    }
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF01509B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorMessage('Could not open link');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      _showErrorMessage('Invalid link format');
    }
  }

  void _showCertificatePreview(String certificateUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(certificateUrl, fit: BoxFit.contain),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategorySection({
    required String title,
    required IconData icon,
    required String category,
    required List<dynamic> items,
  }) {
    final displayItems = items.length > 1 ? items.sublist(0, 1) : items;
    final hasMore = items.length > 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 2),
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
                    color: const Color(0xFF01509B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Icon(icon, color: const Color(0xFF01509B), size: 24.0),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF01509B),
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
                    if (result == true && mounted) {
                      await _loadExperienceData();
                    }
                  },
                  borderRadius: BorderRadius.circular(12.0),
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF83C8EF), Color(0xFF01509B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
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
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CategoryDetailPage(
                          title: title,
                          icon: icon,
                          category: category,
                        ),
                      ),
                    );
                    if (result == true && mounted) {
                      await _loadExperienceData();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF01509B).withOpacity(0.05),
                          const Color(0xFF83C8EF).withOpacity(0.05),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: const Color(0xFF01509B).withOpacity(0.3),
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
                            color: Color(0xFF01509B),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Color(0xFF01509B),
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

  String _getDateOrHoursText(Map<String, dynamic> item) {
    if (item['startDate'] != null || item['endDate'] != null) {
      return '${item['startDate'] ?? 'N/A'} - ${item['endDate'] ?? 'Present'}';
    } else if (item['year'] != null) {
      return 'Year: ${item['year']}';
    } else if (item['hours'] != null && item['hours'].toString().isNotEmpty) {
      return 'Hours: ${item['hours']}';
    }
    return '';
  }

  Widget _buildExperienceItem({
    required Map<String, dynamic> item,
    required String category,
    required int index,
  }) {
    final itemKey = _getItemKey(category, index);
    final isExpanded = expandedItems.contains(itemKey);
    final dateOrHoursText = _getDateOrHoursText(item);

    return Container(
      margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF83C8EF).withOpacity(0.1),
            const Color(0xFF01509B).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: const Color(0xFF83C8EF).withOpacity(0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                expandedItems.remove(itemKey);
              } else {
                expandedItems.add(itemKey);
              }
            });
          },
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                              color: Color(0xFF01509B),
                            ),
                          ),
                          if (dateOrHoursText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                dateOrHoursText,
                                style: TextStyle(
                                  fontSize: 13.0,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          if (!isExpanded)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                'Tap to view details',
                                style: TextStyle(
                                  fontSize: 12.0,
                                  color: const Color(0xFF01509B).withOpacity(0.7),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: const Color(0xFF01509B).withOpacity(0.7), size: 20.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                          if (result == true && mounted) {
                            await _loadExperienceData();
                          }
                        } else if (value == 'delete') {
                          await _deleteItem(category, index);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Color(0xFF01509B), size: 20),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
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
                
                if (isExpanded) ...[
                  const SizedBox(height: 8.0),
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
                  if (item['link'] != null && item['link'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: InkWell(
                        onTap: () => _launchUrl(item['link']),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.link, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item['link'],
                                style: const TextStyle(
                                  fontSize: 13.0,
                                  color: Color(0xFF01509B),
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: null,
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (item['certificateUrl'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: InkWell(
                        onTap: () => _showCertificatePreview(item['certificateUrl']),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.upload_file, size: 16, color: Color(0xFF01509B)),
                            SizedBox(width: 6),
                            Text(
                              'Certificate uploaded (tap to view)',
                              style: TextStyle(
                                fontSize: 13.0,
                                color: Color(0xFF01509B),
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
@override
Widget build(BuildContext context) {
  const Color kBg = Color(0xFFE6F3FF);
  const Color kTopBar = Color(0xFF0D4F94);

  return Scaffold(
    backgroundColor: kBg,
    body: Column(  // ✅ Remove SafeArea wrapper from here
      children: [
        // Header section - matching profile page style
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: kTopBar,
            borderRadius: const BorderRadius.only(
              bottomRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(  // ✅ Add SafeArea INSIDE the header container
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Row(
                children: [
                  const SizedBox(width: 48), // Left spacing to match profile
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "My Experience",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                  // Invisible placeholder to match profile menu button dimensions exactly
                  Padding(
                    padding: EdgeInsets.all(8.0), // Extra outer padding
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Icon(
                          Icons.more_vert,
                          color: Colors.transparent,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(  // ✅ Add SafeArea for content area with top: false
            top: false,
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF01509B),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF01509B),
                    onRefresh: _loadExperienceData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20.0, bottom: 80.0),
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
    floatingActionButton: Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF01509B), Color(0xFF83C8EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF01509B).withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () async {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );

          try {
            final docId = await _getUserDocId();
            if (docId == null) {
              if (mounted) Navigator.pop(context);
              _showErrorMessage('Unable to identify user');
              return;
            }

            final doc = await _firestore.collection('users').doc(docId).get();
            
            if (!doc.exists) {
              if (mounted) Navigator.pop(context);
              _showErrorMessage('User data not found');
              return;
            }

            final data = doc.data();
            final projects = data?['projects'] ?? [];
            final workshops = data?['workshops'] ?? [];
            final clubs = data?['clubs'] ?? [];
            final volunteering = data?['volunteering'] ?? [];

            if (projects.isEmpty && workshops.isEmpty && clubs.isEmpty && volunteering.isEmpty) {
              if (mounted) Navigator.pop(context);
              _showErrorMessage('Please add at least one project, workshop, club, or volunteering experience before generating CV');
              return;
            }

            if (mounted) Navigator.pop(context);

            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CVPage(autoGenerate: true),
                ),
              );
            }
          } catch (e) {
            if (mounted) Navigator.pop(context);
            _showErrorMessage('Failed to check experiences: ${e.toString()}');
          }
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.description, color: Colors.white),
        label: const Text(
          'Generate CV',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    ),
  );
}}