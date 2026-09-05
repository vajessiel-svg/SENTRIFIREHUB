import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

enum PinMode { setup, unlock }

class PinScreen extends StatefulWidget {
  const PinScreen._({
    required this.mode,
    required this.auth,
    required this.onUnlocked,
    required this.onSessionInvalidated,
  });

  factory PinScreen.setup({
    required AuthService auth,
    required ValueChanged<String?> onUnlocked,
    required ValueChanged<String?> onSessionInvalidated,
  }) =>
      PinScreen._(
        mode: PinMode.setup,
        auth: auth,
        onUnlocked: onUnlocked,
        onSessionInvalidated: onSessionInvalidated,
      );

  factory PinScreen.unlock({
    required AuthService auth,
    required ValueChanged<String?> onUnlocked,
    required ValueChanged<String?> onSessionInvalidated,
  }) =>
      PinScreen._(
        mode: PinMode.unlock,
        auth: auth,
        onUnlocked: onUnlocked,
        onSessionInvalidated: onSessionInvalidated,
      );

  final PinMode mode;
  final AuthService auth;
  final ValueChanged<String?> onUnlocked;
  final ValueChanged<String?> onSessionInvalidated;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String pin = '';
  String? firstPin;
  String? message;
  int failedAttempts = 0;
  bool loading = false;

  void _press(String value) {
    if (loading || pin.length >= 4) return;
    setState(() {
      pin += value;
      message = null;
    });
    if (pin.length == 4) _submit();
  }

  void _backspace() {
    if (loading || pin.isEmpty) return;
    setState(() => pin = pin.substring(0, pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => loading = true);
    if (widget.mode == PinMode.setup) {
      if (firstPin == null) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return;
        setState(() {
          firstPin = pin;
          pin = '';
          message = 'Enter the same PIN again.';
          loading = false;
        });
        return;
      }
      if (firstPin != pin) {
        setState(() {
          firstPin = null;
          pin = '';
          message = 'PINs did not match. Start again.';
          loading = false;
        });
        return;
      }
      try {
        await widget.auth.setupPin(pin);
        if (mounted) widget.onUnlocked(null);
      } on ApiException catch (error) {
        if (mounted) setState(() => message = error.message);
      } finally {
        if (mounted) setState(() => loading = false);
      }
      return;
    }

    final PinVerificationResult result = await widget.auth.unlockWithPin(pin, failedAttempts);
    if (!mounted) return;
    if (result.sessionInvalidated) {
      widget.onSessionInvalidated(result.message);
      return;
    }
    if (result.success) {
      widget.onUnlocked(result.message);
      return;
    }
    setState(() {
      failedAttempts += 1;
      pin = '';
      message = result.message;
      loading = false;
    });
  }

  Future<void> _biometric() async {
    setState(() {
      loading = true;
      message = null;
    });
    final PinVerificationResult result = await widget.auth.unlockWithBiometrics();
    if (!mounted) return;
    if (result.success) {
      widget.onUnlocked(result.message);
    } else {
      setState(() {
        loading = false;
        message = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool setup = widget.mode == PinMode.setup;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Column(
                children: [
                  Image.asset('assets/images/sentrifire_shield_transparent.png', width: 140, height: 125),
                  Text(
                    setup ? (firstPin == null ? 'Create emergency PIN' : 'Confirm your PIN') : 'Welcome back',
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    setup ? 'Choose four numbers for fast access.' : 'Enter your 4-digit PIN to open SentriFire.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      4,
                      (int index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 17,
                        height: 17,
                        margin: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < pin.length ? AppTheme.red : Colors.transparent,
                          border: Border.all(color: index < pin.length ? AppTheme.red : AppTheme.gray, width: 1.6),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: Center(
                      child: loading
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.3),
                            )
                          : Text(
                              message ?? '',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: message?.contains('offline') == true ? AppTheme.amber : AppTheme.textSecondary),
                            ),
                    ),
                  ),
                  for (final List<String> row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ])
                    _keyRow(row),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 70,
                        child: setup
                            ? const SizedBox.shrink()
                            : IconButton(
                                onPressed: loading ? null : _biometric,
                                icon: const Icon(Icons.fingerprint_rounded, size: 34),
                                tooltip: 'Fingerprint or device unlock',
                              ),
                      ),
                      _key('0'),
                      SizedBox(
                        width: 76,
                        height: 70,
                        child: IconButton(
                          onPressed: loading ? null : _backspace,
                          icon: const Icon(Icons.backspace_outlined),
                        ),
                      ),
                    ],
                  ),
                  if (!setup)
                    TextButton(
                      onPressed: loading
                          ? null
                          : () async {
                              await widget.auth.clearLocalSession();
                              widget.onSessionInvalidated('Enter your email and password to create a new PIN.');
                            },
                      child: const Text('Forgot PIN? Use full login'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyRow(List<String> values) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: values.map(_key).toList(),
      );

  Widget _key(String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: SizedBox(
          width: 76,
          height: 70,
          child: FilledButton.tonal(
            onPressed: loading ? null : () => _press(value),
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: AppTheme.surface2,
            ),
            child: Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}
