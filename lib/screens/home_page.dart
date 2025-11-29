import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_screen.dart';
import 'experience.dart';
import 'community.dart';
import 'profile.dart';

const _kBgColor = Color(0xFFE6F3FF);
const _kTopBar = Color(0xFF0D4F94);
const _kAccent = Color(0xFF4A98E9);

class HomePage extends StatefulWidget {
  final int initialIndex;

  const HomePage({super.key, this.initialIndex = 2});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  late int _selectedIndex;
final GlobalKey<ProfileScreenState> _profileKey = GlobalKey<ProfileScreenState>();
late final List<Widget> _tabs = <Widget>[
  ProfileScreen(key: _profileKey),  // ← add key here
  const CalendarScreen(),
  const _HomeTab(),
  const ExperiencePage(),
  const CommunityPage(),
];

 @override
 void initState() {
   super.initState();
   _selectedIndex = widget.initialIndex;
 }

 void _onTap(int i) async {
  // If leaving Profile (index 0) while in edit mode
  if (_selectedIndex == 0 && i != 0) {
    final profileState = _profileKey.currentState;
    if (profileState != null && profileState.isEditMode) {
      // Ask user whether to discard edits or stay
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Changes?'),
          content: const Text('You have unsaved changes. Do you want to leave without saving?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      // If user wants to stay → do nothing
      if (shouldLeave != true) return;

      // Otherwise cancel edits before switching tab
      profileState.cancelEdit();
    }
  }

  setState(() => _selectedIndex = i);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _tabs),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xF2EAF3FF), // light tinted background with slight opacity
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                active: _selectedIndex == 0,
                onTap: () => _onTap(0),
              ),
              _NavItem(
                icon: Icons.event_available_outlined,
                label: 'Schedule',
                active: _selectedIndex == 1,
                onTap: () => _onTap(1),
              ),
              _NavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                active: _selectedIndex == 2,
                onTap: () => _onTap(2),
              ),
              _NavItem(
                icon: Icons.school_outlined,
                label: 'Experience',
                active: _selectedIndex == 3,
                onTap: () => _onTap(3),
              ),
              _NavItem(
                icon: Icons.people_outline,
                label: 'Community',
                active: _selectedIndex == 4,
                onTap: () => _onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const inactiveColor = Color(0xFF7A8DA8);
    const activeColor = Color(0xFF2E5D9F);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? activeColor : inactiveColor, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? activeColor : inactiveColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                width: active ? 26 : 0,
                decoration: BoxDecoration(
                  color: active ? activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  String? firstName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
  }

  Future<void> _fetchUserName() async {
    try {
      // First check SharedPreferences for Microsoft user
      final prefs = await SharedPreferences.getInstance();
      final microsoftDocId = prefs.getString('microsoft_user_doc_id');

      DocumentSnapshot<Map<String, dynamic>>? doc;

      if (microsoftDocId != null) {
        // Microsoft user
        doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(microsoftDocId)
            .get();
      } else {
        // Regular Firebase Auth user
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
        }
      }

      if (doc != null && doc.exists && doc.data() != null) {
        setState(() {
          firstName = doc!.data()!['FName'] ?? "User";
          _loading = false;
        });
      } else {
        setState(() {
          firstName = "User";
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        firstName = "User";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = firstName ?? 'User';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [_kTopBar, _kAccent, Color(0xFF123B73)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 48,
                      width: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Hi there!',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$displayName, plan your learning journey today',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Quick Actions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: GridView.count(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.05,
                children: [
                  _FeatureCard(
                    title: 'Swapping',
                    subtitle: 'Post a request',
                    icon: Icons.swap_horiz_rounded,
                    onTapRoute: '/swapping',
                    accent: _kAccent,
                  ),
                  _FeatureCard(
                    title: 'GPA Calculator',
                    subtitle: 'Plan your term',
                    icon: Icons.calculate_rounded,
                    onTapRoute: '/calculator',
                    accent: _kTopBar,
                  ),
                  _FeatureCard(
                    title: 'Absence',
                    subtitle: 'Track attendance',
                    icon: Icons.assignment_turned_in_rounded,
                    onTapRoute: '/absence',
                    accent: const Color(0xFF356FD2),
                  ),
                  _FeatureCard(
                    title: 'My Courses',
                    subtitle: 'Manage sections',
                    icon: Icons.menu_book_rounded,
                    onTapRoute: '/my-courses',
                    accent: Color(0xFF7199FF),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String onTapRoute;
  final Color accent;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTapRoute,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.pushNamed(context, onTapRoute),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.95),
              Colors.white.withOpacity(0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.25),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _kTopBar,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: _kTopBar.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
