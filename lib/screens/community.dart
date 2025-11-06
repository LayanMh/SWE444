import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin {
  static const List<String> _categories = [
    'Hackathon',
    'Course',
    'Certificate',
  ];

  late final TabController _tabController;
  bool _isLoadingProfile = true;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserMajor;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _loadCurrentStudent();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentStudent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final microsoftDocId = prefs.getString('microsoft_user_doc_id');
      DocumentSnapshot<Map<String, dynamic>>? doc;

      if (microsoftDocId != null) {
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(microsoftDocId)
            .get();
      } else {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
        }
      }

      final data = doc?.data();
      if (data != null) {
        setState(() {
          _currentUserId = doc!.id;
          _currentUserName = _resolveFullName(data);
          _currentUserMajor = _resolveMajor(data['major']);
          _isLoadingProfile = false;
        });
      } else {
        setState(() => _isLoadingProfile = false);
      }
    } catch (e) {
      debugPrint('Failed to load current student: $e');
      setState(() => _isLoadingProfile = false);
    }
  }

  String _resolveFullName(Map<String, dynamic> data) {
    final first = (data['FName'] ?? '').toString().trim();
    final last = (data['LName'] ?? '').toString().trim();
    final candidate = '$first $last'.trim();
    if (candidate.isNotEmpty) {
      return candidate;
    }
    return data['displayName']?.toString() ?? 'Student';
  }

  String? _resolveMajor(dynamic rawMajor) {
    if (rawMajor == null) return null;
    if (rawMajor is String && rawMajor.trim().isNotEmpty) {
      return rawMajor.trim();
    }
    if (rawMajor is List && rawMajor.isNotEmpty) {
      final first = rawMajor.first;
      if (first is String && first.trim().isNotEmpty) {
        return first.trim();
      }
    }
    return null;
  }

  bool get _canCreatePost => !_isLoadingProfile && _currentUserId != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Community'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _categories.map((category) => Tab(text: category)).toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _canCreatePost ? _openCreatePostSheet : null,
        icon: const Icon(Icons.edit),
        label: const Text('New post'),
        tooltip: _canCreatePost
            ? 'Share something new'
            : 'Sign in to add a community post',
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map(_buildCategoryFeed).toList(),
      ),
    );
  }

  Widget _buildCategoryFeed(String category) {
    final stream = FirebaseFirestore.instance
        .collection('community_posts')
        .where('category', isEqualTo: category)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(message: snapshot.error.toString());
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final posts = docs.map(CommunityPost.fromDoc).toList();

        if (posts.isEmpty) {
          return _EmptyCategoryState(category: category);
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
          itemCount: posts.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _buildPostCard(posts[index]),
        );
      },
    );
  }

  Widget _buildPostCard(CommunityPost post) {
    final color = _categoryColor(post.category);
    final icon = _categoryIcon(post.category);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Text(
                    _initialsFromName(post.studentName),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.studentName,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          (post.studentMajor != null &&
                                  post.studentMajor!.trim().isNotEmpty)
                              ? post.studentMajor!
                              : 'Student',
                          _timeAgo(post.createdAt),
                        ].join(' • '),
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 4),
                      Text(
                        post.category,
                        style: textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              post.title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.description,
              style: textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
            if (post.resourceLink != null &&
                post.resourceLink!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_outlined, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        post.resourceLink!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.blueGrey[700],
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openCreatePostSheet() {
    if (!_canCreatePost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to create a post.')),
      );
      return;
    }

    final avatarColor = _avatarColorFor(_currentUserId!);
    final initials = _initialsFromName(_currentUserName ?? 'Student');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _PostComposerSheet(
          categories: _categories,
          initialCategory: _categories[_tabController.index],
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName ?? 'Student',
          currentUserMajor: _currentUserMajor,
          avatarColor: avatarColor,
          userInitials: initials,
          onPosted: () {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Post published for the community.'),
              ),
            );
          },
        );
      },
    );
  }

  Color _avatarColorFor(String id) {
    const palette = [
      Color(0xFF3F51B5),
      Color(0xFF1E88E5),
      Color(0xFF00897B),
      Color(0xFFF4511E),
      Color(0xFF8E24AA),
      Color(0xFF3949AB),
    ];
    final hash = id.codeUnits.fold<int>(0, (value, element) => value + element);
    return palette[hash % palette.length];
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Hackathon':
        return const Color(0xFF00796B);
      case 'Course':
        return const Color(0xFF3949AB);
      case 'Certificate':
        return const Color(0xFFEF6C00);
      default:
        return const Color(0xFF546E7A);
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Hackathon':
        return Icons.rocket_launch_outlined;
      case 'Course':
        return Icons.menu_book_outlined;
      case 'Certificate':
        return Icons.workspace_premium_outlined;
      default:
        return Icons.forum_outlined;
    }
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\\s+'));
    if (parts.isEmpty) {
      return 'ST';
    }
    if (parts.length == 1) {
      final value = parts.first;
      if (value.length >= 2) {
        return value.substring(0, 2).toUpperCase();
      }
      return value.toUpperCase();
    }
    final first = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    final combined = '$first$second';
    return combined.toUpperCase();
  }

  String _timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }
    if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    }
    if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    }
    final years = (difference.inDays / 365).floor();
    return '${years}y ago';
  }
}

class _PostComposerSheet extends StatefulWidget {
  const _PostComposerSheet({
    required this.categories,
    required this.initialCategory,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserMajor,
    required this.avatarColor,
    required this.userInitials,
    required this.onPosted,
  });

  final List<String> categories;
  final String initialCategory;
  final String currentUserId;
  final String currentUserName;
  final String? currentUserMajor;
  final Color avatarColor;
  final String userInitials;
  final VoidCallback onPosted;

  @override
  State<_PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<_PostComposerSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;
  late final TextEditingController _linkController;
  late String _selectedCategory = widget.initialCategory;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _detailsController = TextEditingController();
    _linkController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance.collection('community_posts').add({
        'title': _titleController.text.trim(),
        'description': _detailsController.text.trim(),
        'resourceLink': _linkController.text.trim().isEmpty
            ? null
            : _linkController.text.trim(),
        'category': _selectedCategory,
        'studentId': widget.currentUserId,
        'studentName': widget.currentUserName,
        'studentMajor': widget.currentUserMajor,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onPosted();
    } catch (e) {
      debugPrint('Failed to publish post: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not publish post. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomInset + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: widget.avatarColor,
                    child: Text(
                      widget.userInitials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.currentUserName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.currentUserMajor ?? 'Student',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Share with the community',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                items: widget.categories
                    .map(
                      (category) => DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedCategory = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'E.g. Healthcare Hackathon 2025',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please add a title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _detailsController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  hintText:
                      'Describe the opportunity, requirements, or what you are asking for.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please add some details.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _linkController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Resource link (optional)',
                  hintText:
                      'Share a registration form, slides, or documentation link.',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link_outlined),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isSubmitting ? 'Sharing...' : 'Share update',
                  ),
                  onPressed: _isSubmitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommunityPost {
  CommunityPost({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.studentId,
    required this.studentName,
    required this.createdAt,
    this.studentMajor,
    this.resourceLink,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String? resourceLink;
  final String studentId;
  final String studentName;
  final String? studentMajor;
  final DateTime createdAt;

  factory CommunityPost.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final timestamp = data['createdAt'];
    return CommunityPost(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      category: (data['category'] ?? 'Course').toString(),
      resourceLink: data['resourceLink']?.toString(),
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? 'Student').toString(),
      studentMajor: data['studentMajor']?.toString(),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
    );
  }
}

class _EmptyCategoryState extends StatelessWidget {
  const _EmptyCategoryState({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'No $category posts yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to share a $category update with everyone.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[400], size: 42),
            const SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}
