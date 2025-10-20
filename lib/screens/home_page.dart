import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' show initializeTimeZones;

import 'calendar_screen.dart';
import 'experience.dart';
import 'community.dart';
import 'profile.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
   
  final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();
  @override
  void initState(){
    init();
    super.initState();
  }

Future<void> init() async {
  initializeTimeZones();
  //! https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  setLocalLocation(
    getLocation('Asia/Riyadh'),
  );
  const androidSettings =
    AndroidInitializationSettings('@mipmap/launcher_icon');
  const InitializationSettings initializationSettings =
      InitializationSettings(
        android: androidSettings,
  );

await notificationsPlugin.initialize(initializationSettings);
}

Future<void> showInstantNotification({
  required int id,
  required String title,
  required String body,
}) async {
  await notificationsPlugin.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'instant_notification_channel_id',
        'Instant Notifications',
        channelDescription: 'Instant notification channel',
        importance: Importance.max,
        priority: Priority.high,
      ), // AndroidNotificationDetails
    ), // NotificationDetails
  );
}

Future<void> scheduleReminder({
  required int id,
  required String title,
  String? body,
}) async {
  TZDateTime now = TZDateTime.now(local);
  TZDateTime scheduledDate = now.add(
    Duration (seconds: 3),
  );
await notificationsPlugin.zonedSchedule(
  id,
  title,
  body,
  scheduledDate,
  const NotificationDetails(
    android: AndroidNotificationDetails (
      'daily_reminder_channel_id', // A unique ID to group notifications together.
      'Daily Reminders', // A human-readable name shown to users in their notification settings.
      channelDescription: 'Reminder to complete daily habits',
      importance: Importance.max,
      priority: Priority.high,
    ), // AndroidNotificationDetails
  ), // NotificationDetails
  androidScheduleMode: AndroidScheduleMode. inexactAllowWhileIdle,
  matchDateTimeComponents:
      DateTimeComponents.dayOfWeekAndTime, // or dateAndTime
  );
}

  int _selectedIndex = 2; 
final GlobalKey<ProfileScreenState> _profileKey = GlobalKey<ProfileScreenState>();
late final List<Widget> _tabs = <Widget>[
  ProfileScreen(key: _profileKey),  // ← add key here
  const CalendarScreen(),
  //const _HomeTab(),
  const ExperiencePage(),
  const CommunityPage(),
];

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
Widget build (BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      backgroundColor: Theme. of (context).colorScheme.inversePrimary,
      title: Text('Flutter Pro'),
      ), // AppBar
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          FilledButton(
            onPressed: () {
              showInstantNotification(
                id: 0, title: 'Instant notif', body: 'body');
            },
            child: Text('Instant notif'),
          ), // FilledButton
          FilledButton(
            onPressed: () {},
            child: Text('Scheduled notif'),
          ), // FilledButton
        ], // <Widget>[]
      ), // Column
    ), // Center
  ); // Scaffold

  /*@override
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
  }*/
}

/*class _HomeTab extends StatefulWidget {
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [Color(0xFF006B7A), Color(0xFF0097B2), Color(0xFF0E0259)],
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
                    onTapRoute: '/swapping',
                    accent: const Color(0xFF4ECDC4),
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
                  _FeatureCard(
                    title: 'My Courses',
                    subtitle: 'Manage sections',
                    icon: Icons.menu_book_rounded,
                    onTapRoute: '/my-courses',
                    accent: const Color(0xFF4E8FFF),
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
  }*/
}