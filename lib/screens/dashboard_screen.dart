import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../theme/brand.dart';
import '../theme/glass_widgets.dart';
import 'clients_screen.dart';
import 'pipeline_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';

class DashboardScreen extends StatefulWidget {
  final AuthService auth;
  const DashboardScreen({super.key, required this.auth});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final repo = ClientRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  int count = 0;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final c = await repo.all();
    if (mounted) setState(() => count = c.length);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// A friendly first name made from the sign-in email (until profiles have names).
  String _firstName() {
    final email = widget.auth.currentEmail;
    if (email.isEmpty) return '';
    final cleaned = email
        .split('@')
        .first
        .replaceAll(RegExp(r'[._\-0-9]+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';
    final first = cleaned.split(' ').first;
    return first[0].toUpperCase() + first.substring(1);
  }

  Future<void> _open(Widget screen, {bool refreshAfter = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (refreshAfter) await refresh();
  }

  Widget _heroCard() {
    final glass = isGlass(context);
    final workspace = widget.auth.workspaceName;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.deepGreen, Brand.green],
        ),
        border: glass
            ? Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Brand.deepGreen.withValues(alpha: glass ? 0.28 : 0.18),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  workspace.isEmpty
                      ? 'Clients in your workspace'
                      : 'Clients in $workspace',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Keep every application moving forward.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flight_takeoff_rounded,
              size: 34,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = _firstName();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.travel_explore_rounded,
                size: 20,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'VasFlow',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _open(SettingsScreen(auth: widget.auth)),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Text(
              name.isEmpty ? _greeting() : '${_greeting()},',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            if (name.isNotEmpty)
              Text(name, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 18),
            _heroCard(),
            const SizedBox(height: 26),
            Text('Workspace', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _tile(
              Icons.people_alt_outlined,
              'Clients',
              'Profiles, documents and payments',
              () => _open(ClientsScreen(auth: widget.auth), refreshAfter: true),
            ),
            _tile(
              Icons.view_kanban_outlined,
              'Client pipeline',
              'Track applications by stage',
              () => _open(PipelineScreen(repo: repo)),
            ),
            _tile(
              Icons.checklist_outlined,
              'Tasks & reminders',
              'Follow-ups and next steps',
              () => _open(const TasksScreen()),
            ),
            _tile(
              Icons.bar_chart_outlined,
              'Reports & export',
              'Export your client list as CSV',
              () => _open(ClientsScreen(auth: widget.auth, exportOnly: true)),
            ),
            _tile(
              Icons.smart_toy_outlined,
              'Private AI assistant',
              'Private workspace placeholder',
              () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  title: Text('Private AI assistant'),
                  content: Text(
                    'Connect an AI provider through a secure backend before '
                    'enabling this feature. Never put a private AI API key in '
                    'the Flutter app.',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
