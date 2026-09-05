import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String _baseUrl = const String.fromEnvironment(
    'SENTRIFIRE_API_URL',
    defaultValue: 'http://192.168.1.50:8000',
  );
  String? accessToken;

  String get baseUrl => _baseUrl;
  Map<String, String> get authorizedHeaders => {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  set baseUrl(String value) {
    final String cleaned = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      throw const ApiException('Server address must begin with http:// or https://.');
    }
    _baseUrl = cleaned;
  }

  Uri _uri(String path, [Map<String, String?>? query]) {
    final Map<String, String> cleanQuery = {
      for (final MapEntry<String, String?> entry in (query ?? const {}).entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    return Uri.parse('$_baseUrl$path').replace(queryParameters: cleanQuery.isEmpty ? null : cleanQuery);
  }

  Map<String, String> _headers({bool authorized = true}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (authorized && accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String?>? query,
    bool authorized = true,
  }) async {
    final Uri uri = _uri(path, query);
    final String? encodedBody = body == null ? null : jsonEncode(body);
    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: _headers(authorized: authorized)).timeout(const Duration(seconds: 12));
          break;
        case 'POST':
          response = await _client
              .post(uri, headers: _headers(authorized: authorized), body: encodedBody)
              .timeout(const Duration(seconds: 12));
          break;
        case 'PUT':
          response = await _client
              .put(uri, headers: _headers(authorized: authorized), body: encodedBody)
              .timeout(const Duration(seconds: 12));
          break;
        default:
          throw ApiException('Unsupported request method: $method');
      }
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('Cannot connect to SentriFire server: $error');
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Request failed (${response.statusCode}).';
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final dynamic result = await _send(
      'POST',
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
      authorized: false,
    );
    return (result as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final dynamic result = await _send(
      'POST',
      '/api/v1/auth/refresh',
      body: {'refresh_token': refreshToken},
      authorized: false,
    );
    return (result as Map).cast<String, dynamic>();
  }

  Future<void> logout(String refreshToken) async {
    await _send(
      'POST',
      '/api/v1/auth/logout',
      body: {'refresh_token': refreshToken},
      authorized: false,
    );
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _send(
      'POST',
      '/api/v1/auth/change-password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  Future<Map<String, dynamic>> bootstrap() async {
    final dynamic result = await _send('GET', '/api/v1/bootstrap');
    return (result as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> events({
    int limit = 100,
    String? cameraId,
    String? level,
    bool activeOnly = false,
  }) async {
    final dynamic result = await _send(
      'GET',
      '/api/v1/events',
      query: {
        'limit': '$limit',
        'camera_id': cameraId,
        'level': level,
        'active_only': '$activeOnly',
      },
    );
    return (result as List).map((dynamic item) => (item as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> updateAlarmSettings(Map<String, dynamic> settings) async {
    final dynamic result = await _send('PUT', '/api/v1/alarm/settings', body: settings);
    return (result as Map).cast<String, dynamic>();
  }

  Future<void> activateAlarm() => _send('POST', '/api/v1/alarm/activate').then((_) {});
  Future<void> cancelManualAlarm() => _send('POST', '/api/v1/alarm/cancel-manual').then((_) {});
  Future<void> cancelSilence() => _send('POST', '/api/v1/alarm/cancel-silence').then((_) {});

  Future<void> silenceAlarm(int minutes) => _send(
        'POST',
        '/api/v1/alarm/silence',
        body: {'minutes': minutes},
      ).then((_) {});

  Future<void> testAlarm({int seconds = 5}) => _send(
        'POST',
        '/api/v1/alarm/test',
        body: {'seconds': seconds},
      ).then((_) {});

  Future<void> acknowledgeEvent(String eventId) =>
      _send('POST', '/api/v1/events/$eventId/acknowledge').then((_) {});

  Future<void> markFalseAlarm(String eventId, String reason) => _send(
        'POST',
        '/api/v1/events/$eventId/false-alarm',
        body: {'reason': reason},
      ).then((_) {});

  Future<void> registerDeviceToken(String token, {String platform = 'android'}) => _send(
        'POST',
        '/api/v1/devices/register',
        body: {'token': token, 'platform': platform},
      ).then((_) {});

  WebSocketChannel openStatusSocket() {
    final String? token = accessToken;
    if (token == null) throw const ApiException('No active session.');
    final Uri httpUri = Uri.parse(_baseUrl);
    final Uri socketUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/status',
      queryParameters: {'token': token},
    );
    return WebSocketChannel.connect(socketUri);
  }

  void close() => _client.close();
}
