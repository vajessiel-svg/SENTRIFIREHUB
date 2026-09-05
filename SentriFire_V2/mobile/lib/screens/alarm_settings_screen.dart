import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/app_models.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class AlarmSettingsScreen extends StatefulWidget {
  const AlarmSettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<AlarmSettingsScreen> createState() => _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends State<AlarmSettingsScreen> {
  late AlarmSettings settings;
  late bool advanced;
  late double threshold;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    settings = widget.controller.alarmSettings;
    advanced = settings.advancedConfidence != null;
    threshold = settings.advancedConfidence ?? 0.50;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final AlarmSettings value = settings.copyWith(
        advancedConfidence: advanced ? threshold : null,
        clearAdvancedConfidence: !advanced,
      );
      await widget.controller.saveAlarmSettings(value);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alarm settings saved on the Raspberry Pi.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fire Detection & Alarm')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
        children: [
          const SectionCard(
            borderColor: AppTheme.amber,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppTheme.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Detection confidence shows how certain YOLO is. It is not a measurement of fire danger or severity.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Detection sensitivity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  value: 'high',
                  groupValue: settings.sensitivity,
                  title: const Text('High sensitivity'),
                  subtitle: const Text('Faster response with a higher false-alarm risk.'),
                  onChanged: (String? value) => setState(() => settings = settings.copyWith(sensitivity: value)),
                ),
                RadioListTile<String>(
                  value: 'balanced',
                  groupValue: settings.sensitivity,
                  title: const Text('Balanced — recommended'),
                  subtitle: const Text('Confirms detections across several frames.'),
                  onChanged: (String? value) => setState(() => settings = settings.copyWith(sensitivity: value)),
                ),
                RadioListTile<String>(
                  value: 'reduced_false_alarms',
                  groupValue: settings.sensitivity,
                  title: const Text('Reduced false alarms'),
                  subtitle: const Text('Requires stronger and longer detection.'),
                  onChanged: (String? value) => setState(() => settings = settings.copyWith(sensitivity: value)),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: advanced,
                  activeThumbColor: AppTheme.red,
                  title: const Text('Advanced confidence threshold'),
                  subtitle: const Text('Use only after real-camera calibration.'),
                  onChanged: (bool value) => setState(() => advanced = value),
                ),
                if (advanced) ...[
                  Text('Minimum confidence: ${(threshold * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Slider(
                    value: threshold,
                    min: .25,
                    max: .85,
                    divisions: 12,
                    label: '${(threshold * 100).round()}%',
                    onChanged: (double value) => setState(() => threshold = value),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.notificationsEnabled,
                  activeThumbColor: AppTheme.red,
                  title: const Text('Confirmed fire notifications'),
                  subtitle: const Text('Keep enabled for emergency alerts.'),
                  onChanged: (bool value) => setState(() => settings = settings.copyWith(notificationsEnabled: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.suspectedNotifications,
                  activeThumbColor: AppTheme.amber,
                  title: const Text('Suspected-fire notifications'),
                  subtitle: const Text('May generate more notifications during calibration.'),
                  onChanged: (bool value) => setState(() => settings = settings.copyWith(suspectedNotifications: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.sirenEnabled,
                  activeThumbColor: AppTheme.red,
                  title: const Text('Automatic physical siren'),
                  subtitle: Text(settings.sirenEnabled ? 'Activates on confirmed fire.' : 'WARNING: automatic siren disabled.'),
                  onChanged: (bool value) => _confirmSiren(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Manual alarm controls', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _confirmAction(
                    title: 'Activate the siren now?',
                    message: 'This immediately activates the physical alarm relay.',
                    action: widget.controller.activateAlarm,
                  ),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
                  icon: const Icon(Icons.campaign_rounded),
                  label: const Text('ACTIVATE SIREN NOW'),
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: () => _confirmAction(
                    title: 'Cancel manual siren?',
                    message: 'This cancels only a manual activation. An active confirmed-fire event can still keep the automatic siren on.',
                    action: widget.controller.cancelManualAlarm,
                  ),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Cancel manually activated siren'),
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: () => _confirmAction(
                    title: 'Run a 5-second siren test?',
                    message: 'Warn everyone nearby before testing.',
                    action: widget.controller.testAlarm,
                  ),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Test siren for 5 seconds'),
                ),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: _silenceOptions,
                  icon: const Icon(Icons.volume_off_outlined),
                  label: const Text('Temporary silence / maintenance'),
                ),
                const SizedBox(height: 9),
                TextButton(
                  onPressed: widget.controller.cancelSilence,
                  child: const Text('Cancel silence and resume automatic alarm'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: saving ? null : _save,
              child: saving ? const CircularProgressIndicator() : const Text('SAVE SETTINGS', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmSiren(bool value) {
    if (value) {
      setState(() => settings = settings.copyWith(sirenEnabled: true));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Disable automatic siren?'),
        content: const Text('YOLO detection and event logging will continue, but confirmed fires will not automatically activate the physical siren.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Keep enabled')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() => settings = settings.copyWith(sirenEnabled: false));
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
  }

  void _confirmAction({required String title, required String message, required Future<void> Function() action}) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await action();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Command sent to the Raspberry Pi.')));
              } catch (error) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _silenceOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Temporary silence', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Detection and event logging remain active. The siren automatically resumes.'),
              const SizedBox(height: 12),
              for (final int minutes in [1, 3, 5, 15, 30])
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$minutes minute${minutes == 1 ? '' : 's'}'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await widget.controller.silenceAlarm(minutes);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Siren silenced for $minutes minute${minutes == 1 ? '' : 's'}.')));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
