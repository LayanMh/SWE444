import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_screen.dart'; 
import 'experience.dart';
import 'community.dart';
import 'profile.dart';
import 'swapping_main.dart';
import 'MySwapRequestPage.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 2; 

  late final List<Widget> _tabs = <Widget>[
    ProfileScreen(),
    const CalendarScreen(),
    const _HomeTab(), 
    const ExperiencePage(),
    const CommunityPage(),
  ];

  void _onTap(int i) => setState(() => _selectedIndex = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_rounded),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: ImageIcon(AssetImage('assets/images/logo.png')),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school_rounded),
            label: 'Experience',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_rounded),
            label: 'Community',
          ),
        ],
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

    if (doc != null && doc.exists) {
      final data = doc.data();
      setState(() {
        firstName = data?['FName'] ?? "User";
        _loading = false;
      });
    } else {
      setState(() {
        firstName = "User";
        _loading = false;
      });
    }
  } catch (e) {
    debugPrint("❌ Error fetching user name: $e");
    setState(() {
      firstName = "User";
      _loading = false;
    });
  }
}


  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [
            Color(0xFF006B7A),
            Color(0xFF0097B2),
            Color(0xFF0E0259),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header 
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
                    child: _loading
                        ? const Text(
                            "Welcome...",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : Text(
                            "Hello $firstName \n! أبشر في أبشّرك ..",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Quick Actions 
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                "Quick Actions",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 3 Quick Action Buttons
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
                    accent: const Color(0xFF4ECDC4),
                    onTap: () async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please log in first.")),
                        );
                        return;
                      }

                      try {
                        final snapshot = await FirebaseFirestore.instance
                            .collection("swap_requests")
                            .where("userId", isEqualTo: uid)
                            .limit(1)
                            .get();

                        if (snapshot.docs.isEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SwapRequestPage()),
                          );
                        } else {
  final doc = snapshot.docs.first;
  final requestId = doc.id;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MySwapRequestPage(requestId: requestId),
    ),
  );
}

                      } catch (e) {
                        debugPrint("❌ Error checking swap requests: $e");
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error loading swapping data: $e")),
                        );
                      }
                    },
                  ),
                  _FeatureCard(
                    title: 'GPA Calculator',
                    subtitle: 'Plan your term',
                    icon: Icons.calculate_rounded,
                    onTapRoute: '/calculator',
                    accent: const Color(0xFF95E1D3),
                  ),
                  _FeatureCard(
                    title: 'Absence',
                    subtitle: 'Track attendance',
                    icon: Icons.assignment_turned_in_rounded,
                    onTapRoute: '/absence',
                    accent: const Color(0xFF0097B2),
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
  final String? onTapRoute;
  final VoidCallback? onTap;
  final Color accent;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTapRoute,
    this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap ?? () {
        if (onTapRoute != null) {
          Navigator.pushNamed(context, onTapRoute!);
        }
      },
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
                color: Color(0xFF0E0259),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF0E0259).withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
