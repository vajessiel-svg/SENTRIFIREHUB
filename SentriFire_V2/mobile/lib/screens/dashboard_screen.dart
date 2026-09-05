import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/app_controller.dart';
import '../models/app_models.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';
import 'full_screen_camera.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onNavigate,
  });

  final AppController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final AppAlarmLevel level = controller.globalLevel;
    final Color color = levelColor(level);
    final DateTime now = DateTime.now();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
          children: [
            PageHeader(
              title: 'Dashboard',
              trailing: IconButton(
                onPressed: () => onNavigate(2),
                icon: Badge(
                  isLabelVisible: controller.activeEvents.isNotEmpty,
                  label: Text('${controller.activeEvents.length}'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ),
            if (!controller.serverReachable)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: .12),
                  border: Border.all(color: AppTheme.amber),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: AppTheme.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.cameras.isEmpty
                            ? 'Pi server unavailable. Check the server address and network.'
                            : 'Offline view — showing cached status from ${_lastUpdateText()}.',
                      ),
                    ),
                  ],
                ),
              ),
            SectionCard(
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: AppTheme.red, size: 31),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(DateFormat('h:mm a').format(now), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        Text(DateFormat('EEEE, MMMM d, yyyy').format(now), style: const TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  Text(controller.serverReachable ? 'LIVE' : 'CACHED', style: TextStyle(color: controller.serverReachable ? AppTheme.green : AppTheme.amber, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => onNavigate(2),
              borderRadius: BorderRadius.circular(17),
              child: Ink(
                padding: const EdgeInsets.all(19),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: level == AppAlarmLevel.normal ? .10 : .22),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: color, width: 1.3),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SYSTEM STATUS', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, letterSpacing: 1)),
                          const SizedBox(height: 7),
                          Text(levelLabel(level), style: TextStyle(color: color, fontSize: 27, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 5),
                          Text(_systemMessage(level), style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    Icon(levelIcon(level), color: color, size: 66),
                  ],
                ),
              ),
            ),
            if (controller.systemHealth?.silencedUntil != null) ...[
              const SizedBox(height: 12),
              SectionCard(
                borderColor: AppTheme.red,
                child: Row(
                  children: [
                    const Icon(Icons.volume_off_rounded, color: AppTheme.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ALARM SILENCED until ${DateFormat('h:mm a').format(controller.systemHealth!.silencedUntil!)}. Detection and logging remain active.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _summary(Icons.videocam_outlined, '${controller.cameras.where((c) => c.online).length}/${controller.cameras.length}', 'Cameras online', AppTheme.green, () => onNavigate(1))),
                const SizedBox(width: 12),
                Expanded(child: _summary(Icons.notifications_active_outlined, '${controller.activeEvents.length}', 'Active alerts', AppTheme.red, () => onNavigate(2))),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(child: Text('Cameras', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                TextButton(onPressed: () => onNavigate(1), child: const Text('View all')),
              ],
            ),
            if (controller.loading && controller.cameras.isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (controller.cameras.isEmpty)
              const SectionCard(child: Text('No camera data is available. Configure the three cameras on the Raspberry Pi.'))
            else
              for (final CameraStatus camera in controller.cameras) ...[
                CameraTile(
                  camera: camera,
                  imageHeaders: controller.mediaHeaders,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => FullScreenCamera(camera: camera)),
                  ),
                ),
                const SizedBox(height: 11),
              ],
          ],
        ),
      ),
    );
  }

  String _lastUpdateText() {
    final DateTime? date = controller.lastUpdated;
    return date == null ? 'an unknown time' : DateFormat('MMM d, h:mm:ss a').format(date);
  }

  String _systemMessage(AppAlarmLevel level) => switch (level) {
        AppAlarmLevel.normal => 'All connected cameras report normal conditions.',
        AppAlarmLevel.suspected => 'Possible fire pattern detected. Verification is in progress.',
        AppAlarmLevel.confirmed => 'Fire has been confirmed. Open active alerts immediately.',
        AppAlarmLevel.critical => 'Critical fire alert. Local siren and notifications are active.',
        AppAlarmLevel.offline => 'One or more system components are unavailable.',
      };

  Widget _summary(IconData icon, String value, String label, Color color, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SectionCard(
            child: Column(
              children: [
                Icon(icon, color: color, size: 31),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
      );
}
