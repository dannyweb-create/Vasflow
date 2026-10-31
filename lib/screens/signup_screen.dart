import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_router.dart';
import 'join_workspace_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

class SignupScreen extends StatefulWidget {
  final String? inviteCode;
  const SignupScreen({super.key, this.inviteCode});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final auth = AuthService();
  final email = TextEditingController(),
      phone = TextEditingController(),
      password = TextEditingController(),
      confirmPassword = TextEditingController();
  bool busy = false, needsLogin = false;
  String? message, error;

  @override
  void dispose() {
    email.dispose();
    phone.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  String _plain(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> submit() async {
    if (email.text.trim().isEmpty && phone.text.trim().isEmpty) {
      setState(() => error = 'Enter an email address or phone number.');
      return;
    }
    if (password.text.length < 6) {
      setState(() => error = 'Use at least 6 characters for your password.');
      return;
    }
    if (password.text != confirmPassword.text) {
      setState(() => error = 'The passwords do not match.');
      return;
    }
    final invite = widget.inviteCode?.trim() ?? '';
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      final hasSession = await auth.signUp(
        email: email.text,
        phone: phone.text,
        password: password.text,
      );
      if (!mounted) return;
      if (invite.isEmpty) {
        setState(
          () =>
              message =
                  'Account request submitted. Follow the verification instructions from Supabase.',
        );
        return;
      }
      if (!hasSession) {
        setState(() {
          needsLogin = true;
          message =
              'Account created. Confirm your email or phone, then log in. '
              'Your invitation code will be used after you log in.';
        });
        return;
      }
      try {
        await auth.joinWorkspace(invite);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => homeFor(auth)),
          (route) => false,
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder:
                (_) => OnboardingScreen(
                  auth: auth,
                  initialInviteCode: invite,
                  initialError:
                      'We could not join that workspace: ${_plain(e)}',
                ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = _plain(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Join VasFlow',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              if (needsLogin) ...[
                Text(
                  message ??
                      'Confirm your account, then log in to use your invitation code.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder:
                              (_) => LoginScreen(inviteCode: widget.inviteCode),
                        ),
                      ),
                  child: const Text('Go to log in'),
                ),
              ] else ...[
                if ((widget.inviteCode ?? '').trim().isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'You are joining a workspace with an invitation code.',
                    ),
                  ),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional if phone is provided)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText:
                        'Phone with country code (optional if email is provided)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                if (message != null)
                  Text(message!, style: const TextStyle(color: Colors.green)),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(busy ? 'Creating…' : 'Create account'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => JoinWorkspaceScreen(
                                initialCode: widget.inviteCode,
                              ),
                        ),
                      ),
                  child: const Text('Join workspace with invitation code'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
