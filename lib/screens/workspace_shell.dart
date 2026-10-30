import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backup_scheduler.dart';
import 'ai_agent_screen.dart';
import 'clients_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

/// Hosts the four bottom tabs: Home, Clients, AI and Profile.
/// An IndexedStack keeps each tab alive, so positions and loaded data are
/// preserved when moving between tabs.
class WorkspaceShell extends StatefulWidget {
  final AuthService auth;
  const WorkspaceShell({super.key, required this.auth});

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  int _tab = 0;
  late final tabNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // App-open automatic backups. The scheduler dedupes per period from the
    // server-side history, so being fired on every shell mount is safe.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      BackupScheduler.schedulerInstance.runIfDue(widget.auth);
    });
  }

  void selectTab(int index) {
    if (!mounted) return;
    setState(() => _tab = index);
    tabNotifier.value = index;
  }

  @override
  void dispose() {
    tabNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardScreen(
            auth: widget.auth,
            tabNotifier: tabNotifier,
            onSelectTab: selectTab,
          ),
          ClientsScreen(auth: widget.auth),
          const AiAgentScreen(),
          SettingsScreen(auth: widget.auth),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt_rounded),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy_rounded),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
