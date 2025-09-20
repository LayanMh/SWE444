import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';

void main() async {
  // Ensure that Flutter is initialized before running Firebase.
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Firebase with proper configuration options
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("🔥 Firebase initialized successfully");
  } catch (e) {
    print("❌ Firebase initialization failed: $e");
    // You might want to show an error dialog or handle this gracefully
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ABSHERK',

      // Define a custom theme for the entire application.
      theme: ThemeData(
        useMaterial3: true,
        
        // Define a custom ColorScheme based on the "Deep Sea" palette.
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0097b2),
          primaryContainer: Color(0xFF95E1D3),
          secondary: Color(0xFF4ECDC4),
          secondaryContainer: Color(0xFF95E1D3),
          tertiary: Color(0xFF0e0259),
          
          surface: Color(0xFFFFFFFF),
          background: Color(0xFFFFFFFF),
          surfaceVariant: Color(0xFFE0F7F0),
          
          onPrimary: Colors.white,
          onPrimaryContainer: Color(0xFF0e0259),
          onSecondary: Colors.white,
          onSecondaryContainer: Color(0xFF0e0259),
          onTertiary: Colors.white,
          onSurface: Color(0xFF0e0259),
          onBackground: Color(0xFF0e0259),
          
          error: Color(0xFFB00020),
          onError: Colors.white,
          outline: Color(0xFF4ECDC4),
        ),
        
        // Customize individual widget themes.
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0097b2),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0097b2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0097b2),
            side: const BorderSide(color: Color(0xFF4ECDC4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0097b2),
          ),
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
      
      // The starting point of the application.
      home: const WelcomeScreen(),
    );
  }
}

