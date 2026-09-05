import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/app_models.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? cameraId;
  bool falseAlarmsOnly = false;

  List<FireEvent> get filtered => widget.controller.events.where((FireEvent event) {
        if (cameraId != null && event.cameraId != cameraId) return false;
        if (falseAlarmsOnly && !event.falseAlarm) return false;
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: widget.controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
          children: [
            const PageHeader(title: 'History'),
            SectionCard(
              child: Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: cameraId,
                    decoration: const InputDecoration(labelText: 'Camera filter'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All cameras')),
                      ...widget.controller.cameras.map(
                        (CameraStatus camera) => DropdownMenuItem<String?>(value: camera.id, child: Text('${camera.name} — ${camera.location}')),
                      ),
                    ],
                    onChanged: (String? value) => setState(() => cameraId = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: falseAlarmsOnly,
                    activeThumbColor: AppTheme.red,
                    title: const Text('Show false alarms only'),
                    onChanged: (bool value) => setState(() => falseAlarmsOnly = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            if (filtered.isEmpty)
              const SectionCard(child: Text('No event records match this filter.'))
            else
              for (final FireEvent event in filtered) ...[
                EventTile(event: event),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}
