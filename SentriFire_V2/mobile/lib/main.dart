import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/session_gate.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final ApiClient api = ApiClient();
  final AuthService auth = AuthService(api);
  await auth.initialize();
  final NotificationService notifications = NotificationService();
  await notifications.initialize();

  runApp(
    SentriFireApp(
      api: api,
      auth: auth,
      notifications: notifications,
    ),
  );
}

class SentriFireApp extends StatelessWidget {
  const SentriFireApp({
    super.key,
    required this.api,
    required this.auth,
    required this.notifications,
  });

  final ApiClient api;
  final AuthService auth;
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SentriFire',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark,
      home: SessionGate(
        api: api,
        auth: auth,
        notifications: notifications,
      ),
    );
  }
}
