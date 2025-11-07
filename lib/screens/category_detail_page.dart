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

class CategoryDetailPage extends StatefulWidget {
  final String title;
  final IconData icon;
  final String category;

  const CategoryDetailPage({
    super.key,
    required this.title,
    required this.icon,
    required this.category,
  });

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Set<String> expandedItems = {};
  List<dynamic> items = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
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

  Future<void> _loadData() async {
    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final doc = await _firestore.collection('users').doc(docId).get();
      
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          items = List.from(data?[widget.category] ?? []);
          isLoading = false;
        });
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _deleteItem(int index) async {
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

      // Optimistically update UI
      final item = items[index];
      setState(() {
        items.removeAt(index);
      });

      // Update Firestore
      await _firestore.collection('users').doc(docId).update({
        widget.category: items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Delete certificate in background
      if (item['certificateUrl'] != null && 
          item['certificateUrl'].toString().isNotEmpty &&
          item['certificateUrl'].toString().startsWith('https://')) {
        try {
          await FirebaseStorage.instance.refFromURL(item['certificateUrl']).delete();
        } catch (e) {
          // Silently ignore certificate deletion errors
          debugPrint('Certificate deletion skipped: $e');
        }
      }

      // Pop back if list is empty
      if (items.isEmpty && mounted) {
        Navigator.pop(context, true); // Return true to indicate changes were made
      }
    } catch (e) {
      debugPrint('Error deleting item: $e');
      // Reload on error
      await _loadData();
      if (mounted) _showErrorMessage('Failed to delete item');
    }
  }
Future<void> _deleteAll() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete All Items'),
      content: Text('Are you sure you want to delete all ${items.length} items? This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete All'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    final docId = await _getUserDocId();
    if (docId == null) return;

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Delete all certificates in background
    for (var item in items) {
      if (item['certificateUrl'] != null && 
          item['certificateUrl'].toString().isNotEmpty &&
          item['certificateUrl'].toString().startsWith('https://')) {
        try {
          await FirebaseStorage.instance.refFromURL(item['certificateUrl']).delete();
        } catch (e) {
          debugPrint('Certificate deletion skipped: $e');
        }
      }
    }

    // Clear the array in Firestore
    await _firestore.collection('users').doc(docId).update({
      widget.category: [],
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Close loading dialog
    if (mounted) Navigator.pop(context);

    // Pop back since list is empty
    if (mounted) {
      Navigator.pop(context, true);
    }
  } catch (e) {
    // Close loading dialog if open
    if (mounted) Navigator.pop(context);
    
    debugPrint('Error deleting all items: $e');
    if (mounted) _showErrorMessage('Failed to delete all items');
    
    // Reload on error
    await _loadData();
  }
}
  String _getItemKey(int index) {
    return '${widget.category}-$index';
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

  void _launchUrl(String url) async {
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

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Always return true to indicate data may have changed
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
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
                  padding: const EdgeInsets.only(
                    top: 16.0,
                    left: 16.0,
                    right: 16.0,
                    bottom: 8.0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context, true),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: 20.0),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      // Delete All button - only shows when items exist
                      if (items.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.delete_sweep, color: Colors.white),
                          onPressed: _deleteAll,
                          tooltip: 'Delete All',
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
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : items.isEmpty
                            ? Center(
                                child: Text(
                                  'No items to display',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadData,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16.0),
                                  itemCount: items.length,
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    return _buildDetailItem(item, index);
                                  },
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

  Widget _buildDetailItem(Map<String, dynamic> item, int index) {
    final itemKey = _getItemKey(index);
    final isExpanded = expandedItems.contains(itemKey);
    final dateOrHoursText = _getDateOrHoursText(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF95E1D3).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: const Color(0xFF95E1D3).withOpacity(0.2),
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
                // Header - Always visible
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
                              color: Color(0xFF0e0259),
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
                          // "Tap to expand" hint when collapsed
                          if (!isExpanded)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                'Tap to view details',
                                style: TextStyle(
                                  fontSize: 12.0,
                                  color: const Color(0xFF0097b2).withOpacity(0.7),
                                  fontStyle: FontStyle.italic,
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
                          switch (widget.category) {
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
                          
                          // Reload immediately after edit
                          if (result == true && mounted) {
                            await _loadData();
                          }
                        } else if (value == 'delete') {
                          await _deleteItem(index);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Color(0xFF0097b2), size: 20),
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
                
                // Expanded details
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
                                  color: Color(0xFF0097b2),
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
                            Icon(Icons.upload_file, size: 16, color: Color(0xFF0097b2)),
                            SizedBox(width: 6),
                            Text(
                              'Certificate uploaded (tap to view)',
                              style: TextStyle(
                                fontSize: 13.0,
                                color: Color(0xFF0097b2),
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
}