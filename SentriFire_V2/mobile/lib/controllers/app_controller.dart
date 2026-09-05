import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/app_models.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.api,
    required this.auth,
    required this.notifications,
  });

  final ApiClient api;
  final AuthService auth;
  final NotificationService notifications;

  static const String _cacheKey = 'sentrifire_bootstrap_cache_v2';

  List<CameraStatus> cameras = const [];
  List<FireEvent> events = const [];
  AlarmSettings alarmSettings = const AlarmSettings(
    sensitivity: 'balanced',
    advancedConfidence: null,
    sirenEnabled: true,
    notificationsEnabled: true,
    suspectedNotifications: false,
  );
  SystemHealth? systemHealth;
  bool loading = true;
  bool serverReachable = false;
  String? errorMessage;
  String? transientAlert;
  DateTime? lastUpdated;

  Timer? _pollTimer;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  bool _disposed = false;

  OwnerAccount? get owner => auth.owner;
  Map<String, String> get mediaHeaders => api.authorizedHeaders;
  List<FireEvent> get activeEvents => events.where((FireEvent event) => event.active).toList();

  AppAlarmLevel get globalLevel {
    if (cameras.any((CameraStatus camera) => camera.level == AppAlarmLevel.critical)) return AppAlarmLevel.critical;
    if (cameras.any((CameraStatus camera) => camera.level == AppAlarmLevel.confirmed)) return AppAlarmLevel.confirmed;
    if (cameras.any((CameraStatus camera) => camera.level == AppAlarmLevel.suspected)) return AppAlarmLevel.suspected;
    if (cameras.isEmpty || cameras.any((CameraStatus camera) => !camera.online)) return AppAlarmLevel.offline;
    return AppAlarmLevel.normal;
  }

  Future<void> start() async {
    _notificationSubscription = notifications.messages.listen((Map<String, dynamic> message) {
      _handleNotification(message);
    });
    for (final Map<String, dynamic> message in notifications.takePendingMessages()) {
      _handleNotification(message);
    }
    await load();
    await notifications.registerDevice(api);
    _connectSocket();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => refresh(silent: true).catchError((_) {}),
    );
  }

  void _handleNotification(Map<String, dynamic> message) {
    transientAlert = message['body']?.toString() ?? 'New SentriFire alert';
    if (!_disposed) notifyListeners();
    refresh(silent: true).catchError((_) {});
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      await refresh();
    } catch (_) {
      await _loadCache();
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) errorMessage = null;
    try {
      Map<String, dynamic> data;
      try {
        data = await api.bootstrap();
      } on ApiException catch (error) {
        if (error.statusCode == 401) {
          await auth.refreshSession();
          data = await api.bootstrap();
        } else {
          rethrow;
        }
      }
      _applyBootstrap(data);
      serverReachable = true;
      lastUpdated = DateTime.now();
      final SharedPreferences preferences = await SharedPreferences.getInstance();
      await preferences.setString(_cacheKey, jsonEncode(data));
      await preferences.setString('${_cacheKey}_time', lastUpdated!.toIso8601String());
    } catch (error) {
      serverReachable = false;
      if (!silent) errorMessage = error.toString();
      rethrow;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  void _applyBootstrap(Map<String, dynamic> data) {
    final dynamic cameraData = data['cameras'];
    final dynamic eventData = data['events'];
    if (cameraData is List) {
      cameras = cameraData
          .map((dynamic item) => CameraStatus.fromJson((item as Map).cast<String, dynamic>()))
          .toList();
    }
    if (eventData is List) {
      events = eventData
          .map((dynamic item) => FireEvent.fromJson((item as Map).cast<String, dynamic>()))
          .toList();
    }
    if (data['alarm_settings'] is Map) {
      alarmSettings = AlarmSettings.fromJson((data['alarm_settings'] as Map).cast<String, dynamic>());
    }
    if (data['system_health'] is Map) {
      systemHealth = SystemHealth.fromJson((data['system_health'] as Map).cast<String, dynamic>());
    }
  }

  Future<void> _loadCache() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? raw = preferences.getString(_cacheKey);
    if (raw == null) return;
    try {
      _applyBootstrap((jsonDecode(raw) as Map).cast<String, dynamic>());
      lastUpdated = preferences.getString('${_cacheKey}_time') == null
          ? null
          : DateTime.tryParse(preferences.getString('${_cacheKey}_time')!);
    } catch (_) {
      // A broken cache must never prevent the emergency app from opening.
    }
  }

  void _connectSocket() {
    if (_disposed || api.accessToken == null) return;
    _socketSubscription?.cancel();
    _socket?.sink.close();
    try {
      _socket = api.openStatusSocket();
      _socketSubscription = _socket!.stream.listen(
        _handleSocketMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        try {
          _socket?.sink.add('ping');
        } catch (_) {
          _scheduleReconnect();
        }
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _connectSocket);
  }

  void _handleSocketMessage(dynamic raw) {
    try {
      final Map<String, dynamic> message = (jsonDecode(raw.toString()) as Map).cast<String, dynamic>();
      final String type = message['type']?.toString() ?? '';
      final Map<String, dynamic> data = (message['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (type == 'camera_status') {
        final CameraStatus updated = CameraStatus.fromJson(data);
        final List<CameraStatus> next = [...cameras];
        final int index = next.indexWhere((CameraStatus camera) => camera.id == updated.id);
        if (index >= 0) {
          next[index] = updated;
        } else {
          next.add(updated);
        }
        cameras = next;
        serverReachable = true;
        lastUpdated = DateTime.now();
        notifyListeners();
      } else if (type == 'alarm_settings' && data.isNotEmpty) {
        alarmSettings = AlarmSettings.fromJson(data);
        notifyListeners();
      } else if (type == 'event_transition' || type == 'event_updated') {
        refresh(silent: true).catchError((_) {});
      } else if (type == 'bootstrap') {
        if (data['cameras'] is List) {
          cameras = (data['cameras'] as List)
              .map((dynamic item) => CameraStatus.fromJson((item as Map).cast<String, dynamic>()))
              .toList();
        }
        if (data['alarm_settings'] is Map) {
          alarmSettings = AlarmSettings.fromJson((data['alarm_settings'] as Map).cast<String, dynamic>());
        }
        notifyListeners();
      }
    } catch (_) {
      // Polling provides recovery if one socket message is malformed.
    }
  }

  Future<void> saveAlarmSettings(AlarmSettings value) async {
    final Map<String, dynamic> response = await api.updateAlarmSettings(value.toJson());
    alarmSettings = AlarmSettings.fromJson(response);
    notifyListeners();
  }

  Future<void> activateAlarm() async {
    await api.activateAlarm();
    await refresh(silent: true);
  }

  Future<void> cancelManualAlarm() async {
    await api.cancelManualAlarm();
    await refresh(silent: true);
  }

  Future<void> silenceAlarm(int minutes) async {
    await api.silenceAlarm(minutes);
    await refresh(silent: true);
  }

  Future<void> cancelSilence() async {
    await api.cancelSilence();
    await refresh(silent: true);
  }

  Future<void> testAlarm() async {
    await api.testAlarm();
    await refresh(silent: true);
  }

  Future<void> acknowledgeEvent(String eventId) async {
    await api.acknowledgeEvent(eventId);
    await refresh(silent: true);
  }

  Future<void> markFalseAlarm(String eventId, String reason) async {
    await api.markFalseAlarm(eventId, reason);
    await refresh(silent: true);
  }

  void clearTransientAlert() {
    transientAlert = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();
    _notificationSubscription?.cancel();
    _socket?.sink.close();
    super.dispose();
  }
}
