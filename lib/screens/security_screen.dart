import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

class SecurityScreen extends StatefulWidget {
  final AuthService auth;

  const SecurityScreen({super.key, required this.auth});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _changePassword() async {
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    String? dialogError;

    final password = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Change password'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Choose a new password for this account. It is sent '
                        'directly to Supabase and is never saved by VasFlow.',
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: newPassword,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'New password',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confirmPassword,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: Icon(Icons.lock_reset_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          dialogError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        final value = newPassword.text;
                        if (value.length < 6) {
                          setDialogState(
                            () =>
                                dialogError =
                                    'Use at least 6 characters for your new password.',
                          );
                          return;
                        }
                        if (value != confirmPassword.text) {
                          setDialogState(
                            () =>
                                dialogError = 'The two passwords do not match.',
                          );
                          return;
                        }
                        Navigator.pop(dialogContext, value);
                      },
                      child: const Text('Continue'),
                    ),
                  ],
                ),
          ),
    );

    newPassword.dispose();
    confirmPassword.dispose();
    if (password == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Change your password?'),
            content: const Text(
              'The new password will replace the current one for this '
              'account. Make sure you have saved it somewhere safe.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Change password'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.auth.changePassword(password);
      if (!mounted) return;
      _snack('Password updated');
    } catch (e) {
      _snack('Could not change the password: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Log out?'),
            content: const Text(
              'You will need your email or phone number and password to sign '
              'in again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Log out'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
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
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change password'),
              subtitle: const Text(
                'Update the password for your signed-in Supabase account. '
                'Passwords are never stored on this device.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _changePassword,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Account email'),
              subtitle: Text(
                widget.auth.currentEmail.isEmpty
                    ? 'No email on this account'
                    : widget.auth.currentEmail,
              ),
              trailing: const Icon(Icons.lock_outline, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('Server-enforced access'),
              subtitle: Text(
                'Supabase Row Level Security decides what this account can '
                'see and change. Buttons in the app only reflect those rules; '
                'they do not replace them.',
              ),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : _logOut,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
