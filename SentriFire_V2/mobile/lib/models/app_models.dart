enum AppAlarmLevel { normal, suspected, confirmed, critical, offline }

AppAlarmLevel alarmLevelFromString(String? value) {
  return AppAlarmLevel.values.firstWhere(
    (AppAlarmLevel level) => level.name == value,
    orElse: () => AppAlarmLevel.offline,
  );
}

DateTime? dateTimeFromEpoch(Object? value) {
  if (value is! num) return null;
  return DateTime.fromMillisecondsSinceEpoch((value * 1000).round(), isUtc: true).toLocal();
}

class OwnerAccount {
  const OwnerAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final String role;

  factory OwnerAccount.fromJson(Map<String, dynamic> json) => OwnerAccount(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Owner',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'owner',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
      };
}

class CameraStatus {
  const CameraStatus({
    required this.id,
    required this.name,
    required this.location,
    required this.enabled,
    required this.online,
    required this.level,
    required this.confidence,
    required this.lastSeenAt,
    required this.streamUrl,
    required this.thumbnailUrl,
    required this.connectionMessage,
    required this.activeEventId,
    required this.screenSuppressed,
  });

  final String id;
  final String name;
  final String location;
  final bool enabled;
  final bool online;
  final AppAlarmLevel level;
  final double confidence;
  final DateTime? lastSeenAt;
  final String? streamUrl;
  final String? thumbnailUrl;
  final String? connectionMessage;
  final String? activeEventId;
  final bool screenSuppressed;

  factory CameraStatus.fromJson(Map<String, dynamic> json) => CameraStatus(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Camera',
        location: json['location']?.toString() ?? 'Unassigned',
        enabled: json['enabled'] == true,
        online: json['online'] == true,
        level: alarmLevelFromString(json['level']?.toString()),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        lastSeenAt: dateTimeFromEpoch(json['last_seen_at']),
        streamUrl: json['stream_url']?.toString(),
        thumbnailUrl: json['thumbnail_url']?.toString(),
        connectionMessage: json['connection_message']?.toString(),
        activeEventId: json['active_event_id']?.toString(),
        screenSuppressed: json['screen_suppressed'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'enabled': enabled,
        'online': online,
        'level': level.name,
        'confidence': confidence,
        'last_seen_at': lastSeenAt == null ? null : lastSeenAt!.toUtc().millisecondsSinceEpoch / 1000,
        'stream_url': streamUrl,
        'thumbnail_url': thumbnailUrl,
        'connection_message': connectionMessage,
        'active_event_id': activeEventId,
        'screen_suppressed': screenSuppressed,
      };

  CameraStatus copyWith({
    bool? online,
    AppAlarmLevel? level,
    double? confidence,
    DateTime? lastSeenAt,
    String? activeEventId,
  }) {
    return CameraStatus(
      id: id,
      name: name,
      location: location,
      enabled: enabled,
      online: online ?? this.online,
      level: level ?? this.level,
      confidence: confidence ?? this.confidence,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      streamUrl: streamUrl,
      thumbnailUrl: thumbnailUrl,
      connectionMessage: connectionMessage,
      activeEventId: activeEventId ?? this.activeEventId,
      screenSuppressed: screenSuppressed,
    );
  }
}

class FireEvent {
  const FireEvent({
    required this.id,
    required this.cameraId,
    required this.cameraName,
    required this.location,
    required this.level,
    required this.peakConfidence,
    required this.startedAt,
    required this.endedAt,
    required this.snapshotUrl,
    required this.acknowledgedAt,
    required this.falseAlarm,
    required this.falseAlarmReason,
    required this.modelVersion,
    required this.sensitivity,
  });

  final String id;
  final String cameraId;
  final String cameraName;
  final String location;
  final AppAlarmLevel level;
  final double peakConfidence;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? snapshotUrl;
  final DateTime? acknowledgedAt;
  final bool falseAlarm;
  final String? falseAlarmReason;
  final String modelVersion;
  final String sensitivity;

  bool get active => endedAt == null && !falseAlarm;

  factory FireEvent.fromJson(Map<String, dynamic> json) => FireEvent(
        id: json['id']?.toString() ?? '',
        cameraId: json['camera_id']?.toString() ?? '',
        cameraName: json['camera_name']?.toString() ?? 'Camera',
        location: json['location']?.toString() ?? 'Unassigned',
        level: alarmLevelFromString(json['level']?.toString()),
        peakConfidence: (json['peak_confidence'] as num?)?.toDouble() ?? 0,
        startedAt: dateTimeFromEpoch(json['started_at']) ?? DateTime.now(),
        endedAt: dateTimeFromEpoch(json['ended_at']),
        snapshotUrl: json['snapshot_url']?.toString(),
        acknowledgedAt: dateTimeFromEpoch(json['acknowledged_at']),
        falseAlarm: json['false_alarm'] == true || json['false_alarm'] == 1,
        falseAlarmReason: json['false_alarm_reason']?.toString(),
        modelVersion: json['model_version']?.toString() ?? 'unknown',
        sensitivity: json['sensitivity']?.toString() ?? 'balanced',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'camera_id': cameraId,
        'camera_name': cameraName,
        'location': location,
        'level': level.name,
        'peak_confidence': peakConfidence,
        'started_at': startedAt.toUtc().millisecondsSinceEpoch / 1000,
        'ended_at': endedAt == null ? null : endedAt!.toUtc().millisecondsSinceEpoch / 1000,
        'snapshot_url': snapshotUrl,
        'acknowledged_at': acknowledgedAt == null ? null : acknowledgedAt!.toUtc().millisecondsSinceEpoch / 1000,
        'false_alarm': falseAlarm,
        'false_alarm_reason': falseAlarmReason,
        'model_version': modelVersion,
        'sensitivity': sensitivity,
      };
}

class AlarmSettings {
  const AlarmSettings({
    required this.sensitivity,
    required this.advancedConfidence,
    required this.sirenEnabled,
    required this.notificationsEnabled,
    required this.suspectedNotifications,
  });

  final String sensitivity;
  final double? advancedConfidence;
  final bool sirenEnabled;
  final bool notificationsEnabled;
  final bool suspectedNotifications;

  factory AlarmSettings.fromJson(Map<String, dynamic> json) => AlarmSettings(
        sensitivity: json['sensitivity']?.toString() ?? 'balanced',
        advancedConfidence: (json['advanced_confidence'] as num?)?.toDouble(),
        sirenEnabled: json['siren_enabled'] != false,
        notificationsEnabled: json['notifications_enabled'] != false,
        suspectedNotifications: json['suspected_notifications'] == true,
      );

  Map<String, dynamic> toJson() => {
        'sensitivity': sensitivity,
        'advanced_confidence': advancedConfidence,
        'siren_enabled': sirenEnabled,
        'notifications_enabled': notificationsEnabled,
        'suspected_notifications': suspectedNotifications,
      };

  AlarmSettings copyWith({
    String? sensitivity,
    double? advancedConfidence,
    bool clearAdvancedConfidence = false,
    bool? sirenEnabled,
    bool? notificationsEnabled,
    bool? suspectedNotifications,
  }) {
    return AlarmSettings(
      sensitivity: sensitivity ?? this.sensitivity,
      advancedConfidence: clearAdvancedConfidence ? null : (advancedConfidence ?? this.advancedConfidence),
      sirenEnabled: sirenEnabled ?? this.sirenEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      suspectedNotifications: suspectedNotifications ?? this.suspectedNotifications,
    );
  }
}

class SystemHealth {
  const SystemHealth({
    required this.apiOnline,
    required this.modelVersion,
    required this.modelLoaded,
    required this.detectorRunning,
    required this.piTemperatureC,
    required this.diskFreeBytes,
    required this.pushConfigured,
    required this.sirenActive,
    required this.silencedUntil,
  });

  final bool apiOnline;
  final String modelVersion;
  final bool modelLoaded;
  final bool detectorRunning;
  final double? piTemperatureC;
  final int? diskFreeBytes;
  final bool pushConfigured;
  final bool sirenActive;
  final DateTime? silencedUntil;

  factory SystemHealth.fromJson(Map<String, dynamic> json) {
    final detector = (json['detector'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final alarm = (json['alarm'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return SystemHealth(
      apiOnline: json['api_online'] == true,
      modelVersion: json['model_version']?.toString() ?? 'unknown',
      modelLoaded: detector['model_loaded'] == true,
      detectorRunning: detector['running'] == true,
      piTemperatureC: (json['pi_temperature_c'] as num?)?.toDouble(),
      diskFreeBytes: (json['disk_free_bytes'] as num?)?.toInt(),
      pushConfigured: json['push_notifications_configured'] == true,
      sirenActive: alarm['siren_active'] == true,
      silencedUntil: dateTimeFromEpoch(alarm['silenced_until']),
    );
  }
}
