import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIService {
  // Replace with your OpenAI API key
  static const String _apiKey = 'YOUR_OPENAI_API_KEY_HERE';
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';

  Future<String> generateCV(Map<String, dynamic> experienceData, Map<String, dynamic> userData) async {
    try {
      // Prepare the prompt with user data
      final prompt = _buildPrompt(experienceData, userData);

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini', // or 'gpt-4' for better quality
          'messages': [
            {
              'role': 'system',
              'content': 'You are a professional CV writer. Create well-formatted, professional CVs in markdown format.'
            },
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'max_tokens': 2000,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception('Failed to generate CV: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error generating CV: $e');
    }
  }

  String _buildPrompt(Map<String, dynamic> experienceData, Map<String, dynamic> userData) {
    final buffer = StringBuffer();
    
    buffer.writeln('Create a professional CV in markdown format with the following information:');
    buffer.writeln();
    
    // Personal Information
    buffer.writeln('## Personal Information');
    buffer.writeln('Name: ${userData['fullName'] ?? 'N/A'}');
    buffer.writeln('Email: ${userData['email'] ?? 'N/A'}');
    if (userData['phone'] != null) buffer.writeln('Phone: ${userData['phone']}');
    if (userData['bio'] != null) buffer.writeln('Bio: ${userData['bio']}');
    buffer.writeln();

    // Projects
    if (experienceData['projects'] != null && (experienceData['projects'] as List).isNotEmpty) {
      buffer.writeln('## Projects');
      for (var project in experienceData['projects']) {
        buffer.writeln('- **${project['title']}**');
        if (project['organization'] != null) buffer.writeln('  - Organization: ${project['organization']}');
        if (project['startDate'] != null) {
          buffer.writeln('  - Duration: ${project['startDate']} - ${project['endDate'] ?? 'Present'}');
        }
        if (project['description'] != null) buffer.writeln('  - ${project['description']}');
        if (project['link'] != null) buffer.writeln('  - Link: ${project['link']}');
        buffer.writeln();
      }
    }

    // Workshops
    if (experienceData['workshops'] != null && (experienceData['workshops'] as List).isNotEmpty) {
      buffer.writeln('## Workshops & Training');
      for (var workshop in experienceData['workshops']) {
        buffer.writeln('- **${workshop['title']}**');
        if (workshop['organization'] != null) buffer.writeln('  - ${workshop['organization']}');
        if (workshop['year'] != null) buffer.writeln('  - Year: ${workshop['year']}');
        if (workshop['description'] != null) buffer.writeln('  - ${workshop['description']}');
        buffer.writeln();
      }
    }

    // Clubs
    if (experienceData['clubs'] != null && (experienceData['clubs'] as List).isNotEmpty) {
      buffer.writeln('## Student Clubs & Organizations');
      for (var club in experienceData['clubs']) {
        buffer.writeln('- **${club['title']}**');
        if (club['role'] != null) buffer.writeln('  - Role: ${club['role']}');
        if (club['organization'] != null) buffer.writeln('  - ${club['organization']}');
        if (club['hours'] != null) buffer.writeln('  - Hours: ${club['hours']}');
        if (club['description'] != null) buffer.writeln('  - ${club['description']}');
        buffer.writeln();
      }
    }

    // Volunteering
    if (experienceData['volunteering'] != null && (experienceData['volunteering'] as List).isNotEmpty) {
      buffer.writeln('## Volunteering Experience');
      for (var volunteer in experienceData['volunteering']) {
        buffer.writeln('- **${volunteer['title']}**');
        if (volunteer['organization'] != null) buffer.writeln('  - ${volunteer['organization']}');
        if (volunteer['hours'] != null) buffer.writeln('  - Hours: ${volunteer['hours']}');
        if (volunteer['description'] != null) buffer.writeln('  - ${volunteer['description']}');
        buffer.writeln();
      }
    }

    buffer.writeln();
    buffer.writeln('Format this as a professional, well-structured CV with proper sections and formatting.');
    
    return buffer.toString();
  }
}