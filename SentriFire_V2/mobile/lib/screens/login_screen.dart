import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.onSuccess,
    this.initialMessage,
  });

  final AuthService auth;
  final ValueChanged<LoginResult> onSuccess;
  final String? initialMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  late final TextEditingController serverController;
  bool rememberDevice = true;
  bool obscurePassword = true;
  bool showServer = false;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    serverController = TextEditingController(text: widget.auth.api.baseUrl);
    error = widget.initialMessage;
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    serverController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (emailController.text.trim().isEmpty || passwordController.text.isEmpty) {
      setState(() => error = 'Enter the owner email and password.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.auth.saveServerUrl(serverController.text);
      final LoginResult result = await widget.auth.login(
        email: emailController.text,
        password: passwordController.text,
        rememberDevice: rememberDevice,
      );
      if (mounted) widget.onSuccess(result);
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } catch (exception) {
      if (mounted) setState(() => error = 'Login failed: $exception');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/sentrifire_shield_transparent.png',
                    width: 210,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 43, fontWeight: FontWeight.w800, letterSpacing: -1.8),
                      children: [
                        TextSpan(text: 'Sentri', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Fire', style: TextStyle(color: AppTheme.red)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'DETECT  •  ALERT  •  PROTECT',
                    style: TextStyle(color: AppTheme.textSecondary, letterSpacing: 2.2, fontSize: 11),
                  ),
                  const SizedBox(height: 38),
                  if (error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AppTheme.darkRed.withValues(alpha: .55),
                        border: Border.all(color: AppTheme.red),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(error!, style: const TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Owner email',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscurePassword = !obscurePassword),
                        icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: rememberDevice,
                    activeColor: AppTheme.red,
                    title: const Text('Remember this device'),
                    subtitle: const Text('Use a 4-digit PIN for faster future access.'),
                    onChanged: (bool? value) => setState(() => rememberDevice = value ?? true),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => showServer = !showServer),
                    icon: const Icon(Icons.settings_ethernet_rounded),
                    label: Text(showServer ? 'Hide server address' : 'Pi server address'),
                  ),
                  if (showServer) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: serverController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'SentriFire API address',
                        hintText: 'http://192.168.1.50:8000',
                        prefixIcon: Icon(Icons.router_outlined),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton(
                      onPressed: loading ? null : _login,
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
                      child: loading
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text('SIGN IN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'The account password is never saved on this phone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
