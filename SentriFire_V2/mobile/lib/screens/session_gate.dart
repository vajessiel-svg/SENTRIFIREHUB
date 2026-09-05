import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'pin_screen.dart';

enum _GateState { loading, login, setupPin, unlockPin, app }

class SessionGate extends StatefulWidget {
  const SessionGate({
    super.key,
    required this.api,
    required this.auth,
    required this.notifications,
  });

  final ApiClient api;
  final AuthService auth;
  final NotificationService notifications;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  _GateState state = _GateState.loading;
  String? startupMessage;

  @override
  void initState() {
    super.initState();
    _decideStart();
  }

  Future<void> _decideStart() async {
    final bool remembered = await widget.auth.hasRememberedSession();
    final bool hasPin = await widget.auth.hasPin();
    if (!mounted) return;
    setState(() {
      state = remembered && hasPin ? _GateState.unlockPin : _GateState.login;
    });
  }

  void _loginComplete(LoginResult result) {
    setState(() {
      state = result.remembered ? _GateState.setupPin : _GateState.app;
    });
  }

  void _openApp([String? message]) {
    setState(() {
      startupMessage = message;
      state = _GateState.app;
    });
  }

  void _returnToLogin([String? message]) {
    setState(() {
      startupMessage = message;
      state = _GateState.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _GateState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _GateState.login:
        return LoginScreen(
          auth: widget.auth,
          initialMessage: startupMessage,
          onSuccess: _loginComplete,
        );
      case _GateState.setupPin:
        return PinScreen.setup(
          auth: widget.auth,
          onUnlocked: _openApp,
          onSessionInvalidated: _returnToLogin,
        );
      case _GateState.unlockPin:
        return PinScreen.unlock(
          auth: widget.auth,
          onUnlocked: _openApp,
          onSessionInvalidated: _returnToLogin,
        );
      case _GateState.app:
        return MainShell(
          api: widget.api,
          auth: widget.auth,
          notifications: widget.notifications,
          startupMessage: startupMessage,
          onLogout: _returnToLogin,
        );
    }
  }
}
