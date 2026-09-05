import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import 'alerts_screen.dart';
import 'cameras_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.api,
    required this.auth,
    required this.notifications,
    required this.onLogout,
    this.startupMessage,
  });

  final ApiClient api;
  final AuthService auth;
  final NotificationService notifications;
  final ValueChanged<String?> onLogout;
  final String? startupMessage;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final AppController controller;
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    controller = AppController(
      api: widget.api,
      auth: widget.auth,
      notifications: widget.notifications,
    );
    controller.start();
    if (widget.startupMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.startupMessage!)));
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void changeScreen(int index) {
    if (index < 0 || index > 4) return;
    setState(() => selectedIndex = index);
  }

  Future<void> logout() async {
    await widget.auth.logout();
    if (mounted) widget.onLogout(null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final List<Widget> screens = [
          DashboardScreen(controller: controller, onNavigate: changeScreen),
          CamerasScreen(controller: controller),
          AlertsScreen(controller: controller),
          HistoryScreen(controller: controller),
          ProfileScreen(controller: controller, auth: widget.auth, onLogout: logout),
        ];
        return Scaffold(
          body: Stack(
            children: [
              IndexedStack(index: selectedIndex, children: screens),
              if (controller.transientAlert != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: MediaQuery.paddingOf(context).top + 8,
                  child: Material(
                    color: AppTheme.darkRed,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      leading: const Icon(Icons.local_fire_department, color: AppTheme.red),
                      title: const Text('SentriFire alert', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(controller.transientAlert!),
                      trailing: IconButton(
                        onPressed: controller.clearTransientAlert,
                        icon: const Icon(Icons.close),
                      ),
                      onTap: () {
                        controller.clearTransientAlert();
                        changeScreen(2);
                      },
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              height: 74,
              backgroundColor: AppTheme.surface,
              indicatorColor: AppTheme.red.withValues(alpha: .15),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (Set<WidgetState> states) => TextStyle(
                  color: states.contains(WidgetState.selected) ? AppTheme.red : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: changeScreen,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Dashboard'),
                NavigationDestination(icon: Icon(Icons.videocam_outlined), selectedIcon: Icon(Icons.videocam), label: 'Cameras'),
                NavigationDestination(icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Alerts'),
                NavigationDestination(icon: Icon(Icons.history), label: 'History'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
              ],
            ),
          ),
        );
      },
    );
  }
}
