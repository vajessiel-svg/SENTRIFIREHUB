import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/app_models.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String filter = 'Active';

  List<FireEvent> get filtered {
    return switch (filter) {
      'Active' => widget.controller.events.where((FireEvent event) => event.active).toList(),
      'Confirmed' => widget.controller.events
          .where((FireEvent event) => event.level == AppAlarmLevel.confirmed || event.level == AppAlarmLevel.critical)
          .toList(),
      'Suspected' => widget.controller.events.where((FireEvent event) => event.level == AppAlarmLevel.suspected).toList(),
      _ => widget.controller.events,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: widget.controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
          children: [
            const PageHeader(title: 'Alerts'),
            Wrap(
              spacing: 8,
              children: ['Active', 'All', 'Confirmed', 'Suspected']
                  .map(
                    (String value) => ChoiceChip(
                      label: Text(value),
                      selected: filter == value,
                      selectedColor: AppTheme.red.withValues(alpha: .25),
                      onSelected: (_) => setState(() => filter = value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const SectionCard(
                child: Column(
                  children: [
                    Icon(Icons.notifications_off_outlined, color: AppTheme.green, size: 42),
                    SizedBox(height: 10),
                    Text('No matching alerts.'),
                  ],
                ),
              )
            else
              for (final FireEvent event in filtered) ...[
                EventTile(event: event, onTap: () => _showEvent(event)),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  void _showEvent(FireEvent event) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (BuildContext sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                event.falseAlarm ? 'False alarm record' : levelLabel(event.level),
                style: TextStyle(color: event.falseAlarm ? AppTheme.gray : levelColor(event.level), fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text('${event.cameraName} — ${event.location}', style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              if (event.snapshotUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    event.snapshotUrl!,
                    headers: widget.controller.mediaHeaders,
                    height: 210,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(height: 120, child: Center(child: Icon(Icons.broken_image_outlined))),
                  ),
                ),
              const SizedBox(height: 15),
              SectionCard(
                child: Column(
                  children: [
                    _detail('Detection confidence', '${(event.peakConfidence * 100).toStringAsFixed(1)}%'),
                    _detail('Alarm level', levelLabel(event.level)),
                    _detail('Sensitivity', event.sensitivity.replaceAll('_', ' ')),
                    _detail('Model', event.modelVersion),
                    _detail('Acknowledged', event.acknowledgedAt == null ? 'No' : 'Yes'),
                  ],
                ),
              ),
              if (event.active) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _run(() => widget.controller.acknowledgeEvent(event.id), 'Alert acknowledged.');
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Acknowledge alert'),
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _silenceDialog();
                  },
                  icon: const Icon(Icons.volume_off_outlined),
                  label: const Text('Temporarily silence siren'),
                ),
                const SizedBox(height: 9),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _falseAlarmDialog(event);
                  },
                  icon: const Icon(Icons.report_off_outlined),
                  label: const Text('Mark as false alarm'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textSecondary))),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      );

  void _silenceDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Temporarily silence siren?'),
        content: const Text('Detection, event logging, and notifications will remain active. The siren automatically resumes after the selected time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          for (final int minutes in [1, 3, 5])
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _run(() => widget.controller.silenceAlarm(minutes), 'Siren silenced for $minutes minute${minutes == 1 ? '' : 's'}.');
              },
              child: Text('$minutes min'),
            ),
        ],
      ),
    );
  }

  void _falseAlarmDialog(FireEvent event) {
    String reason = 'Display screen or bright object';
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
          title: const Text('Mark as false alarm?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This closes the event and records feedback for future model improvement. Verify the camera first.'),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const [
                  DropdownMenuItem(value: 'Display screen or bright object', child: Text('Screen or bright object')),
                  DropdownMenuItem(value: 'Red or orange object', child: Text('Red/orange object')),
                  DropdownMenuItem(value: 'Reflection or lighting', child: Text('Reflection/lighting')),
                  DropdownMenuItem(value: 'Other verified false alarm', child: Text('Other verified false alarm')),
                ],
                onChanged: (String? value) => setDialogState(() => reason = value ?? reason),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _run(() => widget.controller.markFalseAlarm(event.id, reason), 'False-alarm feedback saved.');
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
