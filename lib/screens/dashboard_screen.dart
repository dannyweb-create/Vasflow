import 'package:flutter/material.dart';

import '../models/application_record.dart';
import '../models/client_record.dart';
import '../models/task_record.dart';
import '../models/document_record.dart';
import '../services/auth_service.dart';
import '../services/business_repositories.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../theme/glass_widgets.dart';
import '../utils/dates.dart';
import 'applications_screen.dart';
import 'clients_screen.dart';
import 'documents_screen.dart';
import 'payments_screen.dart';
import 'reports_screen.dart';
import 'tasks_screen.dart';

/// Home tab: personalized greeting, real stats from saved data, quick
/// actions, upcoming deadlines (tasks, applications, passports) and recent
/// activity. Works in Light, Dark and Liquid Glass themes.
class DashboardScreen extends StatefulWidget {
  final AuthService auth;
  final ValueNotifier<int>? tabNotifier;
  final ValueChanged<int>? onSelectTab;

  const DashboardScreen({
    super.key,
    required this.auth,
    this.tabNotifier,
    this.onSelectTab,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final repo = ClientRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final appsRepo = ApplicationRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final docsRepo = DocumentRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final store = LocalStore();

  List<ClientRecord> clients = [];
  List<ApplicationRecord> applications = [];
  List<DocumentRecord> documents = [];
  List<TaskRecord> tasks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    refresh();
    widget.tabNotifier?.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.tabNotifier?.removeListener(_onTabChanged);
    super.dispose();
  }

  int _lastTab = 0;

  void _onTabChanged() {
    final tab = widget.tabNotifier?.value ?? 0;
    if (tab == 0 && _lastTab != 0 && mounted) {
      refresh();
    }
    _lastTab = tab;
  }

  List<ClientRecord> get active => clients.where((c) => !c.archived).toList();

  Future<void> refresh() async {
    final c = await repo.all();
    final a = await appsRepo.load();
    final d = await docsRepo.load();
    final t = await store.getTasks();
    if (mounted) {
      setState(() {
        clients = c;
        applications = a;
        documents = d;
        tasks = t;
        loading = false;
      });
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _firstName() {
    final email = widget.auth.currentEmail;
    if (email.isEmpty) return '';
    final cleaned =
        email.split('@').first.replaceAll(RegExp(r'[._\-0-9]+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    final first = cleaned.split(' ').first;
    return first[0].toUpperCase() + first.substring(1);
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    await refresh();
  }

  void _openAiDialog() {
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('AI Agent moved'),
            content: const Text(
              'The assistant now lives on the AI tab at the bottom of the app. '
              'It is not connected to a provider yet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  int get _openTaskCount => tasks.where((t) => !t.done).length;

  /// Upcoming items merge three real sources: task due dates, application
  /// deadlines and passport expiry dates.
  List<_Upcoming> get _upcoming {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <_Upcoming>[];
    for (final task in tasks.where((t) => !t.done && t.dueDate != null)) {
      items.add(
        _Upcoming(
          date: task.dueDate!,
          title: task.title,
          subtitle: 'Task reminder',
          icon: Icons.task_alt_outlined,
          overdue: task.dueDate!.isBefore(today),
          open: () => _push(const TasksScreen()),
        ),
      );
    }
    for (final app in applications.where((a) => a.deadline != null)) {
      items.add(
        _Upcoming(
          date: app.deadline!,
          title:
              app.institution.isEmpty
                  ? (app.course.isEmpty ? 'Application' : app.course)
                  : '${app.institution} application',
          subtitle: 'Application deadline · ${activeName(app.clientId)}',
          icon: Icons.flight_takeoff_outlined,
          overdue: app.deadline!.isBefore(today),
          open: () => _push(ApplicationsScreen(auth: widget.auth)),
        ),
      );
    }
    final expiring =
        active
            .map(
              (c) => (
                client: c,
                expiry: ClientRecord.dateFromDetails(
                  c.details,
                  'passport_expiry_date',
                ),
              ),
            )
            .where(
              (entry) =>
                  entry.expiry != null &&
                  entry.expiry!.isBefore(DateTime(now.year + 1)),
            )
            .toList();
    for (final entry in expiring) {
      items.add(
        _Upcoming(
          date: entry.expiry!,
          title: '${entry.client.fullName} · passport expires',
          subtitle:
              'Passport of ${entry.client.country.isEmpty ? 'client' : entry.client.country} client',
          icon: Icons.badge_outlined,
          overdue: entry.expiry!.isBefore(today),
          open: () => _push(ClientsScreen(auth: widget.auth)),
        ),
      );
    }
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  String activeName(String clientId) {
    for (final c in clients) {
      if (c.id == clientId) {
        return c.fullName;
      }
    }
    return 'client';
  }

  List<ClientRecord> get _recent {
    final copy = [...active];
    copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return copy.take(4).toList();
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _statsStrip() {
    final scheme = Theme.of(context).colorScheme;
    final cells = <Widget>[
      _statCell(
        active.length,
        'Clients',
        Icons.people_alt_outlined,
        () => widget.onSelectTab?.call(1),
      ),
      _statCell(
        active.where((c) => c.stage == 'Application submitted').length,
        'In progress',
        Icons.flight_takeoff_outlined,
        () => _push(ApplicationsScreen(auth: widget.auth)),
      ),
      _statCell(
        _openTaskCount,
        'Open tasks',
        Icons.task_alt_outlined,
        () => _push(const TasksScreen()),
      ),
      _statCell(
        documents.length,
        'Documents',
        Icons.folder_open_outlined,
        () => _push(DocumentsScreen(auth: widget.auth)),
      ),
    ];
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 12),
      radius: 24,
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) Container(width: 1, color: scheme.outlineVariant),
              Expanded(child: cells[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statCell(int value, String label, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions() {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.82,
      padding: EdgeInsets.zero,
      children: [
        _actionTile(
          Icons.people_alt_outlined,
          'Clients',
          () => widget.onSelectTab?.call(1),
        ),
        _actionTile(
          Icons.flight_takeoff_outlined,
          'Applications',
          () => _push(ApplicationsScreen(auth: widget.auth)),
        ),
        _actionTile(
          Icons.task_alt_outlined,
          'Tasks',
          () => _push(const TasksScreen()),
        ),
        _actionTile(
          Icons.bar_chart_outlined,
          'Reports',
          () => _push(ReportsScreen(auth: widget.auth)),
        ),
        _actionTile(
          Icons.payments_outlined,
          'Payments',
          () => _push(PaymentsScreen(auth: widget.auth)),
        ),
        _actionTile(
          Icons.folder_open_outlined,
          'Documents',
          () => _push(DocumentsScreen(auth: widget.auth)),
        ),
        _actionTile(Icons.smart_toy_outlined, 'AI Agent', _openAiDialog),
        _actionTile(
          Icons.settings_outlined,
          'Settings',
          () => widget.onSelectTab?.call(3),
        ),
      ],
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      radius: 20,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _upcomingPanel() {
    final items = _upcoming.take(4).toList();
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      radius: 22,
      child:
          items.isEmpty
              ? InkWell(
                onTap: () => _push(const TasksScreen()),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  child: Row(
                    children: [
                      Icon(Icons.event_available_outlined),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No upcoming deadlines. Add a task or a deadline.',
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 62),
                    _upcomingRow(items[i]),
                  ],
                ],
              ),
    );
  }

  Widget _upcomingRow(_Upcoming item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overdue = item.overdue;
    return InkWell(
      onTap: item.open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (overdue ? scheme.error : scheme.primaryContainer)
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.icon,
                size: 20,
                color: overdue ? scheme.error : scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    overdue
                        ? 'Overdue · ${dayLabel(item.date, DateTime.now())}'
                        : '${item.subtitle} · ${dayLabel(item.date, DateTime.now())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          overdue
                              ? scheme.error
                              : scheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: overdue ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentPanel() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = _recent;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      radius: 22,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 62),
            InkWell(
              onTap: () => widget.onSelectTab?.call(1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        items[i].fullName.isEmpty
                            ? '?'
                            : items[i].fullName[0].toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            items[i].fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            items[i].stage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      timeAgo(items[i].updatedAt, DateTime.now()),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = _firstName();
    final workspace = widget.auth.workspaceName;
    final recent = _recent;

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
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  children: [
                    Text(
                      '${_greeting()}${name.isEmpty ? '' : ','}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    Text(
                      name.isEmpty ? 'Consultant' : name,
                      style: theme.textTheme.headlineMedium,
                    ),
                    if (workspace.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          workspace,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _statsStrip(),
                    const SizedBox(height: 18),
                    Text('Quick actions', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 10),
                    _quickActions(),
                    const SizedBox(height: 2),
                    _sectionTitle('Upcoming'),
                    _upcomingPanel(),
                    if (recent.isNotEmpty) ...[
                      _sectionTitle('Recent activity'),
                      _recentPanel(),
                    ],
                  ],
                ),
              ),
    );
  }
}

class _Upcoming {
  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool overdue;
  final VoidCallback open;

  const _Upcoming({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.overdue,
    required this.open,
  });
}
