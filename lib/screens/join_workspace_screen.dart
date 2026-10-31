import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'signup_screen.dart';

/// Collects the invitation code before sign-up or login so the code is
/// redeemed automatically as soon as a session exists.
class JoinWorkspaceScreen extends StatefulWidget {
  final String? initialCode;
  const JoinWorkspaceScreen({super.key, this.initialCode});

  @override
  State<JoinWorkspaceScreen> createState() => _JoinWorkspaceScreenState();
}

class _JoinWorkspaceScreenState extends State<JoinWorkspaceScreen> {
  late final TextEditingController code;
  String? error;

  @override
  void initState() {
    super.initState();
    code = TextEditingController(text: widget.initialCode ?? '');
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  void _continue({required bool newAccount}) {
    final value = code.text.trim();
    if (value.isEmpty) {
      setState(() => error = 'Enter your invitation code to continue.');
      return;
    }
    setState(() => error = null);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                newAccount
                    ? SignupScreen(inviteCode: value)
                    : LoginScreen(inviteCode: value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join workspace')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Join with an invitation code',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the code from your workspace Admin first. '
                  'Then create an account or log in to join.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Invitation code',
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    prefixIcon: Icon(Icons.key_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                FilledButton(
                  onPressed: () => _continue(newAccount: true),
                  child: const Padding(
                    padding: EdgeInsets.all(13),
                    child: Text("I'm new, create an account"),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _continue(newAccount: false),
                  child: const Text('I already have an account, log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
