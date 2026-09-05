import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/app_models.dart';
import '../widgets/status_widgets.dart';
import 'full_screen_camera.dart';

class CamerasScreen extends StatelessWidget {
  const CamerasScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
          children: [
            const PageHeader(title: 'Cameras'),
            const SizedBox(height: 8),
            if (controller.cameras.isEmpty)
              const SectionCard(
                child: Text('No cameras are configured. Add the three Tapo camera RTSP addresses to the Pi .env file.'),
              )
            else
              for (final CameraStatus camera in controller.cameras) ...[
                CameraTile(
                  camera: camera,
                  imageHeaders: controller.mediaHeaders,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => FullScreenCamera(camera: camera)),
                  ),
                ),
                const SizedBox(height: 14),
              ],
          ],
        ),
      ),
    );
  }
}
