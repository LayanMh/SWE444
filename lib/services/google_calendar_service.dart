import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:http/http.dart' as http;

class GoogleCalendarService {
  GoogleCalendarService._();

  static Future<List<calendar.Event>> fetchUpcomingEvents(
    GoogleSignInAccount account,
  ) async {
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);

    try {
      final calendarApi = calendar.CalendarApi(client);
      final events = await calendarApi.events.list(
        'primary',
        timeMin: DateTime.now().toUtc(),
        maxResults: 50,
        singleEvents: true,
        orderBy: 'startTime',
      );
      return events.items ?? <calendar.Event>[];
    } finally {
      client.close();
    }
  }

  static Future<void> insertEvent(
    GoogleSignInAccount account,
    calendar.Event event,
  ) async {
    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);

    try {
      final calendarApi = calendar.CalendarApi(client);
      await calendarApi.events.insert(event, 'primary');
    } finally {
      client.close();
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}
