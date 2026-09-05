import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_client.dart';

class NotificationService {
  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  final StreamController<Map<String, dynamic>> _messages = StreamController.broadcast();
  final List<Map<String, dynamic>> _pendingMessages = <Map<String, dynamic>>[];
  bool _configured = false;

  bool get configured => _configured;
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  List<Map<String, dynamic>> takePendingMessages() {
    final List<Map<String, dynamic>> messages = List<Map<String, dynamic>>.from(_pendingMessages);
    _pendingMessages.clear();
    return messages;
  }

  Future<void> initialize() async {
    if ([_apiKey, _appId, _senderId, _projectId].any((String value) => value.isEmpty)) {
      return;
    }
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      _configured = true;
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      FirebaseMessaging.onMessage.listen(_publish);
      FirebaseMessaging.onMessageOpenedApp.listen(_publish);
      final RemoteMessage? initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _publish(initial);
    } catch (_) {
      _configured = false;
    }
  }

  void _publish(RemoteMessage message) {
    final Map<String, dynamic> payload = {
      ...message.data,
      'title': message.notification?.title,
      'body': message.notification?.body,
    };
    if (_messages.hasListener) {
      _messages.add(payload);
    } else {
      _pendingMessages.add(payload);
    }
  }

  Future<void> registerDevice(ApiClient api) async {
    if (!_configured) return;
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) await api.registerDeviceToken(token);
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (String newToken) => api.registerDeviceToken(newToken),
      );
    } catch (_) {
      // Registration will be retried on the next successful app session.
    }
  }

  Future<void> dispose() async {
    await _messages.close();
  }
}
