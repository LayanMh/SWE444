import 'package:flutter/material.dart';
import 'home_page.dart';

abstract class AppScreen extends StatefulWidget {
  const AppScreen({super.key});
}
abstract class AppScreenState<T extends AppScreen> extends State<T> {

  void onNavTap(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomePage(initialIndex: index)),
    );
  }

  Widget buildNavBar({required int currentIndex}) {
    const inactiveColor = Color(0xFF7A8DA8);
    const activeColor  = Color(0xFF2E5D9F);
    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8,  vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xF2EAF3FF),
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
            navItem(Icons.person_outline,           'Profile',    currentIndex == 0, () => onNavTap(0), activeColor, inactiveColor),
            navItem(Icons.event_available_outlined,  'Schedule',   currentIndex == 1, () => onNavTap(1), activeColor, inactiveColor),
            navItem(Icons.home_outlined,             'Home',       currentIndex == 2, () => onNavTap(2), activeColor, inactiveColor),
            navItem(Icons.school_outlined,           'Experience', currentIndex == 3, () => onNavTap(3), activeColor, inactiveColor),
            navItem(Icons.people_outline,            'Community',  currentIndex == 4, () => onNavTap(4), activeColor, inactiveColor),
          ],
        ),
      ),
    );
  }

  Widget navItem(
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap,
    Color activeColor,
    Color inactiveColor,
  ) {
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