import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AuthService auth;
  final ValueChanged<bool> onThemeChanged;
  const SettingsScreen({
    super.key,
    required this.auth,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Only admins load the team list; the server refuses anyone else anyway.
  late final Future<List<Map<String, dynamic>>> _team = widget.auth.isAdmin
      ? widget.auth.listTeam()
      : Future.value(const <Map<String, dynamic>>[]);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createInvite() async {
    try {
      final code = await widget.auth.createInvite();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Staff invite code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Works once and expires in 48 hours. Send it to your staff '
                'member privately. They create an account, log in, then choose '
                '"Join with an invite code". You cannot see this code again.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _logOut() async {
    await widget.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(onThemeChanged: widget.onThemeChanged),
      ),
      (route) => false,
    );
  }

  Widget _teamSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _team,
      builder: (context, snapshot) {
        final members = snapshot.data ?? const <Map<String, dynamic>>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Team & invites',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else if (snapshot.hasError)
                  const Text('Could not load the team list.')
                else
                  for (final m in members)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(
                        '${m['display_name'] ?? ''}'.isEmpty
                            ? 'Team member'
                            : '${m['display_name']}',
                      ),
                      subtitle: Text('${m['role'] ?? ''}'.toUpperCase()),
                    ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _createInvite,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Create staff invite code'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.admin_panel_settings_outlined),
              ),
              title: Text(auth.currentEmail.isEmpty ? 'Signed in' : auth.currentEmail),
              subtitle: Text(
                '${auth.workspaceName.isEmpty ? 'Workspace' : auth.workspaceName}'
                ' · Role: ${auth.role.toUpperCase()}',
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: const Text('Switch between light and dark appearance'),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: widget.onThemeChanged,
          ),
          if (auth.isAdmin) _teamSection(),
          const ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('Security & privacy'),
            subtitle: Text(
              'Access is enforced on the server with Row Level Security. '
              'Staff can add and edit clients; only Admins can delete.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline mode'),
            subtitle: Text(
              'Client records are cached on this phone. The cache is not '
              'encrypted, and changes made offline are not queued yet.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About VasFlow'),
            subtitle: Text('Visa Consultant Admin Management'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _logOut,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
