import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/reminder_service.dart';
import '../theme/brand.dart';
import '../theme/theme_controller.dart';
import '../widgets/client_avatar.dart';
import 'admin_profile_screen.dart';
import 'backup_screen.dart';
import 'coming_soon_screen.dart';
import 'general_settings_screen.dart';
import 'login_screen.dart';
import 'personal_information_screen.dart';
import 'security_screen.dart';
import 'settings_info_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AuthService auth;
  const SettingsScreen({super.key, required this.auth});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Only admins load the team list; the server refuses anyone else anyway.
  late final Future<List<Map<String, dynamic>>> _team =
      widget.auth.isAdmin
          ? widget.auth.listTeam()
          : Future.value(const <Map<String, dynamic>>[]);
  int _profileRevision = 0;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openAdminProfile() async {
    await _open(AdminProfileScreen(auth: widget.auth));
    if (!mounted) return;
    setState(() => _profileRevision++);
  }

  Future<void> _createInvite() async {
    try {
      final code = await widget.auth.createInvite();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
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
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  IconData _themeIcon(AppThemeChoice choice) {
    switch (choice) {
      case AppThemeChoice.light:
        return Icons.light_mode_outlined;
      case AppThemeChoice.dark:
        return Icons.dark_mode_outlined;
      case AppThemeChoice.glass:
        return Icons.blur_on;
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _tileGroup(List<Widget> tiles) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            tiles[i],
          ],
        ],
      ),
    );
  }

  Widget _profileSummary() {
    final auth = widget.auth;
    final name =
        auth.displayName.isEmpty
            ? (auth.currentEmail.isEmpty ? 'Signed in' : auth.currentEmail)
            : auth.displayName;
    final details = [
      if (auth.currentEmail.isNotEmpty) auth.currentEmail,
      '${auth.workspaceName.isEmpty ? 'Workspace' : auth.workspaceName}'
          ' · Role: ${auth.role.toUpperCase()}',
    ].join('\n');
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ClientAvatar(
          key: ValueKey('profile-avatar-$_profileRevision'),
          photoPath: auth.adminPhotoPath ?? '',
          name: auth.displayName,
          size: 56,
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(details),
        isThreeLine: true,
        trailing: Icon(
          auth.isAdmin ? Icons.edit_outlined : Icons.chevron_right,
        ),
        onTap:
            auth.isAdmin
                ? _openAdminProfile
                : () => _open(PersonalInformationScreen(auth: auth)),
      ),
    );
  }

  Widget _accountSection() {
    final auth = widget.auth;
    return _tileGroup([
      if (auth.isAdmin)
        ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Admin profile'),
          subtitle: const Text('Your name and profile photo'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openAdminProfile,
        ),
      ListTile(
        leading: const Icon(Icons.person_outline),
        title: const Text('Personal information'),
        subtitle: const Text('Email, role and workspace details'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(PersonalInformationScreen(auth: auth)),
      ),
      ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Security'),
        subtitle: const Text('Change password and log out'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(SecurityScreen(auth: auth)),
      ),
    ]);
  }

  Widget _workspaceSection() {
    final auth = widget.auth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tileGroup([
          ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: const Text('General settings'),
            subtitle: const Text('Workspace, role and connection'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(GeneralSettingsScreen(auth: auth)),
          ),
        ]),
        const SizedBox(height: 8),
        if (auth.isAdmin)
          _teamSection()
        else
          const Card(
            child: ListTile(
              leading: Icon(Icons.groups_outlined),
              title: Text('Consultants'),
              subtitle: Text(
                'Only Admins can view the consultant list and create invite '
                'codes.',
              ),
            ),
          ),
        const SizedBox(height: 8),
        Card(child: _remindersSection()),
      ],
    );
  }

  Widget _integrationsSection() {
    return _tileGroup([
      ListTile(
        leading: const Icon(Icons.add_to_drive_outlined),
        title: const Text('Google Drive'),
        subtitle: const Text('Backup and export files to Drive (coming soon)'),
        trailing: const Icon(Icons.chevron_right),
        onTap:
            () => _open(
              const ComingSoonScreen(
                title: 'Google Drive',
                icon: Icons.add_to_drive_outlined,
                description:
                    'Connect VasFlow to Google Drive so protected workspace '
                    'backups and client exports can be copied to your own '
                    'Drive folders.',
                plans: [
                  'Send a finished backup archive to a Drive folder you choose.',
                  'Save client PDF, Excel, CSV or ZIP exports straight to Drive.',
                  'Keep a record of which files were copied and when.',
                ],
              ),
            ),
      ),
      ListTile(
        leading: const Icon(Icons.table_chart_outlined),
        title: const Text('Google Sheets'),
        subtitle: const Text(
          'Share lists and reports with Sheets (coming soon)',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap:
            () => _open(
              const ComingSoonScreen(
                title: 'Google Sheets',
                icon: Icons.table_chart_outlined,
                description:
                    'Connect VasFlow to Google Sheets for live consultant '
                    'lists, pipeline summaries and payment reports.',
                plans: [
                  'Export client, task and payment summaries to a chosen sheet.',
                  'Refresh a sheet without downloading a file first.',
                  'Keep workspace data private by naming the exact sheet.',
                ],
              ),
            ),
      ),
      ListTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: const Text('AI assistant'),
        subtitle: const Text(
          'Connect the assistant to more tools (coming soon)',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap:
            () => _open(
              const ComingSoonScreen(
                title: 'AI assistant',
                icon: Icons.smart_toy_outlined,
                description:
                    'The AI tab already offers basic help. This integration '
                    'will let the assistant work with connected tools and '
                    'outside services.',
                plans: [
                  'Draft updates and summaries using your workspace records.',
                  'Use connected files and calendars when you ask for help.',
                  'Keep every action reviewable before anything is changed.',
                ],
              ),
            ),
      ),
    ]);
  }

  Widget _dataAndSecuritySection() {
    final auth = widget.auth;
    return _tileGroup([
      ListTile(
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Backup and recovery'),
        subtitle: const Text(
          'Backup history, archive download and verified restores. '
          'Only Admins can create backups or restore.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(BackupScreen(auth: auth)),
      ),
      ListTile(
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('Data exports'),
        subtitle: const Text(
          'Export one client from their profile as PDF, Excel, CSV or JSON.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap:
            () => _open(
              const SettingsInfoScreen(
                title: 'Data exports',
                icon: Icons.file_download_outlined,
                summary:
                    'Exports are made per client from the client profile. '
                    'This keeps sensitive records together and avoids sharing '
                    'the whole workspace by accident.',
                points: [
                  'Open Clients, choose a client, then use the export action on '
                      'their profile.',
                  'Choose PDF for a printable report, Excel for one workbook '
                      'with a sheet per section, CSV for plain rows, or JSON for '
                      'structured data.',
                  'Document names and review statuses are always included. You '
                      'can also bundle the original document files into a ZIP.',
                  'Only Admins can export client data. Save or share the '
                      'finished file yourself; VasFlow does not upload it to '
                      'another service.',
                ],
                footnote:
                    'A whole-workspace export is not offered here. Use Backup '
                    'and recovery for a protected workspace archive.',
              ),
            ),
      ),
      ListTile(
        leading: const Icon(Icons.privacy_tip_outlined),
        title: const Text('Privacy and access'),
        subtitle: const Text('Who can see and change workspace records.'),
        trailing: const Icon(Icons.chevron_right),
        onTap:
            () => _open(
              const SettingsInfoScreen(
                title: 'Privacy and access',
                icon: Icons.privacy_tip_outlined,
                summary:
                    'Access is enforced on the server with Supabase Row Level '
                    'Security. The app only shows controls that match your role.',
                points: [
                  'Staff can add and edit clients and work with their tasks, '
                      'applications, payments and documents.',
                  'Only Admins can delete critical records, manage backups and '
                      'restore data.',
                  'Everyone in the workspace can see workspace records; people '
                      'outside the workspace cannot.',
                  'Client and admin photos live in a private bucket. The app '
                      'requests short-lived signed links instead of public URLs.',
                  'Passwords are handled by Supabase auth and are never stored '
                      'on this device.',
                ],
                footnote:
                    'Workspace membership and server policies are managed in '
                    'Supabase. Ask your Admin if someone should lose access.',
              ),
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
    ]);
  }

  Widget _appearanceSection() {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final selected = ThemeController.instance.choice;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Appearance'),
            for (final choice in AppThemeChoice.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color:
                          choice == selected
                              ? scheme.primary
                              : scheme.outlineVariant,
                      width: choice == selected ? 2 : 1,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(_themeIcon(choice)),
                    title: Text(choice.label),
                    subtitle: Text(choice.description),
                    trailing: Icon(
                      choice == selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: choice == selected ? scheme.primary : null,
                    ),
                    onTap: () => ThemeController.instance.select(choice),
                  ),
                ),
              ),
          ],
        );
      },
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
                  'Consultants',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Team members and invite codes',
                  style: TextStyle(fontSize: 12.5),
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
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
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

  Widget _remindersSection() {
    return FutureBuilder<bool>(
      future: ReminderService.isEnabled,
      builder: (context, snapshot) {
        final enabled = snapshot.data ?? true;
        return SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Deadline reminders (experimental)'),
          subtitle: const Text(
            'Local reminders on this device for task due dates and '
            'application deadlines. Scheduling needs a rebuild with the '
            'Android setup and is not verified on all devices yet.',
          ),
          value: enabled,
          onChanged: (v) {
            ReminderService.setEnabled(v).then((_) => setState(() {}));
            if (v) {
              _snack(
                'Reminders on. Android will ask for notification '
                'permission the first time one is scheduled.',
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileSummary(),
          _sectionTitle('Account'),
          _accountSection(),
          _sectionTitle('Workspace'),
          _workspaceSection(),
          _sectionTitle('Integrations'),
          _integrationsSection(),
          _sectionTitle('Data and security'),
          _dataAndSecuritySection(),
          _appearanceSection(),
          _sectionTitle('About'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('About VasFlow'),
              subtitle: Text('Visa Consultant Admin Management'),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _logOut,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
