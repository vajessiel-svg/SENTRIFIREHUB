import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';
import 'alarm_settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.auth,
    required this.onLogout,
  });

  final AppController controller;
  final AuthService auth;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final health = controller.systemHealth;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
        children: [
          const PageHeader(title: 'Profile'),
          SectionCard(
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.red)),
                  child: ClipOval(child: Image.asset('assets/images/sentrifire_shield_transparent.png', fit: BoxFit.cover)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(controller.owner?.name ?? 'Owner', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(controller.owner?.email ?? '', style: const TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 5),
                      const Text('OWNER', style: TextStyle(color: AppTheme.red, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Safety controls', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _menu(
                  icon: Icons.tune_rounded,
                  title: 'Fire Detection & Alarm Settings',
                  subtitle: '${controller.alarmSettings.sensitivity.replaceAll('_', ' ')} sensitivity',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlarmSettingsScreen(controller: controller),
                    ),
                  ),
                ),
                _menu(
                  icon: Icons.lock_reset_rounded,
                  title: 'Change 4-digit PIN',
                  onTap: () => _changePin(context),
                ),
                _menu(
                  icon: Icons.password_rounded,
                  title: 'Change account password',
                  onTap: () => _changePassword(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('System health', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _health('Pi API', controller.serverReachable ? 'Online' : 'Offline', controller.serverReachable),
                _health('YOLO model', health?.modelLoaded == true ? '${health!.modelVersion} loaded' : 'Not loaded', health?.modelLoaded == true),
                _health('Detection worker', health?.detectorRunning == true ? 'Running' : 'Stopped', health?.detectorRunning == true),
                _health('Push notifications', health?.pushConfigured == true ? 'Configured' : 'Not configured', health?.pushConfigured == true),
                if (health?.piTemperatureC != null)
                  _health('Pi temperature', '${health!.piTemperatureC!.toStringAsFixed(1)} °C', health.piTemperatureC! < 80),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.red,
              side: const BorderSide(color: AppTheme.red),
              padding: const EdgeInsets.all(16),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _menu({required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  Widget _health(String label, String value, bool good) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(good ? Icons.check_circle : Icons.error_outline, color: good ? AppTheme.green : AppTheme.amber, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(color: AppTheme.textSecondary))),
          ],
        ),
      );

  void _changePin(BuildContext context) {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Change PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pinField(current, 'Current PIN'),
            const SizedBox(height: 10),
            _pinField(next, 'New 4-digit PIN'),
            const SizedBox(height: 10),
            _pinField(confirm, 'Confirm new PIN'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (next.text != confirm.text) {
                _message(context, 'New PINs do not match.');
                return;
              }
              try {
                await auth.changePin(current.text, next.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) _message(context, 'PIN changed successfully.');
              } on ApiException catch (error) {
                if (context.mounted) _message(context, error.message);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _pinField(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 4,
        decoration: InputDecoration(labelText: label, counterText: ''),
      );

  void _changePassword(BuildContext context) {
    final current = TextEditingController();
    final next = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Change account password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
            const SizedBox(height: 10),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password (10+ characters)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (next.text.length < 10) {
                _message(context, 'New password must contain at least 10 characters.');
                return;
              }
              try {
                await auth.changePassword(current.text, next.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  _message(context, 'Password changed. Sign in again.');
                  await onLogout();
                }
              } on ApiException catch (error) {
                if (context.mounted) _message(context, error.message);
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('The remembered session and PIN will be removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onLogout();
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _message(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
