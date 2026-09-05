import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';
import 'api_client.dart';

class LoginResult {
  const LoginResult({required this.owner, required this.remembered});
  final OwnerAccount owner;
  final bool remembered;
}

class PinVerificationResult {
  const PinVerificationResult({
    required this.success,
    required this.sessionInvalidated,
    required this.offlineAccess,
    this.message,
  });

  final bool success;
  final bool sessionInvalidated;
  final bool offlineAccess;
  final String? message;
}

class AuthService {
  AuthService(this.api);

  final ApiClient api;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final Pbkdf2 _pinDerivation = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );

  static const String _accessKey = 'session_access_token';
  static const String _refreshKey = 'session_refresh_token';
  static const String _ownerKey = 'session_owner';
  static const String _pinSaltKey = 'pin_salt';
  static const String _pinHashKey = 'pin_hash';
  static const String _serverUrlKey = 'server_url';

  OwnerAccount? owner;
  Future<void>? _refreshing;

  Future<void> initialize() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? savedUrl = preferences.getString(_serverUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      api.baseUrl = savedUrl;
    }
    api.accessToken = await _secure.read(key: _accessKey);
    final String? ownerJson = await _secure.read(key: _ownerKey);
    if (ownerJson != null) {
      try {
        owner = OwnerAccount.fromJson((jsonDecode(ownerJson) as Map).cast<String, dynamic>());
      } catch (_) {
        owner = null;
      }
    }
  }

  Future<void> saveServerUrl(String value) async {
    api.baseUrl = value;
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(_serverUrlKey, api.baseUrl);
  }

  Future<bool> hasRememberedSession() async {
    return await _secure.read(key: _refreshKey) != null && owner != null;
  }

  Future<bool> hasPin() async {
    return await _secure.read(key: _pinHashKey) != null && await _secure.read(key: _pinSaltKey) != null;
  }

  Future<LoginResult> login({
    required String email,
    required String password,
    required bool rememberDevice,
  }) async {
    final Map<String, dynamic> response = await api.login(email.trim(), password);
    final OwnerAccount account = OwnerAccount.fromJson(
      (response['owner'] as Map).cast<String, dynamic>(),
    );
    owner = account;
    api.accessToken = response['access_token']?.toString();
    if (rememberDevice) {
      await _secure.write(key: _accessKey, value: api.accessToken);
      await _secure.write(key: _refreshKey, value: response['refresh_token']?.toString());
      await _secure.write(key: _ownerKey, value: jsonEncode(account.toJson()));
    } else {
      await _secure.delete(key: _accessKey);
      await _secure.delete(key: _refreshKey);
      await _secure.delete(key: _ownerKey);
      await _secure.delete(key: _pinSaltKey);
      await _secure.delete(key: _pinHashKey);
    }
    return LoginResult(owner: account, remembered: rememberDevice);
  }

  Future<void> setupPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const ApiException('PIN must contain exactly four numbers.');
    }
    final Random random = Random.secure();
    final List<int> salt = List<int>.generate(16, (_) => random.nextInt(256));
    final List<int> digest = await _derivePin(pin, salt);
    await _secure.write(key: _pinSaltKey, value: base64Encode(salt));
    await _secure.write(key: _pinHashKey, value: base64Encode(digest));
  }

  Future<List<int>> _derivePin(String pin, List<int> salt) async {
    final SecretKey key = await _pinDerivation.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  Future<bool> _pinMatches(String pin) async {
    final String? saltText = await _secure.read(key: _pinSaltKey);
    final String? hashText = await _secure.read(key: _pinHashKey);
    if (saltText == null || hashText == null || !RegExp(r'^\d{4}$').hasMatch(pin)) return false;
    final List<int> candidate = await _derivePin(pin, base64Decode(saltText));
    return _constantTimeEquals(candidate, base64Decode(hashText));
  }

  bool _constantTimeEquals(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    int difference = 0;
    for (int index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }

  Future<PinVerificationResult> unlockWithPin(String pin, int failedAttempts) async {
    if (!await _pinMatches(pin)) {
      if (failedAttempts + 1 >= 5) {
        await clearLocalSession();
        return const PinVerificationResult(
          success: false,
          sessionInvalidated: true,
          offlineAccess: false,
          message: 'Too many incorrect attempts. Sign in with your password again.',
        );
      }
      return PinVerificationResult(
        success: false,
        sessionInvalidated: false,
        offlineAccess: false,
        message: 'Incorrect PIN. ${4 - failedAttempts} attempts remaining.',
      );
    }

    try {
      await refreshSession();
      return const PinVerificationResult(success: true, sessionInvalidated: false, offlineAccess: false);
    } on ApiException catch (error) {
      if (owner != null) {
        return PinVerificationResult(
          success: true,
          sessionInvalidated: false,
          offlineAccess: true,
          message: 'Opened offline. Live status will refresh when the Pi is reachable.',
        );
      }
      return PinVerificationResult(
        success: false,
        sessionInvalidated: true,
        offlineAccess: false,
        message: error.message,
      );
    }
  }

  Future<PinVerificationResult> unlockWithBiometrics() async {
    try {
      final bool supported = await _localAuth.isDeviceSupported();
      if (!supported) {
        return const PinVerificationResult(
          success: false,
          sessionInvalidated: false,
          offlineAccess: false,
          message: 'Biometric or device authentication is not available.',
        );
      }
      final bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Unlock SentriFire for emergency access',
        persistAcrossBackgrounding: true,
      );
      if (!authenticated) {
        return const PinVerificationResult(
          success: false,
          sessionInvalidated: false,
          offlineAccess: false,
          message: 'Authentication was not completed.',
        );
      }
      try {
        await refreshSession();
        return const PinVerificationResult(success: true, sessionInvalidated: false, offlineAccess: false);
      } on ApiException {
        if (owner != null) {
          return const PinVerificationResult(
            success: true,
            sessionInvalidated: false,
            offlineAccess: true,
            message: 'Opened offline. Live status will refresh when available.',
          );
        }
        rethrow;
      }
    } catch (error) {
      return PinVerificationResult(
        success: false,
        sessionInvalidated: false,
        offlineAccess: false,
        message: 'Authentication failed: $error',
      );
    }
  }

  Future<void> refreshSession() {
    final Future<void>? existing = _refreshing;
    if (existing != null) return existing;
    final Future<void> operation = _performRefresh();
    _refreshing = operation;
    return operation.whenComplete(() {
      if (identical(_refreshing, operation)) _refreshing = null;
    });
  }

  Future<void> _performRefresh() async {
    final String? refreshToken = await _secure.read(key: _refreshKey);
    if (refreshToken == null) throw const ApiException('No remembered session.');
    final Map<String, dynamic> response = await api.refresh(refreshToken);
    api.accessToken = response['access_token']?.toString();
    owner = OwnerAccount.fromJson((response['owner'] as Map).cast<String, dynamic>());
    await _secure.write(key: _accessKey, value: api.accessToken);
    await _secure.write(key: _refreshKey, value: response['refresh_token']?.toString());
    await _secure.write(key: _ownerKey, value: jsonEncode(owner!.toJson()));
  }

  Future<void> changePin(String currentPin, String newPin) async {
    if (!await _pinMatches(currentPin)) throw const ApiException('Current PIN is incorrect.');
    await setupPin(newPin);
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await api.changePassword(currentPassword, newPassword);
    await clearLocalSession();
  }

  Future<void> logout() async {
    final String? refreshToken = await _secure.read(key: _refreshKey);
    if (refreshToken != null) {
      try {
        await api.logout(refreshToken);
      } catch (_) {
        // Local logout must still succeed when the Pi is offline.
      }
    }
    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    api.accessToken = null;
    owner = null;
    for (final String key in [_accessKey, _refreshKey, _ownerKey, _pinSaltKey, _pinHashKey]) {
      await _secure.delete(key: key);
    }
  }
}
