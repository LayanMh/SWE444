import 'dart:async';
import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class MicrosoftAccount {
  const MicrosoftAccount({
    required this.id,
    required this.displayName,
    required this.email,
    required this.accessToken,
  });

  final String id;
  final String displayName;
  final String email;
  final String accessToken;

  MicrosoftAccount copyWith({String? accessToken}) {
    return MicrosoftAccount(
      id: id,
      displayName: displayName,
      email: email,
      accessToken: accessToken ?? this.accessToken,
    );
  }
}

class MicrosoftAuthService {
  MicrosoftAuthService._();

  static final FlutterAppAuth _appAuth = FlutterAppAuth();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const String _refreshTokenStorageKey = 'microsoft_auth_refresh_token';
  static const String _accountStorageKey = 'microsoft_auth_account';
  static const String _accessTokenExpiryStorageKey = 'microsoft_auth_access_token_expiry';
  static bool _sessionLoadedFromStorage = false;

  static const String _clientId = 'adba7fb2-f6d3-4fef-950d-e0743a720212';
  static const String _tenantId = '19df06c3-3fcd-4947-809f-064684abf608';
  static const String _redirectUri = 'msauth://com.example.absherk/redirect';

  static const List<String> _scopes = <String>[
    'openid',
    'profile',
    'email',
    'offline_access',
    'User.Read',
    'Calendars.Read',
    'Calendars.ReadWrite',
  ];

  static List<String> get scopes => _scopes;

  static MicrosoftAccount? _account;
  static String? _refreshToken;
  static DateTime? _accessTokenExpiry;

  static AuthorizationServiceConfiguration get _configuration =>
      AuthorizationServiceConfiguration(
        authorizationEndpoint:
            'https://login.microsoftonline.com/$_tenantId/oauth2/v2.0/authorize',
        tokenEndpoint:
            'https://login.microsoftonline.com/$_tenantId/oauth2/v2.0/token',
      );

  static MicrosoftAccount? get currentAccount => _account;

  static Future<MicrosoftAccount?> ensureSignedIn({
    bool interactive = true,
    bool forcePrompt = false,
  }) async {
    await _ensureSessionLoaded();

    if (_hasValidAccessToken) {
      return _account;
    }

    final refreshed = await _refreshSession();
    if (refreshed != null) {
      return refreshed;
    }

    if (!interactive) {
      return null;
    }

    return _interactiveSignIn(forcePrompt: forcePrompt);
  }

  static Future<void> signOut() async {
    _account = null;
    _refreshToken = null;
    _accessTokenExpiry = null;
    await _clearPersistedSession();
  }

  static bool get _hasValidAccessToken {
    return _account != null &&
        _accessTokenExpiry != null &&
        _accessTokenExpiry!
            .isAfter(DateTime.now().add(const Duration(seconds: 30)));
  }

  static Future<void> _ensureSessionLoaded() async {
    if (_sessionLoadedFromStorage) {
      return;
    }

    _sessionLoadedFromStorage = true;

    final storedRefreshToken =
        await _secureStorage.read(key: _refreshTokenStorageKey);
    final storedAccountJson =
        await _secureStorage.read(key: _accountStorageKey);
    final storedAccessTokenExpiryIso =
        await _secureStorage.read(key: _accessTokenExpiryStorageKey);

    if (storedRefreshToken == null || storedAccountJson == null) {
      return;
    }

    try {
      final decoded = jsonDecode(storedAccountJson);
      if (decoded is Map<String, dynamic>) {
        _account = MicrosoftAccount(
          id: decoded['id'] as String? ?? '',
          displayName: decoded['displayName'] as String? ?? '',
          email: decoded['email'] as String? ?? '',
          accessToken: decoded['accessToken'] as String? ?? '',
        );
      } else {
        await _clearPersistedSession();
        return;
      }
    } on Object {
      await _clearPersistedSession();
      return;
    }

    _refreshToken = storedRefreshToken;
    _accessTokenExpiry = storedAccessTokenExpiryIso != null
        ? DateTime.tryParse(storedAccessTokenExpiryIso)
        : null;
  }

  static Future<void> _persistSession() async {
    final futures = <Future<void>>[];

    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      futures.add(_secureStorage.write(
        key: _refreshTokenStorageKey,
        value: _refreshToken,
      ));
    } else {
      futures.add(_secureStorage.delete(key: _refreshTokenStorageKey));
    }

    if (_account != null) {
      final payload = jsonEncode(<String, String>{
        'id': _account!.id,
        'displayName': _account!.displayName,
        'email': _account!.email,
        'accessToken': _account!.accessToken,
      });
      futures.add(_secureStorage.write(
        key: _accountStorageKey,
        value: payload,
      ));
    } else {
      futures.add(_secureStorage.delete(key: _accountStorageKey));
    }

    if (_accessTokenExpiry != null) {
      futures.add(_secureStorage.write(
        key: _accessTokenExpiryStorageKey,
        value: _accessTokenExpiry!.toIso8601String(),
      ));
    } else {
      futures.add(_secureStorage.delete(key: _accessTokenExpiryStorageKey));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    _sessionLoadedFromStorage = true;
  }

  static Future<void> _clearPersistedSession() async {
    await Future.wait(<Future<void>>[
      _secureStorage.delete(key: _refreshTokenStorageKey),
      _secureStorage.delete(key: _accountStorageKey),
      _secureStorage.delete(key: _accessTokenExpiryStorageKey),
    ]);
    _sessionLoadedFromStorage = false;
  }

  static Future<MicrosoftAccount?> _refreshSession() async {
    if (_refreshToken == null) {
      return null;
    }

    try {
      final response = await _appAuth.token(
        TokenRequest(
          _clientId,
          _redirectUri,
          refreshToken: _refreshToken,
          scopes: _scopes,
          serviceConfiguration: _configuration,
        ),
      );

      return _updateSession(response);
    } on Exception {
      await signOut();
      return null;
    }
  }

  static Future<MicrosoftAccount?> _interactiveSignIn({
    bool forcePrompt = false,
  }) async {
    final List<String>? promptValues =
        forcePrompt ? <String>['login'] : null;

    final response = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _clientId,
        _redirectUri,
        scopes: _scopes,
        serviceConfiguration: _configuration,
        promptValues: promptValues,
      ),
    );

    return _updateSession(response, fetchProfile: true);
  }

  static Future<MicrosoftAccount?> _updateSession(
    TokenResponse tokens, {
    bool fetchProfile = false,
  }) async {
    final accessToken = tokens.accessToken;
    if (accessToken == null) {
      return null;
    }

    _refreshToken = tokens.refreshToken ?? _refreshToken;
    _accessTokenExpiry = tokens.accessTokenExpirationDateTime;

    final shouldFetchProfile = fetchProfile || _account == null;

    if (!shouldFetchProfile && _account != null) {
      _account = _account!.copyWith(accessToken: accessToken);
      await _persistSession();
      return _account;
    }

    final profile = await _fetchProfile(accessToken);

    final displayName = (profile['displayName'] as String?)?.trim();
    final principalName = (profile['userPrincipalName'] as String?)?.trim();
    final mail = (profile['mail'] as String?)?.trim();

    _account = MicrosoftAccount(
      id: (profile['id'] as String?) ?? '',
      displayName: (displayName?.isNotEmpty ?? false)
          ? displayName!
          : (principalName ?? ''),
      email: (mail?.isNotEmpty ?? false) ? mail! : (principalName ?? ''),
      accessToken: accessToken,
    );

    await _persistSession();
    return _account;
  }

  static Future<Map<String, dynamic>> _fetchProfile(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me'),
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load Microsoft profile (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Unexpected profile response shape');
  }

    /// Public helper to update session after external sign-in (e.g. SignInScreen)
  static Future<void> updateSessionFromSignIn({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
    required Map<String, dynamic> profile,
  }) async {
    _refreshToken = refreshToken ?? _refreshToken;
    _accessTokenExpiry = expiry ?? DateTime.now().add(const Duration(hours: 1));

    _account = MicrosoftAccount(
      id: profile['microsoftId'] ?? '',
      displayName: profile['displayName'] ?? '',
      email: profile['email'] ?? '',
      accessToken: accessToken,
    );

    await _persistSession();
  }
}






