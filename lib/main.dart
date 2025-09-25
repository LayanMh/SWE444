import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/schedule_provider.dart';

// New
import 'screens/home_page.dart';
import 'screens/gpa_calc.dart';
import 'screens/swapping_main.dart';
import 'screens/experience.dart';
import 'screens/community.dart';

// Existing
import 'screens/welcome_screen.dart';
import 'screens/calendar_screen.dart'; 
import 'screens/add_lecture_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e, st) {
    debugPrint('Firebase initialization failed: $e');
    debugPrintStack(stackTrace: st);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = const ColorScheme.light(
      primary: Color(0xFF0097b2),
      primaryContainer: Color(0xFF95E1D3),
      secondary: Color(0xFF4ECDC4),
      secondaryContainer: Color(0xFF95E1D3),
      tertiary: Color(0xFF0e0259),
      surface: Color(0xFFFFFFFF),
      onPrimary: Colors.white,
      onPrimaryContainer: Color(0xFF0e0259),
      onSecondary: Colors.white,
      onSecondaryContainer: Color(0xFF0e0259),
      onTertiary: Colors.white,
      onSurface: Color(0xFF0e0259),
      error: Color(0xFFB00020),
      onError: Colors.white,
      outline: Color(0xFF4ECDC4),
    ).copyWith(surfaceContainerHighest: const Color(0xFFE0F7F0));

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ABSHERK',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: colorScheme,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0097b2),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF0097b2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: Color(0xFF0097b2),
              side: const BorderSide(color: Color(0xFF4ECDC4)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF0097b2)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4ECDC4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
            ),
            floatingLabelStyle: const TextStyle(color: Color(0xFF0097b2)),
          ),
        ),

        //  Welcome before sign in
        home: const WelcomeScreen(),

        routes: {
      
          '/calendar': (_) => const CalendarScreen(), 
          '/add-lecture': (_) => const AddLectureScreen(),

        
          '/home': (_) => const HomePage(), 
          '/swapping': (_) => const SwapRequestPage(),
  '/calculator': (_) => const GpaCalculator(),


          '/experience': (_) => const ExperiencePage(),
          '/community': (_) => const CommunityPage(),
          '/absence': (_) => const AbsencePage(),
        },
      ),
    );
  }
}

//  Absence placeholder
class AbsencePage extends StatelessWidget {
  const AbsencePage({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text("Absence Page")));
}