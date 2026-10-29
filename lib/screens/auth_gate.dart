import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_router.dart';
import 'login_screen.dart';

/// First screen of the app. If a saved session exists, skip the login screen.
class AuthGate extends StatefulWidget {
  final ValueChanged<bool> onThemeChanged;
  const AuthGate({super.key, required this.onThemeChanged});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final auth = AuthService();
  late Future<void> _start = _prepare();

  Future<void> _prepare() async {
    if (auth.hasSession) await auth.loadMembership();
  }

  void _retry() => setState(() => _start = _prepare());

  Future<void> _logOut() async {
    await auth.signOut();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!auth.hasSession) {
      return LoginScreen(onThemeChanged: widget.onThemeChanged);
    }
    return FutureBuilder<void>(
      future: _start,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load your workspace. Check your internet '
                      'connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _retry, child: const Text('Try again')),
                    TextButton(onPressed: _logOut, child: const Text('Log out')),
                  ],
                ),
              ),
            ),
          );
        }
        return homeFor(auth, widget.onThemeChanged);
      },
    );
  }
}
