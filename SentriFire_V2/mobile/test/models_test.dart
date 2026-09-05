import 'package:flutter_test/flutter_test.dart';
import 'package:sentrifire_mobile/models/app_models.dart';

void main() {
  test('camera status parses a confirmed alarm', () {
    final CameraStatus camera = CameraStatus.fromJson(<String, dynamic>{
      'id': 'cam1',
      'name': 'Front Entrance',
      'location': 'Ground floor',
      'online': true,
      'level': 'confirmed',
      'confidence': 0.91,
      'last_frame_at': 1,
    });

    expect(camera.id, 'cam1');
    expect(camera.level, AppAlarmLevel.confirmed);
    expect(camera.confidence, 0.91);
  });

  test('fire event marks an open event as active', () {
    final FireEvent event = FireEvent.fromJson(<String, dynamic>{
      'id': 'event-1',
      'camera_id': 'cam2',
      'camera_name': 'Kitchen',
      'location': 'Ground floor',
      'level': 'suspected',
      'peak_confidence': 0.67,
      'started_at': 1,
      'false_alarm': false,
    });

    expect(event.active, isTrue);
    expect(event.level, AppAlarmLevel.suspected);
  });
}
