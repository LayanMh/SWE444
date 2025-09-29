import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? errorMessage;
  String? currentUserEmail; // Track email for display

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final prefs = await SharedPreferences.getInstance();
      final microsoftDocId = prefs.getString('microsoft_user_doc_id');
      final microsoftEmail = prefs.getString('microsoft_user_email');

     DocumentSnapshot<Map<String, dynamic>>? doc;

      // Check if this is a Microsoft user
      if (microsoftDocId != null) {
        doc = await _firestore
            .collection('users')
            .doc(microsoftDocId)
            .get();
        
        // Store email for display
        if (microsoftEmail != null) {
          currentUserEmail = microsoftEmail;
        }
      } else {
        // Regular Firebase Auth user
        final User? user = _auth.currentUser;
        if (user != null) {
          doc = await _firestore
              .collection('users')
              .doc(user.uid)
              .get();
          currentUserEmail = user.email;
        }
      }

      if (doc != null && doc.exists) {
  setState(() {
    userData = doc!.data() as Map<String, dynamic>?;
    isLoading = false;
  });
}
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading profile: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('microsoft_user_email');
      await prefs.remove('microsoft_user_doc_id');
     
      
      // Sign out from Firebase Auth (if user exists)
      if (_auth.currentUser != null) {
        await _auth.signOut();
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e')),
      );
    }
  }
Future<void> _deleteAccount() async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    
    String? docIdToDelete;

    if (microsoftDocId != null) {
      docIdToDelete = microsoftDocId;
    } else if (_auth.currentUser != null) {
      docIdToDelete = _auth.currentUser!.uid;
    }

    if (docIdToDelete != null) {
      // Get user data to check auth provider and email
      final userDoc = await _firestore.collection('users').doc(docIdToDelete).get();
      final userData = userDoc.data();
      final authProvider = userData?['authProvider'];
      final userEmail = userData?['email'];
      
      // **IF EMAIL USER: Ask for password FIRST before deleting anything**
      if (authProvider == 'email' && userEmail != null) {
        debugPrint('📧 Email account - verifying password before deletion');
        
        final savedPassword = prefs.getString('saved_password');
        bool authSuccess = false;
        
        if (savedPassword != null) {
          try {
            await _auth.signInWithEmailAndPassword(
              email: userEmail,
              password: savedPassword,
            );
            authSuccess = true;
          } catch (e) {
            debugPrint('⚠️ Saved password invalid, asking user');
          }
        }
        
        // If saved password didn't work, ask user
        if (!authSuccess) {
          authSuccess = await _showPasswordDialogAndVerify(userEmail);
        }
        
        // If password verification failed, STOP - don't delete anything
        if (!authSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Account deletion cancelled'),
                backgroundColor: Colors.orange[400],
              ),
            );
          }
          return; // EXIT without deleting
        }
      }
      
      // Password verified (or Microsoft user) - NOW delete everything
      debugPrint('🗑️ Deleting user document: $docIdToDelete');
      await _firestore.collection('users').doc(docIdToDelete).delete();
      debugPrint('✅ Firestore document deleted');

      // Delete Firebase Auth account if exists
      if (_auth.currentUser != null) {
        await _auth.currentUser!.delete();
        debugPrint('✅ Firebase Auth account deleted');
      }
    }

    // Clear ALL SharedPreferences
    await prefs.remove('saved_email');
    await prefs.remove('saved_password');
    await prefs.remove('microsoft_user_email');
    await prefs.remove('microsoft_user_doc_id');
    await prefs.remove('microsoft_last_email');
    await prefs.setBool('remember_me', false);
    await prefs.setBool('microsoft_remember_me', false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Account deleted successfully'),
          backgroundColor: const Color(0xFF4ECDC4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      Navigator.of(context).pushReplacementNamed('/');
    }
  } catch (e) {
    debugPrint('❌ Error deleting account: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting account: $e'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }
}

// Updated method - returns true if password correct, false if wrong
Future<bool> _showPasswordDialogAndVerify(String email) async {
  final passwordController = TextEditingController();
  
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please enter your password to delete your account:'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );

  if (confirmed == true && passwordController.text.isNotEmpty) {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: passwordController.text,
      );
      debugPrint('✅ Password verified');
      return true; // Password correct
    } catch (e) {
      debugPrint('❌ Password verification failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Incorrect password'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
      return false; // Password wrong
    }
  }
  
  return false; // User cancelled
}
// Add this method to ask for password
Future<void> _showPasswordDialogAndDelete(String email) async {
  final passwordController = TextEditingController();
  
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('To complete account deletion, please enter your password:'),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      );
    },
  );

  if (confirmed == true && passwordController.text.isNotEmpty) {
    try {
      // Sign in with password
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: passwordController.text,
      );
      
      // Delete Firebase Auth account
      await credential.user!.delete();
      debugPrint('✅ Firebase Auth account deleted with user-provided password');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account fully deleted'),
            backgroundColor: Color(0xFF4ECDC4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Password verification failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incorrect password. Firebase Auth account not deleted.'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
    }
  }
}
  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF0097b2),
            size: 24.0,
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.0,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0e0259),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getDisplayName() {
    if (userData != null) {
      final firstName = userData!['FName'] ?? '';
      final lastName = userData!['LName'] ?? '';
      return '$firstName $lastName'.trim();
    }
    return 'User';
  }

  String _getInitials() {
    if (userData != null) {
      final firstName = userData!['FName'] ?? '';
      final lastName = userData!['LName'] ?? '';
      String initials = '';
      if (firstName.isNotEmpty) initials += firstName[0].toUpperCase();
      if (lastName.isNotEmpty) initials += lastName[0].toUpperCase();
      return initials.isNotEmpty ? initials : 'U';
    }

    // Fallback: try current email
    final email = currentUserEmail ?? _auth.currentUser?.email;
    if (email != null && email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return 'U';
  }

  String _getMajorDisplay() {
    if (userData?['major'] != null) {
      // Handle both string and list formats
      if (userData!['major'] is String) {
        return userData!['major'];
      } else if (userData!['major'] is List) {
        final majorList = List<String>.from(userData!['major']);
        return majorList.isNotEmpty ? majorList.first : 'Not specified';
      }
    }
    return 'Not specified';
  }

  String _getLevelDisplay() {
    if (userData?['level'] != null) {
      // Handle both int and list formats
      if (userData!['level'] is int) {
        return 'Level ${userData!['level']}';
      } else if (userData!['level'] is List) {
        final levelList = List<int>.from(userData!['level']);
        return levelList.isNotEmpty ? 'Level ${levelList.first}' : 'Not specified';
      }
    }
    return 'Not specified';
  }

  String _getGenderDisplay() {
    if (userData?['gender'] != null) {
      // Handle both string and list formats
      if (userData!['gender'] is String) {
        return userData!['gender'];
      } else if (userData!['gender'] is List) {
        final genderList = List<String>.from(userData!['gender']);
        return genderList.isNotEmpty ? genderList.first : 'Not specified';
      }
    }
    return 'Not specified';
  }

  String _getGpaDisplay() {
    if (userData?['GPA'] != null) {
      final gpa = userData!['GPA'];
      if (gpa is num) {
        return gpa.toStringAsFixed(2);
      }
    }
    return 'Not specified';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              // Custom App Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    const Expanded(
                      child: Text(
                        'My Profile',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'refresh') {
                          _loadUserData();
                        } else if (value == 'delete') {
                          _deleteAccount();
                        }
                      },
                      icon: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'refresh',
                          child: Row(
                            children: [
                              Icon(Icons.refresh, color: Color(0xFF0097b2)),
                              SizedBox(width: 8),
                              Text('Refresh'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_forever, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete Account'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Profile Content
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: RefreshIndicator(
                    onRefresh: _loadUserData,
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 64.0,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16.0),
                                    Text(
                                      errorMessage!,
                                      style: TextStyle(
                                        fontSize: 16.0,
                                        color: Colors.grey[600],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16.0),
                                    ElevatedButton(
                                      onPressed: _loadUserData,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Column(
                                  children: [
                                    // Profile Header
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(24.0),
                                      child: Column(
                                        children: [
                                          CircleAvatar(
                                            radius: 50.0,
                                            backgroundColor: const Color(0xFF0097b2),
                                            child: Text(
                                              _getInitials(),
                                              style: const TextStyle(
                                                fontSize: 36.0,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16.0),
                                          Text(
                                            _getDisplayName(),
                                            style: const TextStyle(
                                              fontSize: 24.0,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0e0259),
                                            ),
                                          ),
                                          const SizedBox(height: 8.0),
                                          Text(
                                            currentUserEmail ?? _auth.currentUser?.email ?? 'No email',
                                            style: TextStyle(
                                              fontSize: 16.0,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Personal Information
                                    if (userData?['FName'] != null)
                                      _buildInfoTile(
                                        icon: Icons.person,
                                        title: 'First Name',
                                        value: userData!['FName'],
                                      ),
                                    if (userData?['LName'] != null)
                                      _buildInfoTile(
                                        icon: Icons.person_outline,
                                        title: 'Last Name',
                                        value: userData!['LName'],
                                      ),
                                    _buildInfoTile(
                                      icon: Icons.email,
                                      title: 'Email Address',
                                      value: currentUserEmail ?? _auth.currentUser?.email ?? 'Not available',
                                    ),
                                    // Academic Information
                                    _buildInfoTile(
                                      icon: Icons.school,
                                      title: 'Major',
                                      value: _getMajorDisplay(),
                                    ),
                                    _buildInfoTile(
                                      icon: Icons.trending_up,
                                      title: 'Academic Level',
                                      value: _getLevelDisplay(),
                                    ),
                                    _buildInfoTile(
                                      icon: Icons.grade,
                                      title: 'Current GPA',
                                      value: _getGpaDisplay(),
                                    ),
                                    _buildInfoTile(
                                      icon: Icons.person_pin,
                                      title: 'Gender',
                                      value: _getGenderDisplay(),
                                    ),
                                    const SizedBox(height: 30.0),
                                    // Sign Out Button
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: Container(
                                        width: double.infinity,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Colors.red, Color(0xFFD32F2F)],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.red.withOpacity(0.3),
                                              blurRadius: 20,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: _signOut,
                                          icon: const Icon(Icons.logout),
                                          label: const Text(
                                            'Sign Out',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 30.0),
                                  ],
                                ),
                              ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}