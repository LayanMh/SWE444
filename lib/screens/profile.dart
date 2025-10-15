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
String? currentUserEmail;

String? _editingField;
final Map<String, TextEditingController> _controllers = {};
final Map<String, GlobalKey<FormState>> _formKeys = {};

List<String> _majorOptions = [];
List<int> _levelOptions = [];
bool _isEditMode = false;

@override
void initState() {
super.initState();
_loadUserData();
_loadDropdownOptions();
}

@override
void dispose() {
_controllers.forEach((key, controller) => controller.dispose());
super.dispose();
}

Future<void> _loadDropdownOptions() async {
try {
final doc = await _firestore
.collection('users')
.doc("5YACUgOv9DV043jJreFPGuwXh2e2")
.get();

if (doc.exists) {
setState(() {
if (doc.data()?['major'] != null) {
_majorOptions = List<String>.from(doc.data()!['major']);
}
if (doc.data()?['level'] != null) {
_levelOptions = List<int>.from(doc.data()!['level']);
}
});
}
} catch (e) {
debugPrint('Error loading options: $e');
}
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

if (microsoftDocId != null) {
doc = await _firestore.collection('users').doc(microsoftDocId).get();
if (microsoftEmail != null) {
currentUserEmail = microsoftEmail;
}
} else {
final User? user = _auth.currentUser;
if (user != null) {
doc = await _firestore.collection('users').doc(user.uid).get();
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
final prefs = await SharedPreferences.getInstance();
await prefs.remove('microsoft_user_email');
await prefs.remove('microsoft_user_doc_id');

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
final userDoc =
await _firestore.collection('users').doc(docIdToDelete).get();
final userData = userDoc.data();
final authProvider = userData?['authProvider'];
final userEmail = userData?['email'];

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
debugPrint('Saved password invalid, asking user');
}
}

if (!authSuccess) {
authSuccess = await _showPasswordDialogAndVerify(userEmail);
}

if (!authSuccess) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: const Text('Account deletion cancelled'),
backgroundColor: Colors.red[400],
),
);
}
return;
}
}

debugPrint('Deleting user document: $docIdToDelete');
await _firestore.collection('users').doc(docIdToDelete).delete();
debugPrint('Firestore document deleted');

if (_auth.currentUser != null) {
await _auth.currentUser!.delete();
debugPrint('Firebase Auth account deleted');
}
}

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
shape:
RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
),
);
Navigator.of(context).pushReplacementNamed('/');
}
} catch (e) {
debugPrint('Error deleting account: $e');
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text('Error deleting account: $e'),
backgroundColor: Colors.red[400],
behavior: SnackBarBehavior.floating,
shape:
RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
),
);
}
}
}

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
return true;
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
return false;
}
}

return false;
}

Future<void> _updateField(String fieldName, dynamic value) async {
try {
final prefs = await SharedPreferences.getInstance();
final microsoftDocId = prefs.getString('microsoft_user_doc_id');

String? docId;
if (microsoftDocId != null) {
docId = microsoftDocId;
} else if (_auth.currentUser != null) {
docId = _auth.currentUser!.uid;
}

if (docId == null) {
_showErrorMessage('Unable to identify user');
return;
}

// Parse GPA if it's a string
dynamic finalValue = value;
if (fieldName == 'GPA' && value is String) {
finalValue = double.parse(value);
}

await _firestore.collection('users').doc(docId).update({
fieldName: finalValue,
'updatedAt': FieldValue.serverTimestamp(),
});

_showSuccessMessage('Updated successfully!');
await _loadUserData();
} catch (e) {
debugPrint('Error updating field: $e');
_showErrorMessage('Failed to update: $e');
}
}

void _showSuccessMessage(String message) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(message),
backgroundColor: const Color(0xFF4ECDC4),
behavior: SnackBarBehavior.floating,
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
),
);
}

void _showErrorMessage(String message) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Text(message),
backgroundColor: Colors.red[400],
behavior: SnackBarBehavior.floating,
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
),
);
}

Future<void> _saveAllChanges() async {
// Validate all form fields
bool allValid = true;
_formKeys.forEach((key, formKey) {
if (formKey.currentState?.validate() == false) {
allValid = false;
}
});

if (!allValid) {
_showErrorMessage('Please fix all validation errors');
return;
}

try {
final prefs = await SharedPreferences.getInstance();
final microsoftDocId = prefs.getString('microsoft_user_doc_id');

String? docId;
if (microsoftDocId != null) {
docId = microsoftDocId;
} else if (_auth.currentUser != null) {
docId = _auth.currentUser!.uid;
}

if (docId == null) {
_showErrorMessage('Unable to identify user');
return;
}

Map<String, dynamic> updates = {};

// Collect all changes from text field controllers
_controllers.forEach((fieldName, controller) {
if (fieldName == 'GPA') {
final gpaValue = double.tryParse(controller.text.trim());
if (gpaValue != null) {
updates[fieldName] = gpaValue;
}
} else {
updates[fieldName] = controller.text.trim();
}
});

// Add dropdown values (major and level)
if (userData?['major'] != null) {
updates['major'] = userData!['major'];
}
if (userData?['level'] != null) {
updates['level'] = userData!['level'];
}

// Add timestamp
updates['updatedAt'] = FieldValue.serverTimestamp();

// Update Firestore
await _firestore.collection('users').doc(docId).update(updates);

setState(() => _isEditMode = false);
_showSuccessMessage('Profile updated successfully!');
// Clear controllers
_controllers.clear();
_formKeys.clear();
await _loadUserData();
} catch (e) {
debugPrint('Error saving changes: $e');
_showErrorMessage('Failed to save changes: $e');
}
}

Widget _buildEditableTextField({
required IconData icon,
required String title,
required String fieldName,
required String? Function(String?) validator,
String? hint,
TextInputType? keyboardType,
bool isEditable = true,
}) {
// Initialize controller if not exists
if (!_controllers.containsKey(fieldName) && userData?[fieldName] != null) {
String value = '';
if (fieldName == 'GPA') {
final gpa = userData![fieldName];
value = gpa is num ? gpa.toStringAsFixed(2) : '';
} else {
value = userData![fieldName].toString();
}
_controllers[fieldName] = TextEditingController(text: value);
_formKeys[fieldName] = GlobalKey<FormState>();
}

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
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(
icon,
color: isEditable && _isEditMode
? const Color(0xFF0097b2)
: Colors.grey[400],
size: 24.0,
),
const SizedBox(width: 16.0),
Text(
title,
style: TextStyle(
fontSize: 14.0,
color: Colors.grey[600],
fontWeight: FontWeight.w500,
),
),
],
),
const SizedBox(height: 8.0),
if (_isEditMode && isEditable)
Form(
key: _formKeys[fieldName],
child: TextFormField(
controller: _controllers[fieldName],
keyboardType: keyboardType,
validator: validator,
enabled: isEditable,
decoration: InputDecoration(
hintText: hint,
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
enabledBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
focusedBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
contentPadding: const EdgeInsets.symmetric(
horizontal: 12,
vertical: 12,
),
filled: true,
fillColor: const Color(0xFF95E1D3).withOpacity(0.1),
),
),
)
else
Text(
_controllers[fieldName]?.text ??
(userData?[fieldName]?.toString() ?? 'Not specified'),
style: TextStyle(
fontSize: 16.0,
fontWeight: FontWeight.w600,
color: isEditable
? const Color(0xFF0e0259)
: Colors.grey[600],
),
),
],
),
);
}

Widget _buildEditableDropdown<T>({
required IconData icon,
required String title,
required String fieldName,
required List<T> options,
required T? Function() getCurrentValue,
required String Function(T?) displayValue,
bool isEditable = true,
}) {
final currentValue = getCurrentValue();

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
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(
icon,
color: isEditable && _isEditMode
? const Color(0xFF0097b2)
: Colors.grey[400],
size: 24.0,
),
const SizedBox(width: 16.0),
Text(
title,
style: TextStyle(
fontSize: 14.0,
color: Colors.grey[600],
fontWeight: FontWeight.w500,
),
),
],
),
const SizedBox(height: 8.0),
if (_isEditMode && isEditable && options.isNotEmpty)
DropdownButtonFormField<T>(
value: currentValue,
isExpanded: true,
decoration: InputDecoration(
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
enabledBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
focusedBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
contentPadding: const EdgeInsets.symmetric(
horizontal: 12,
vertical: 12,
),
filled: true,
fillColor: const Color(0xFF95E1D3).withOpacity(0.1),
),
items: options.map((item) {
return DropdownMenuItem<T>(
value: item,
child: Text(item.toString()),
);
}).toList(),
onChanged: (newValue) {
setState(() {
// Store the selected value to be saved later
if (fieldName == 'major') {
userData!['major'] = [newValue];
} else if (fieldName == 'level') {
userData!['level'] = [newValue];
}
});
},
)
else
Text(
displayValue(currentValue),
style: TextStyle(
fontSize: 16.0,
fontWeight: FontWeight.w600,
color: isEditable
? const Color(0xFF0e0259)
: Colors.grey[600],
),
),
],
),
);
}

Widget _buildReadOnlyTile({
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
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(icon, color: Colors.grey[400], size: 24.0),
const SizedBox(width: 16.0),
Text(
title,
style: TextStyle(
fontSize: 14.0,
color: Colors.grey[600],
fontWeight: FontWeight.w500,
),
),
],
),
const SizedBox(height: 8.0),
Text(
value,
style: TextStyle(
fontSize: 16.0,
fontWeight: FontWeight.w600,
color: Colors.grey[600],
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

final email = currentUserEmail ?? _auth.currentUser?.email;
if (email != null && email.isNotEmpty) {
return email[0].toUpperCase();
}
return 'U';
}

String _getMajorDisplay() {
if (userData?['major'] != null) {
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

double? _getCurrentGpa() {
if (userData?['GPA'] != null) {
final gpa = userData!['GPA'];
if (gpa is num) {
return gpa.toDouble();
}
}
return null;
}

String? _getCurrentMajor() {
if (userData?['major'] != null) {
if (userData!['major'] is String) {
return userData!['major'];
} else if (userData!['major'] is List) {
final majorList = List<String>.from(userData!['major']);
return majorList.isNotEmpty ? majorList.first : null;
}
}
return null;
}

int? _getCurrentLevel() {
if (userData?['level'] != null) {
if (userData!['level'] is int) {
return userData!['level'];
} else if (userData!['level'] is List) {
final levelList = List<int>.from(userData!['level']);
return levelList.isNotEmpty ? levelList.first : null;
}
}
return null;
}

// Validation methods
String? _validateName(String? value, String fieldName) {
if (value == null || value.trim().isEmpty) {
return 'Please enter your $fieldName';
}
if (value.trim().contains(' ')) {
return '$fieldName cannot contain spaces';
}
if (RegExp(r'\d').hasMatch(value.trim())) {
return '$fieldName cannot contain numbers';
}
if (value.trim().length > 30) {
return '$fieldName cannot exceed 30 characters';
}
if (!RegExp(r'^[a-zA-Z]+$').hasMatch(value.trim())) {
return '$fieldName can only contain letters';
}
if (RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true)
.hasMatch(value.trim())) {
return '$fieldName cannot contain emojis';
}
return null;
}

String? _validateGPA(String? value) {
if (value == null || value.trim().isEmpty) {
return 'Please enter your current GPA';
}
final gpaValue = double.tryParse(value.trim());
if (gpaValue == null || gpaValue < 0 || gpaValue > 5) {
return 'GPA must be between 0.00 and 5.00';
}
if (value.trim().contains('.')) {
final parts = value.trim().split('.');
if (parts.length == 2 && parts[1].length > 2) {
return 'GPA can have at most 2 decimal places';
}
}
return null;
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
if (value == 'edit') {
setState(() => _isEditMode = true);
} else if (value == 'refresh') {
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
if (!_isEditMode)
const PopupMenuItem<String>(
value: 'edit',
child: Row(
children: [
Icon(Icons.edit, color: Color(0xFF0097b2)),
SizedBox(width: 8),
Text('Edit Profile'),
],
),
),
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
physics:
const AlwaysScrollableScrollPhysics(),
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
backgroundColor:
const Color(0xFF0097b2),
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
currentUserEmail ??
_auth.currentUser?.email ??
'No email',
style: TextStyle(
fontSize: 16.0,
color: Colors.grey[600],
),
),
const SizedBox(height: 8.0),
],
),
),
// Personal Information
if (userData?['FName'] != null)
_buildEditableTextField(
icon: Icons.person,
title: 'First Name',
fieldName: 'FName',
validator: (value) => _validateName(value, 'First name'),
),
if (userData?['LName'] != null)
_buildEditableTextField(
icon: Icons.person_outline,
title: 'Last Name',
fieldName: 'LName',
validator: (value) => _validateName(value, 'Last name'),
),
_buildReadOnlyTile(
icon: Icons.email,
title: 'Email Address',
value: currentUserEmail ?? _auth.currentUser?.email ?? 'Not available',
),
// Academic Information
_buildEditableDropdown<String>(
icon: Icons.school,
title: 'Major',
fieldName: 'major',
options: _majorOptions,
getCurrentValue: _getCurrentMajor,
displayValue: (value) => value ?? 'Not specified',
),
_buildEditableDropdown<int>(
icon: Icons.trending_up,
title: 'Academic Level',
fieldName: 'level',
options: _levelOptions,
getCurrentValue: _getCurrentLevel,
displayValue: (value) => value != null ? 'Level $value' : 'Not specified',
),
_buildEditableTextField(
icon: Icons.grade,
title: 'Current GPA',
fieldName: 'GPA',
hint: 'e.g., 3.75',
keyboardType: const TextInputType.numberWithOptions(decimal: true),
validator: _validateGPA,
),
_buildReadOnlyTile(
icon: Icons.person_pin,
title: 'Gender',
value: _getGenderDisplay(),
),
const SizedBox(height: 30.0),
// Edit Mode: Save/Cancel Buttons OR Sign Out Button
Padding(
padding: const EdgeInsets.symmetric(horizontal: 16.0),
child: _isEditMode
? Row(
children: [
Expanded(
child: Container(
height: 48,
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(12),
border: Border.all(
color: const Color(0xFF0097b2),
width: 2,
),
),
child: ElevatedButton.icon(
onPressed: () {
// Clear controllers and reload data
_controllers.clear();
_formKeys.clear();
setState(() => _isEditMode = false);
_loadUserData();
},
icon: const Icon(Icons.close),
label: const Text(
'Cancel',
style: TextStyle(
fontSize: 16,
fontWeight: FontWeight.w600,
letterSpacing: 0.5,
),
),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.white,
foregroundColor: const Color(0xFF0097b2),
elevation: 0,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
),
),
),
),
),
const SizedBox(width: 12),
Expanded(
child: Container(
height: 48,
decoration: BoxDecoration(
gradient: const LinearGradient(
colors: [Color(0xFF0097b2), Color(0xFF006B7A)],
),
borderRadius: BorderRadius.circular(12),
boxShadow: [
BoxShadow(
color: const Color(0xFF0097b2).withOpacity(0.3),
blurRadius: 20,
offset: const Offset(0, 8),
),
],
),
child: ElevatedButton.icon(
onPressed: _saveAllChanges,
icon: const Icon(Icons.check),
label: const Text(
'Save',
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
],
)
: Container(
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