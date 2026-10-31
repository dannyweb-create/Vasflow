import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_router.dart';
import 'login_screen.dart';

/// Shown after sign-in when the person does not belong to a workspace yet.
class OnboardingScreen extends StatefulWidget {
  final AuthService auth;
  final String? initialInviteCode;
  final String? initialError;
  const OnboardingScreen({
    super.key,
    required this.auth,
    this.initialInviteCode,
    this.initialError,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final workspaceName = TextEditingController();
  late final TextEditingController inviteCode;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    inviteCode = TextEditingController(text: widget.initialInviteCode ?? '');
    error = widget.initialError;
  }

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
        MaterialPageRoute(builder: (_) => homeFor(widget.auth)),
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

  Future<void> _createWorkspace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Create a separate workspace?'),
            content: const Text(
              'This creates a new separate workspace and makes you its Admin. '
              'Staff joining an existing business should use an invitation '
              'code instead.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Create workspace'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => widget.auth.createWorkspace(workspaceName.text));
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
                  'A workspace is where your team shares clients. Join your '
                  'team with an invite code from your Admin, or start a new '
                  'workspace of your own.',
                ),
                const SizedBox(height: 24),
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
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Invite code',
                            hintText: 'XXXX-XXXX-XXXX-XXXX',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed:
                              busy
                                  ? null
                                  : () => _run(
                                    () => widget.auth.joinWorkspace(
                                      inviteCode.text,
                                    ),
                                  ),
                          child: const Text('Join workspace'),
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
                        OutlinedButton(
                          onPressed: busy ? null : _createWorkspace,
                          child: const Text('Create workspace'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: busy ? null : _logOut,
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
