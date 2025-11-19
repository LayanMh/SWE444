import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CVGeneratorService {
  // Get API key from environment variable
  static String get _apiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';
 
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get user document ID (supports both Microsoft and Firebase auth)
  Future<String?> _getUserDocId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');
    
    if (microsoftDocId != null) {
      return microsoftDocId;
    } else if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    return null;
  }

  /// Fetch all user data needed for CV generation
  Future<Map<String, dynamic>> fetchAllUserData() async {
    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        throw Exception('Unable to identify user');
      }

      final doc = await _firestore.collection('users').doc(docId).get();
      
      if (!doc.exists) {
        throw Exception('User document not found');
      }

      final data = doc.data() ?? {};
      
      // Extract profile information
      final profileInfo = {
        'FName': data['FName'] ?? '',
        'LName': data['LName'] ?? '',
        'studentID': data['studentID'] ?? '',
        'email': data['email'] ?? '',
        'major': _getMajorString(data['major']),
        'level': data['level']?.toString() ?? '',
        'GPA': data['GPA']?.toString() ?? '',
        'gender': _getGenderString(data['gender']),
      };
      
      // Extract experience data
      final experienceData = {
        'projects': data['projects'] ?? [],
        'workshops': data['workshops'] ?? [],
        'clubs': data['clubs'] ?? [],
        'volunteering': data['volunteering'] ?? [],
      };
      
      return {
        'profile': profileInfo,
        'experience': experienceData,
      };
    } catch (e) {
      print('Error fetching user data: $e');
      rethrow;
    }
  }

  /// Helper to get major as string
  String _getMajorString(dynamic major) {
    if (major == null) return '';
    if (major is String) return major;
    if (major is List && major.isNotEmpty) return major[0].toString();
    return '';
  }

  /// Helper to get gender as string
  String _getGenderString(dynamic gender) {
    if (gender == null) return '';
    if (gender is String) return gender;
    if (gender is List && gender.isNotEmpty) return gender[0].toString();
    return '';
  }

  /// Generate CV using OpenAI
  Future<String> generateCV() async {
    try {
      // Fetch all user data
      final allData = await fetchAllUserData();
      final profile = allData['profile'] as Map<String, dynamic>;
      final experience = allData['experience'] as Map<String, dynamic>;
      
      // Build prompt
      final prompt = _buildPrompt(profile, experience);
      
      // Call OpenAI API
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': '''You are a professional CV writer. Create well-formatted, professional CVs following these rules:

STRUCTURE:
1. Always start with the person's full name as the title.
2. Contact information (email) must be on the second line.
3. Create a new section titled "PROFESSIONAL SUMMARY" immediately after the contact information. 
   - This section must contain 2–3 concise sentences describing the candidate's background, strengths, and interests.
   - It must always appear as its own section, separate from Education.
4. Then add an "EDUCATION" section.
   - This section must include only Major and GPA (formatted as "Major: [major] | GPA: [value]").
   - Do NOT include level or student ID.
5. Only include other sections that have data (Projects, Workshops, Clubs, Volunteering).


FORMATTING:
- Use clear section headings in ALL CAPS
- Use bullet points for items within sections
- Do NOT include any links or URLs
- Keep it professional and concise
- No markdown symbols in the final output (no **, ##, etc.)
- Make each bullet point impactful but brief
- FOR CLUBS: ALWAYS include hours in format "ClubName | Role | X hours"
- FOR VOLUNTEERING: ALWAYS include hours in format "Title | X hours"
- ALWAYS include hours for clubs and volunteering in format "Title | Role | X hours" or "Title | X hours"

DESCRIPTION HANDLING (CRITICAL):
- If user provided a description: REWRITE it professionally using different words each time, make it concise (1-2 lines), focus on impact and achievements
- If NO description provided: CREATE a professional description based on:
  * The title/name of the activity
  * Role (if provided)
  * Organization (if provided)
  * Hours/duration (if provided)
  * Certificate information (implies completion and skill development)
  * Make it achievement-focused and highlight transferable skills
- NEVER copy descriptions word-for-word from the user input
- Each regeneration MUST produce VARIED descriptions with completely different wording and phrasing
- Use diverse action verbs: developed, led, implemented, coordinated, contributed, designed, orchestrated, spearheaded, facilitated, executed, managed, etc.
- Emphasize different skills each time: teamwork, leadership, technical skills, communication, problem-solving, innovation, collaboration, analytical thinking
- Vary sentence structure and focus areas
- Keep descriptions between 1-2 concise, impactful sentences maximum
- Make every word count - eliminate fluff and focus on concrete achievements'''
            },
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'max_tokens': 2500,
          'temperature': 0.9,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final cvContent = data['choices'][0]['message']['content'];
        
        // Save to Firebase
        await _saveCVToFirebase(cvContent);
        
        return cvContent;
      } else {
        throw Exception('Failed to generate CV: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error generating CV: $e');
    }
  }

  /// Build prompt for OpenAI
  String _buildPrompt(Map<String, dynamic> profile, Map<String, dynamic> experience) {
    final buffer = StringBuffer();
    
    buffer.writeln('Create a professional CV with the following information:');
    buffer.writeln();
    
    // Personal Information - ALWAYS REQUIRED
    buffer.writeln('=== REQUIRED INFORMATION (MUST INCLUDE) ===');
    buffer.writeln('Full Name: ${profile['FName']} ${profile['LName']}');
    buffer.writeln('Email: ${profile['email']}');
    
    // Education - ALWAYS REQUIRED
    buffer.writeln();
    buffer.writeln('=== EDUCATION (MUST INCLUDE) ===');
    if (profile['major'] != null && profile['major'].toString().isNotEmpty) {
      buffer.writeln('Major: ${profile['major']}');
    }
    if (profile['GPA'] != null && profile['GPA'].toString().isNotEmpty) {
      buffer.writeln('GPA: ${profile['GPA']}');
    }
    
    buffer.writeln();
    buffer.writeln('=== OPTIONAL SECTIONS (Include only if data exists) ===');
    buffer.writeln();
    
    // Projects
    final projects = experience['projects'] as List;
    if (projects.isNotEmpty) {
      buffer.writeln('--- PROJECTS SECTION (${projects.length} total) ---');
      for (var i = 0; i < projects.length; i++) {
        var project = projects[i];
        buffer.writeln('Project ${i + 1}:');
        buffer.writeln('  Title: ${project['title'] ?? 'Untitled Project'}');
        if (project['organization'] != null && project['organization'].toString().isNotEmpty) {
          buffer.writeln('  Organization: ${project['organization']}');
        }
        if (project['startDate'] != null || project['endDate'] != null) {
          final start = project['startDate'] ?? 'N/A';
          final end = project['endDate'] ?? 'Present';
          buffer.writeln('  Duration: $start - $end');
        }
        if (project['description'] != null && project['description'].toString().isNotEmpty) {
          buffer.writeln('  User Description (REWRITE THIS - DO NOT COPY): ${project['description']}');
        } else {
          buffer.writeln('  (NO description provided - CREATE ONE based on title, organization, and duration)');
        }
        buffer.writeln('  Has Certificate: ${project['certificateUrl'] != null ? 'Yes (completed and documented)' : 'No'}');
        buffer.writeln();
        
      }
    }
    
    // Workshops
    final workshops = experience['workshops'] as List;
    if (workshops.isNotEmpty) {
      buffer.writeln('--- WORKSHOPS & TRAINING SECTION (${workshops.length} total) ---');
      for (var i = 0; i < workshops.length; i++) {
        var workshop = workshops[i];
        buffer.writeln('Workshop ${i + 1}:');
        buffer.writeln('  Title: ${workshop['title'] ?? 'Untitled Workshop'}');
        if (workshop['organization'] != null && workshop['organization'].toString().isNotEmpty) {
          buffer.writeln('  Organization: ${workshop['organization']}');
        }
        if (workshop['year'] != null) {
          buffer.writeln('  Year: ${workshop['year']}');
        }
        if (workshop['description'] != null && workshop['description'].toString().isNotEmpty) {
          buffer.writeln('  User Description (REWRITE THIS - DO NOT COPY): ${workshop['description']}');
        } else {
          buffer.writeln('  (NO description provided - CREATE ONE based on title and organization)');
        }
      }
    }
    
    // Clubs - ALWAYS SHOW HOURS IN CV
    final clubs = experience['clubs'] as List;
    if (clubs.isNotEmpty) {
      buffer.writeln('--- STUDENT CLUBS & ORGANIZATIONS SECTION (${clubs.length} total) ---');
      for (var i = 0; i < clubs.length; i++) {
        var club = clubs[i];
        buffer.writeln('Club ${i + 1}:');
        buffer.writeln('  Title: ${club['title'] ?? 'Club Activity'}');
        if (club['organization'] != null && club['organization'].toString().isNotEmpty) {
          buffer.writeln('  Organization: ${club['organization']}');
        }
        if (club['role'] != null && club['role'].toString().isNotEmpty) {
          buffer.writeln('  Role: ${club['role']}');
        }
        if (club['hours'] != null && club['hours'].toString().isNotEmpty) {
          buffer.writeln('  Participation Hours: ${club['hours']} (MUST DISPLAY IN CV)');
        }
        if (club['description'] != null && club['description'].toString().isNotEmpty) {
          buffer.writeln('  User Description (REWRITE THIS - DO NOT COPY): ${club['description']}');
        } else {
          buffer.writeln('  (NO description provided - CREATE ONE based on title, role, and hours)');
        }
        buffer.writeln('  Has Certificate: ${club['certificateUrl'] != null ? 'Yes (documented participation)' : 'No'}');
        buffer.writeln();
      }
    }
    
    // Volunteering - ALWAYS SHOW HOURS IN CV
    final volunteering = experience['volunteering'] as List;
    if (volunteering.isNotEmpty) {
      buffer.writeln('--- VOLUNTEERING EXPERIENCE SECTION (${volunteering.length} total) ---');
      for (var i = 0; i < volunteering.length; i++) {
        var volunteer = volunteering[i];
        buffer.writeln('Volunteering ${i + 1}:');
        final title = volunteer['title'] ?? 'Volunteer Work';
        buffer.writeln('  Title: $title');
        if (volunteer['organization'] != null && volunteer['organization'].toString().isNotEmpty) {
          buffer.writeln('  Organization: ${volunteer['organization']}');
        }
        if (volunteer['hours'] != null && volunteer['hours'].toString().isNotEmpty) {
          buffer.writeln('  Hours: ${volunteer['hours']} (MUST DISPLAY IN CV)');
        }
        if (volunteer['description'] != null && volunteer['description'].toString().isNotEmpty) {
          buffer.writeln('  User Description (REWRITE THIS - DO NOT COPY): ${volunteer['description']}');
        } else {
          buffer.writeln('  (NO description provided - CREATE ONE based on title, organization, and hours)');
        }
        buffer.writeln('  Has Certificate: ${volunteer['certificateUrl'] != null ? 'Yes (verified service)' : 'No'}');
        buffer.writeln();
      }
    }
    
    buffer.writeln();
    buffer.writeln('=== CRITICAL INSTRUCTIONS FOR CV GENERATION ===');
    buffer.writeln('1. MUST START WITH: Full name as title, then email on next line');
    buffer.writeln('2. MUST INCLUDE: Education section with ONLY Major and GPA');
    buffer.writeln('3. ADD: A brief professional summary/introduction (2-3 sentences) after education');
    buffer.writeln('4. ONLY INCLUDE sections that have data (if no projects, skip Projects section entirely)');
    buffer.writeln('5. Use ALL CAPS for section headings (EDUCATION, PROJECTS, WORKSHOPS, etc.)');
    buffer.writeln('6. FOR CLUBS: ALWAYS include hours in the format "ClubName | Role | X hours"');
    buffer.writeln('7. FOR VOLUNTEERING: ALWAYS include hours in the format "Title | X hours"');
    buffer.writeln('8. FOR EACH ITEM WITH DESCRIPTION:');
    buffer.writeln('   - COMPLETELY REWRITE the description in your own words');
    buffer.writeln('   - Use DIFFERENT phrasing and vocabulary than the user provided');
    buffer.writeln('   - Make it professional, achievement-focused, and concise (1-2 lines max)');
    buffer.writeln('   - Focus on impact, skills gained, and concrete achievements');
    buffer.writeln('9. FOR EACH ITEM WITHOUT DESCRIPTION:');
    buffer.writeln('   - CREATE a professional description from scratch');
    buffer.writeln('   - Base it on: title, role, organization, hours/duration, certificate status');
    buffer.writeln('   - Infer skills and achievements that would logically come from this activity');
    buffer.writeln('   - Make it specific and impactful (1-2 lines max)');
    buffer.writeln('10. VARIATION IS KEY:');
    buffer.writeln('   - Each time you regenerate, use DIFFERENT action verbs and sentence structures');
    buffer.writeln('   - Emphasize DIFFERENT aspects (e.g., technical skills vs leadership vs teamwork)');
    buffer.writeln('   - Never produce identical descriptions across regenerations');
    buffer.writeln('11. DO NOT include any links or URLs');
    buffer.writeln('12. NO markdown formatting symbols in output (no **, ##, _)');
    buffer.writeln('13. Format should be clean and ready for PDF conversion');
    buffer.writeln('14. Make bullet points short, powerful, and achievement-oriented');
    buffer.writeln('15. If certificate exists, subtly highlight completion/certification in description');
    buffer.writeln('=== GIBBERISH & INVALID INPUT DETECTION ===');
    buffer.writeln('16. QUALITY CHECK:');
    buffer.writeln('   - If any user input appears to be gibberish, random characters, keyboard mashing, or meaningless text:');
    buffer.writeln('     * Examples: "gjdjsjajajaj", "asdfasdf", "qwerty", "aaaaaaa", "12345", "test test test"');
    buffer.writeln('     * DO NOT include that item in the CV');
    buffer.writeln('     * Skip that entry entirely as if it doesn\'t exist');
    buffer.writeln('   - Only include items with meaningful, coherent information');
    buffer.writeln('   - If a title/name looks valid but description is gibberish, create a professional description');
    buffer.writeln('   - If BOTH title and description are gibberish, omit the entire item');
    buffer.writeln('   - If ALL items in a section are gibberish, omit the entire section');
    buffer.writeln('   - Maintain professional standards - only include legitimate content');

    
    return buffer.toString();
  }

  /// Save generated CV to Firebase
  Future<void> _saveCVToFirebase(String cvContent) async {
    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        throw Exception('Unable to identify user');
      }

      await _firestore.collection('users').doc(docId).update({
        'generatedCV': cvContent,
        'cvGeneratedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving CV: $e');
      rethrow;
    }
  }

  /// Get saved CV from Firebase
  Future<String?> getSavedCV() async {
    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        return null;
      }

      final doc = await _firestore.collection('users').doc(docId).get();
      
      if (doc.exists && doc.data()?['generatedCV'] != null) {
        return doc.data()?['generatedCV'] as String;
      }
      
      return null;
    } catch (e) {
      print('Error getting saved CV: $e');
      return null;
    }
  }

  /// Check if user has minimum data to generate CV
  bool hasMinimumData(Map<String, dynamic> experience) {
    final projects = experience['projects'] as List;
    final workshops = experience['workshops'] as List;
    final clubs = experience['clubs'] as List;
    final volunteering = experience['volunteering'] as List;

    return projects.isNotEmpty || workshops.isNotEmpty || 
           clubs.isNotEmpty || volunteering.isNotEmpty;
  }
}