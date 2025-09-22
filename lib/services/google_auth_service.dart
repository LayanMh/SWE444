import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      calendar.CalendarApi.calendarScope,
      calendar.CalendarApi.calendarEventsScope,
      calendar.CalendarApi.calendarReadonlyScope,
      'email',
    ],
  );

  static Future<GoogleSignInAccount?> ensureSignedIn({
    bool interactive = true,
  }) async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();

    if (account != null || !interactive) {
      return account;
    }

    try {
      account = await _googleSignIn.signIn();
      return account;
    } on Exception {
      rethrow;
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.disconnect();
    await _googleSignIn.signOut();
  }

  static GoogleSignIn get instance => _googleSignIn;
}
