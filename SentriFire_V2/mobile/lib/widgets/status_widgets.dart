import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_models.dart';
import '../theme/app_theme.dart';

Color levelColor(AppAlarmLevel level) => switch (level) {
      AppAlarmLevel.normal => AppTheme.green,
      AppAlarmLevel.suspected => AppTheme.amber,
      AppAlarmLevel.confirmed || AppAlarmLevel.critical => AppTheme.red,
      AppAlarmLevel.offline => AppTheme.gray,
    };

String levelLabel(AppAlarmLevel level) => switch (level) {
      AppAlarmLevel.normal => 'NORMAL',
      AppAlarmLevel.suspected => 'SUSPECTED',
      AppAlarmLevel.confirmed => 'FIRE CONFIRMED',
      AppAlarmLevel.critical => 'CRITICAL FIRE',
      AppAlarmLevel.offline => 'OFFLINE',
    };

IconData levelIcon(AppAlarmLevel level) => switch (level) {
      AppAlarmLevel.normal => Icons.verified_user_outlined,
      AppAlarmLevel.suspected => Icons.warning_amber_rounded,
      AppAlarmLevel.confirmed || AppAlarmLevel.critical => Icons.local_fire_department_rounded,
      AppAlarmLevel.offline => Icons.cloud_off_rounded,
    };

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: Row(
          children: [
            const SizedBox(width: 42),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(width: 42, child: trailing),
          ],
        ),
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.borderColor, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final Color? borderColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? AppTheme.border),
        ),
        child: child,
      );
}

class CameraTile extends StatelessWidget {
  const CameraTile({
    super.key,
    required this.camera,
    required this.onTap,
    this.imageHeaders = const <String, String>{},
  });
  final CameraStatus camera;
  final VoidCallback onTap;
  final Map<String, String> imageHeaders;

  @override
  Widget build(BuildContext context) {
    final Color color = levelColor(camera.level);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: camera.level == AppAlarmLevel.critical || camera.level == AppAlarmLevel.confirmed
                ? AppTheme.darkRed.withValues(alpha: .55)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: .8)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 112,
                  height: 82,
                  child: camera.online && camera.thumbnailUrl != null
                      ? Image.network(
                          '${camera.thumbnailUrl}?v=${camera.lastSeenAt?.millisecondsSinceEpoch ?? 0}',
                          headers: imageHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(color),
                        )
                      : _placeholder(color),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(camera.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(camera.location, style: const TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            levelLabel(camera.level),
                            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      camera.online
                          ? (camera.screenSuppressed
                              ? 'Screen-contained detection suppressed'
                              : 'Confidence ${(camera.confidence * 100).toStringAsFixed(0)}%')
                          : (camera.connectionMessage ?? 'Camera unavailable'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(Color color) => ColoredBox(
        color: AppTheme.surface2,
        child: Icon(camera.online ? levelIcon(camera.level) : Icons.videocam_off_outlined, color: color, size: 38),
      );
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.onTap});
  final FireEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = event.falseAlarm ? AppTheme.gray : levelColor(event.level);
    return SectionCard(
      borderColor: color.withValues(alpha: .7),
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .15),
          child: Icon(event.falseAlarm ? Icons.report_off_outlined : levelIcon(event.level), color: color),
        ),
        title: Text(
          event.falseAlarm ? 'FALSE ALARM' : levelLabel(event.level),
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
        ),
        subtitle: Text(
          '${event.cameraName} — ${event.location}\n${DateFormat('MMM d, yyyy • h:mm:ss a').format(event.startedAt)}',
          style: const TextStyle(height: 1.5),
        ),
        isThreeLine: true,
        trailing: Text(
          '${(event.peakConfidence * 100).toStringAsFixed(0)}%',
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
