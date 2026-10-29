import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_router.dart';
import 'login_screen.dart';

/// Shown after sign-in when the person does not belong to a workspace yet.
class OnboardingScreen extends StatefulWidget {
  final AuthService auth;
  const OnboardingScreen({super.key, required this.auth});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final workspaceName = TextEditingController();
  final inviteCode = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    workspaceName.dispose();
    inviteCode.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => homeFor(widget.auth),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _logOut() async {
    await widget.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your workspace')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome to VasFlow',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'A workspace is where your team shares clients. Start your own '
                  'as the Admin, or join one with an invite code from your Admin.',
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Create a workspace (Admin)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: workspaceName,
                          decoration: const InputDecoration(
                            labelText: 'Workspace name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => _run(
                                    () => widget.auth
                                        .createWorkspace(workspaceName.text),
                                  ),
                          child: const Text('Create workspace'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Join with an invite code (Staff)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: inviteCode,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Invite code',
                            hintText: 'XXXX-XXXX-XXXX-XXXX',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => _run(
                                    () => widget.auth.joinWorkspace(inviteCode.text),
                                  ),
                          child: const Text('Join workspace'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(error!, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 16),
                TextButton(onPressed: busy ? null : _logOut, child: const Text('Log out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
