import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'home_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin {
  static const List<String> _categories = [
    'All',
    'Hackathon',
    'Course',
    'Certificate',
  ];

  // Palette similar to GPA / Absence pages
  static const Color _kTopBarColor = Color(0xFF0D4F94);
  static const Color _kPageBackground = Color(0xFFF2F6FF);
  static const Color _kTabContainer = Color(0xFF0A3E82);
  static const Color _kActiveTab = Colors.white;
  static const Color _kInactiveTab = Color(0xFFD0E2FF);

  late final TabController _tabController;
  bool _isLoadingProfile = true;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserMajor;
  final Set<String> _likeOperationsInFlight = <String>{};
  final Set<String> _saveOperationsInFlight = <String>{};
  final Set<String> _deleteOperationsInFlight = <String>{};

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

  void _onNavTap(int index) {
    // Same navigation behavior as Absence / GPA pages
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Top bar styled like GPA page
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(140),
        child: Container(
          decoration: const BoxDecoration(
            color: _kTopBarColor,
            borderRadius: BorderRadius.only(
              bottomRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      const Spacer(),
                      const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Community',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 18),
                      const Spacer(),
                      _buildProfileAction(),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 14),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kTabContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: _kActiveTab,
                      unselectedLabelColor: _kInactiveTab,
                      indicator: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      tabs: _categories
                          .map((category) => Tab(text: category))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _canCreatePost ? _openCreatePostSheet : null,
        backgroundColor: const Color(0xFF1E88E5),
        icon: const Icon(Icons.edit),
        label: const Text('New post'),
        tooltip: _canCreatePost
            ? 'Share something new'
            : 'Sign in to add a community post',
      ),

      body: Container(
        color: _kPageBackground,
        child: TabBarView(
          controller: _tabController,
          children: _categories.map(_buildCategoryFeed).toList(),
        ),
      ),

     
    );
  }

  Widget _buildProfileAction() {
    if (_isLoadingProfile) {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      );
    }

    if (_currentUserId == null) {
      return IconButton(
        tooltip: 'Sign in to view your community profile',
        icon: const Icon(Icons.person_outline, color: Colors.white),
        onPressed: () => _showAuthRequiredSnack('view your profile'),
      );
    }

    final avatarColor = _avatarColorFor(_currentUserId!);
    final initials = _initialsFromName(_currentUserName ?? 'Student');
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: _openProfileSheet,
        child: CircleAvatar(
          radius: 18,
          backgroundColor: avatarColor.withOpacity(0.2),
          child: Text(
            initials,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  void _showAuthRequiredSnack(String actionDescription) {
    _showFloatingSnack('Please sign in to $actionDescription.');
  }

  void _showFloatingSnack(String message, {Color? backgroundColor}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openProfileSheet() {
    final userId = _currentUserId;
    if (userId == null) {
      _showAuthRequiredSnack('view your profile');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _ProfileSheet(
          userName: _currentUserName ?? 'Student',
          userMajor: _currentUserMajor,
          userInitials: _initialsFromName(_currentUserName ?? 'Student'),
          avatarColor: _avatarColorFor(userId),
          currentUserId: userId,
          postBuilder: _buildPostCard,
          showSavedTab: true,
        );
      },
    );
  }

  Widget _buildCategoryFeed(String category) {
    final stream = FirebaseFirestore.instance
        .collection('community_posts')
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
        final posts = docs
            .map(CommunityPost.fromDoc)
            .where((post) => category == 'All'
                ? true
                : _normalizeCategory(post.category) ==
                    _normalizeCategory(category))
            .toList();

        if (posts.isEmpty) {
          return _EmptyCategoryState(category: category);
        }

        return ListView.separated(
          key: PageStorageKey('community-$category'),
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
    final textTheme = Theme.of(context).textTheme;
    final userId = _currentUserId;
    final isLiked = userId != null && post.likedBy.contains(userId);
    final isSaved = userId != null && post.savedBy.contains(userId);
    final likeBusy = _likeOperationsInFlight.contains(post.id);
    final saveBusy = _saveOperationsInFlight.contains(post.id);
    final hasImage =
        post.imageUrl != null && post.imageUrl!.trim().isNotEmpty;
    final caption = post.description.trim();
    final isOwner = userId != null && userId == post.studentId;
    final isDeleting = _deleteOperationsInFlight.contains(post.id);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.hardEdge,
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () => _openUserProfile(post),
                  borderRadius: BorderRadius.circular(24),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: color.withOpacity(0.25),
                    child: Text(
                      _initialsFromName(post.studentName),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    post.studentName,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    post.category,
                    style: textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(width: 4),
                  isDeleting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : PopupMenuButton<_PostAction>(
                          onSelected: (action) =>
                              _handlePostAction(action, post),
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _PostAction.delete,
                              child: Text('Delete post'),
                            ),
                          ],
                        ),
                ],
              ],
            ),
          ),

          // Image
          if (hasImage)
            AspectRatio(
              aspectRatio: 4 / 5,
              child: Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, size: 32),
                ),
              ),
            ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.redAccent : Colors.black87,
                  ),
                  onPressed: likeBusy
                      ? null
                      : (userId == null
                          ? () => _showAuthRequiredSnack('like posts')
                          : () => _toggleLike(post, isLiked)),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_outline,
                    color: isSaved
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black87,
                  ),
                  onPressed: saveBusy
                      ? null
                      : (userId == null
                          ? () => _showAuthRequiredSnack('save posts')
                          : () => _toggleSave(post, isSaved)),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.likesCount > 0 || likeBusy)
                  Text(
                    '${post.likesCount} '
                    '${post.likesCount == 1 ? 'like' : 'likes'}',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 4),
                if (caption.isNotEmpty)
                  RichText(
                    text: TextSpan(
                      style: textTheme.bodyMedium?.copyWith(height: 1.4),
                      children: [
                        TextSpan(
                          text: '${post.studentName} ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: caption),
                      ],
                    ),
                  ),
                if (post.resourceLink != null &&
                    post.resourceLink!.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _showFloatingSnack(
                      'Open links from this post manually for now.',
                    ),
                    child: Text(
                      post.resourceLink!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.blueAccent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _timeAgo(post.createdAt),
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _toggleLike(CommunityPost post, bool currentlyLiked) async {
    final userId = _currentUserId;
    if (userId == null) {
      _showAuthRequiredSnack('like posts');
      return;
    }
    if (_likeOperationsInFlight.contains(post.id)) return;

    setState(() => _likeOperationsInFlight.add(post.id));
    try {
      await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(post.id)
          .update({
        'likes': currentlyLiked
            ? FieldValue.arrayRemove([userId])
            : FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      debugPrint('Failed to toggle like: $e');
      if (mounted) {
        _showFloatingSnack('We could not update your like. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _likeOperationsInFlight.remove(post.id));
      }
    }
  }

  Future<void> _toggleSave(CommunityPost post, bool currentlySaved) async {
    final userId = _currentUserId;
    if (userId == null) {
      _showAuthRequiredSnack('save posts');
      return;
    }
    if (_saveOperationsInFlight.contains(post.id)) return;

    setState(() => _saveOperationsInFlight.add(post.id));
    try {
      await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(post.id)
          .update({
        'saves': currentlySaved
            ? FieldValue.arrayRemove([userId])
            : FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      debugPrint('Failed to toggle save: $e');
      if (mounted) {
        _showFloatingSnack('Unable to save this post right now.');
      }
    } finally {
      if (mounted) {
        setState(() => _saveOperationsInFlight.remove(post.id));
      }
    }
  }

  void _handlePostAction(_PostAction action, CommunityPost post) {
    switch (action) {
      case _PostAction.delete:
        _confirmDelete(post);
        break;
    }
  }

  void _openUserProfile(CommunityPost post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _ProfileSheet(
          userName: post.studentName,
          userMajor: post.studentMajor,
          userInitials: _initialsFromName(post.studentName),
          avatarColor: _avatarColorFor(post.studentId),
          currentUserId: post.studentId,
          postBuilder: _buildPostCard,
          showSavedTab: post.studentId == _currentUserId,
        );
      },
    );
  }

  Future<void> _confirmDelete(CommunityPost post) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete post?'),
          content: const Text(
            'This post will be removed from the community feed permanently.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deletePost(post);
    }
  }

  Future<void> _deletePost(CommunityPost post) async {
    if (_deleteOperationsInFlight.contains(post.id)) return;

    setState(() => _deleteOperationsInFlight.add(post.id));
    try {
      await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(post.id)
          .delete();
      if (mounted) {
        _showFloatingSnack('Post deleted.');
      }
    } catch (e) {
      debugPrint('Failed to delete post: $e');
      if (mounted) {
        _showFloatingSnack('Could not delete this post. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _deleteOperationsInFlight.remove(post.id));
      } else {
        _deleteOperationsInFlight.remove(post.id);
      }
    }
  }

  void _openCreatePostSheet() {
    if (!_canCreatePost) {
      _showFloatingSnack('Please sign in to create a post.');
      return;
    }

    final avatarColor = _avatarColorFor(_currentUserId!);
    final initials = _initialsFromName(_currentUserName ?? 'Student');
    final creationCategories =
        _categories.where((category) => category != 'All').toList();
    final initialCategory = _tabController.index == 0
        ? creationCategories.first
        : _categories[_tabController.index];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _PostComposerSheet(
          categories: creationCategories,
          initialCategory: initialCategory,
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName ?? 'Student',
          currentUserMajor: _currentUserMajor,
          avatarColor: avatarColor,
          userInitials: initials,
          onPosted: () {
            if (!mounted) return;
            _showFloatingSnack('Post published for the community.');
          },
          scaffoldContext: context,
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
    switch (_normalizeCategory(category)) {
      case 'hackathon':
        return const Color(0xFF00796B);
      case 'course':
        return const Color(0xFF3949AB);
      case 'certificate':
        return const Color(0xFFEF6C00);
      default:
        return const Color(0xFF546E7A);
    }
  }

  String _normalizeCategory(String category) {
    return category.trim().toLowerCase();
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
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

/* ─────────────────────────  Composer Sheet  ───────────────────────── */

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
    required this.scaffoldContext,
  });

  final List<String> categories;
  final String initialCategory;
  final String currentUserId;
  final String currentUserName;
  final String? currentUserMajor;
  final Color avatarColor;
  final String userInitials;
  final VoidCallback onPosted;
  final BuildContext scaffoldContext;

  @override
  State<_PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<_PostComposerSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _captionController;
  late final TextEditingController _linkController;
  late String _selectedCategory = widget.initialCategory;
  bool _isSubmitting = false;
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  final _photoFieldKey = GlobalKey<FormFieldState<String>>();

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController();
    _linkController = TextEditingController();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (result != null) {
        setState(() {
          _selectedImage = result;
        });
        _photoFieldKey.currentState?.didChange(result.path);
      }
    } on PlatformException catch (e) {
      debugPrint('Image picker permission error: $e');
      if (!mounted) return;
      final friendlyMessage = switch (e.code) {
        'photo_access_denied' =>
            'Please allow gallery access so we can show your photo.',
        'camera_access_denied' =>
            'Camera permission is required to capture a new photo.',
        _ => 'We need photo permissions to continue. Check your settings.',
      };
      _showSheetSnack(friendlyMessage);
    } catch (e) {
      debugPrint('Failed to pick image: $e');
      if (!mounted) return;
      _showSheetSnack('Could not access gallery right now.');
    }
  }

  void _showSheetSnack(String message) {
    final messenger = ScaffoldMessenger.of(widget.scaffoldContext);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _removeImage() {
    setState(() => _selectedImage = null);
    _photoFieldKey.currentState?.didChange(null);
  }

  /// Uploads selected image to ImgBB and returns the public URL.
  Future<String> _uploadSelectedImage() async {
    final image = _selectedImage;
    if (image == null) {
      throw StateError('No image selected');
    }

    final file = File(image.path);
    if (!await file.exists()) {
      throw StateError('Selected image file is missing');
    }

    try {
      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload'),
        body: {
          // same key used elsewhere in app
          'key': '0b411c63631d14df85c76a6cdbcf1667',
          'image': base64Image,
          'name':
              'community_${widget.currentUserId}_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final imageUrl = data['data']['url'] as String;
        debugPrint('✅ Community image upload success: $imageUrl');
        return imageUrl;
      } else {
        debugPrint(
          '❌ Community image upload failed: '
          '${response.statusCode} ${response.body}',
        );
        throw Exception('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error uploading community image: $e');
      if (mounted) {
        _showSheetSnack(
          'Failed to upload image. Please check your internet connection.',
        );
      }
      rethrow;
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_photoFieldKey.currentState?.validate() == false) return;

    setState(() => _isSubmitting = true);
    try {
      final caption = _captionController.text.trim();
      final imageUrl = await _uploadSelectedImage();
      await FirebaseFirestore.instance.collection('community_posts').add({
        'title': 'Community photo',
        'description': caption,
        'resourceLink': _linkController.text.trim().isEmpty
            ? null
            : _linkController.text.trim(),
        'imageUrl': imageUrl,
        'category': _selectedCategory.trim(),
        'studentId': widget.currentUserId,
        'studentName': widget.currentUserName,
        'studentMajor': widget.currentUserMajor,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': <String>[],
        'saves': <String>[],
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onPosted();
    } catch (e) {
      debugPrint('Failed to publish post: $e');
      if (!mounted) return;
      _showSheetSnack('Could not publish post. Please try again.');
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
              FormField<String>(
                key: _photoFieldKey,
                validator: (_) =>
                    _selectedImage == null ? 'A photo is required.' : null,
                builder: (state) {
                  final hasError = state.hasError;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_selectedImage != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            children: [
                              AspectRatio(
                                aspectRatio: 4 / 5,
                                child: Image.file(
                                  File(_selectedImage!.path),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: CircleAvatar(
                                  backgroundColor: Colors.black54,
                                  child: IconButton(
                                    onPressed: _removeImage,
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _pickImage,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: hasError
                                ? Theme.of(context).colorScheme.error
                                : const Color(0xFF4ECDC4),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        icon: Icon(
                          Icons.photo_outlined,
                          color: hasError
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                        label: Text(
                          _selectedImage == null
                              ? 'Add photo'
                              : 'Change selected photo',
                          style: TextStyle(
                            color: hasError
                                ? Theme.of(context).colorScheme.error
                                : null,
                            fontWeight:
                                hasError ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                      if (hasError) ...[
                        const SizedBox(height: 4),
                        Text(
                          state.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _captionController,
                minLines: 4,
                maxLines: 8,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Caption',
                  hintText: 'Describe the story behind this photo.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please write a caption.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
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
                controller: _linkController,
                keyboardType: TextInputType.url,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  if (text.length < 5 || text.length > 2000) {
                    return 'Link must be between 5 and 2000 characters.';
                  }
                  if (text.contains(RegExp(r'\s'))) {
                    return 'Link cannot contain spaces.';
                  }
                  String? scheme;
                  if (text.startsWith('https://')) {
                    scheme = 'https://';
                  } else if (text.startsWith('http://')) {
                    scheme = 'http://';
                  }
                  if (scheme == null) {
                    return 'Link must start with http:// or https://';
                  }
                  final remainder = text.substring(scheme.length);
                  if (remainder.startsWith('/')) {
                    return 'Use only two slashes after the scheme (e.g., https://example.com).';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'Resource link (optional)',
                  hintText:
                      'Share a form, slides, link.',
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

/* ─────────────────────────  Profile Sheet  ───────────────────────── */

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet({
    required this.userName,
    required this.userMajor,
    required this.userInitials,
    required this.avatarColor,
    required this.currentUserId,
    required this.postBuilder,
    required this.showSavedTab,
  });

  final String userName;
  final String? userMajor;
  final String userInitials;
  final Color avatarColor;
  final String currentUserId;
  final Widget Function(CommunityPost post) postBuilder;
  final bool showSavedTab;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Container(
            color: colorScheme.surface,
            height: MediaQuery.of(context).size.height * 0.9,
            child: DefaultTabController(
              length: showSavedTab ? 2 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    child: Container(
                      width: 48,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: CircleAvatar(
                      radius: 28,
                      backgroundColor: avatarColor.withOpacity(0.15),
                      child: Text(
                        userInitials,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    title: Text(
                      userName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      userMajor ?? 'Student',
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TabBar(
                      indicatorColor: const Color(0xFF0097b2),
                      labelColor: const Color(0xFF0097b2),
                      tabs: showSavedTab
                          ? const [Tab(text: 'My posts'), Tab(text: 'Saved')]
                          : const [Tab(text: 'Posts')],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _ProfilePostsTab(
                          query: FirebaseFirestore.instance
                              .collection('community_posts')
                              .where('studentId', isEqualTo: currentUserId),
                          postBuilder: postBuilder,
                          emptyIcon: Icons.edit_note,
                          emptyTitle: 'No community posts yet',
                          emptyDescription:
                              'Share an update with the community and it will appear here.',
                        ),
                        if (showSavedTab)
                          _ProfilePostsTab(
                            query: FirebaseFirestore.instance
                                .collection('community_posts')
                                .where('saves', arrayContains: currentUserId),
                            postBuilder: postBuilder,
                            emptyIcon: Icons.bookmark_added_outlined,
                            emptyTitle: 'Nothing saved',
                            emptyDescription:
                                'Use the save button on posts you want to revisit.',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfilePostsTab extends StatelessWidget {
  const _ProfilePostsTab({
    required this.query,
    required this.postBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyDescription,
  });

  final Query<Map<String, dynamic>> query;
  final Widget Function(CommunityPost post) postBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyDescription;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(message: snapshot.error.toString());
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final posts = docs.map(CommunityPost.fromDoc).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (posts.isEmpty) {
          return _ProfileEmptyState(
            icon: emptyIcon,
            title: emptyTitle,
            description: emptyDescription,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          itemCount: posts.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (_, index) => postBuilder(posts[index]),
        );
      },
    );
  }
}

class _ProfileEmptyState extends StatelessWidget {
  const _ProfileEmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            Text(
              title,
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/* ─────────────────────────  Models & States  ───────────────────────── */

enum _PostAction { delete }

class CommunityPost {
  CommunityPost({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.studentId,
    required this.studentName,
    required this.createdAt,
    required this.likedBy,
    required this.savedBy,
    this.studentMajor,
    this.resourceLink,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String? resourceLink;
  final String? imageUrl;
  final String studentId;
  final String studentName;
  final String? studentMajor;
  final DateTime createdAt;
  final List<String> likedBy;
  final List<String> savedBy;

  int get likesCount => likedBy.length;
  int get savesCount => savedBy.length;

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
      resourceLink: _cleanText(data['resourceLink']),
      imageUrl: _cleanText(data['imageUrl']),
      studentId: (data['studentId'] ?? '').toString(),
      studentName: (data['studentName'] ?? 'Student').toString(),
      studentMajor: data['studentMajor']?.toString(),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      likedBy: _stringList(data['likes']),
      savedBy: _stringList(data['saves']),
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is Iterable) {
      return raw
          .map((entry) => (entry?.toString() ?? '').trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  static String? _cleanText(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
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
