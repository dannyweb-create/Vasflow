import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import 'clients_screen.dart';
import 'settings_screen.dart';
import 'pipeline_screen.dart';
import 'tasks_screen.dart';

class DashboardScreen extends StatefulWidget {
  final AuthService auth; final ValueChanged<bool> onThemeChanged;
  const DashboardScreen({super.key, required this.auth, required this.onThemeChanged});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}
class _DashboardScreenState extends State<DashboardScreen> {
  late final repo = ClientRepository(LocalStore(), workspaceId: widget.auth.workspaceId);
  int count = 0;
  @override void initState() { super.initState(); refresh(); }
  Future<void> refresh() async { final c = await repo.all(); if (mounted) setState(() => count = c.length); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VasFlow'), actions: [IconButton(tooltip: 'Settings', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(auth: widget.auth, onThemeChanged: widget.onThemeChanged))), icon: const Icon(Icons.settings_outlined))]),
    body: RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(18), children: [
      Text('Good to see you', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 4), Text(widget.auth.currentEmail, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$count', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)), Text(widget.auth.workspaceName.isEmpty ? 'Clients in your workspace' : 'Clients in ${widget.auth.workspaceName}'), const SizedBox(height: 8), const Text('Keep every application moving forward.') ])),
        const Icon(Icons.flight_takeoff_rounded, size: 58),
      ])),
      const SizedBox(height: 22),
      Text('Workspace', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      _tile(context, Icons.people_alt_outlined, 'Clients', 'Profiles, documents and payments', () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsScreen(auth: widget.auth))); refresh(); }),
      _tile(context, Icons.view_kanban_outlined, 'Client pipeline', 'Track applications by stage', () => Navigator.push(context, MaterialPageRoute(builder: (_) => PipelineScreen(repo: repo)))),
      _tile(context, Icons.checklist_outlined, 'Tasks & reminders', 'Follow-ups and next steps', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen()))),
      _tile(context, Icons.bar_chart_outlined, 'Reports & export', 'Export your client list as CSV', () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsScreen(auth: widget.auth, exportOnly: true)))),
      _tile(context, Icons.smart_toy_outlined, 'Private AI assistant', 'Private workspace placeholder', () => showDialog(context: context, builder: (_) => const AlertDialog(title: Text('Private AI assistant'), content: Text('Connect an AI provider through a secure backend before enabling this feature. Never put a private AI API key in the Flutter app.')))),
    ])),
  );
  Widget _tile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7), leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right), onTap: onTap));
}
