import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_record.dart';
import '../models/stages.dart';
import '../services/auth_service.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../theme/glass_widgets.dart';
import '../utils/dates.dart';
import '../utils/file_export.dart';
import 'applications_screen.dart';
import 'client_form_screen.dart';
import 'documents_screen.dart';
import 'payments_screen.dart';

/// Client list: search, stage/country filters, list/grid cards, archived
/// view, and quick access to details, editing, Applications, Documents and
/// Payments. All data comes from the real repository (Supabase + cache).
class ClientsScreen extends StatefulWidget {
  final AuthService auth;
  final bool exportOnly;
  const ClientsScreen({super.key, required this.auth, this.exportOnly = false});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late final repo = ClientRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  final search = TextEditingController();
  List<ClientRecord> clients = [];
  bool loading = true;
  String? loadError;
  String? stageFilter;
  String? countryFilter;
  bool showArchived = false;
  bool gridMode = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final c = await repo.all();
      if (mounted) {
        setState(() {
          clients = c;
          loading = false;
          loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  List<ClientRecord> get filtered {
    final q = search.text.trim().toLowerCase();
    return clients.where((c) {
        if (c.archived != showArchived) return false;
        if (stageFilter != null && c.stage != stageFilter) return false;
        if (countryFilter != null && c.country != countryFilter) {
          return false;
        }
        if (q.isNotEmpty) {
          final haystack =
              '${c.fullName} ${c.email} ${c.phone} ${c.country}'.toLowerCase();
          if (!haystack.contains(q)) return false;
        }
        return true;
      }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<String> get availableCountries =>
      ({
          for (final c in clients)
            if (c.country.trim().isNotEmpty) c.country.trim(),
        }.toList()
        ..sort());

  List<String> get availableStages {
    final present = {for (final c in clients) c.stage};
    return [
      ...kClientStages.where(present.contains),
      ...present.where((s) => !kClientStages.contains(s)).toList()..sort(),
    ];
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openForm([ClientRecord? existing]) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ClientFormScreen(
              repo: repo,
              auth: widget.auth,
              existing: existing,
            ),
      ),
    );
    await load();
  }

  Future<void> _setArchived(ClientRecord c) async {
    try {
      await repo.setArchived(c.id, !c.archived);
      _snack(
        c.archived ? 'Client restored to the active list' : 'Client archived',
      );
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _delete(ClientRecord c) async {
    if (widget.auth.role != 'admin') {
      _snack('Only an Admin can delete critical data.');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete client?'),
            content: Text(
              'Delete ${c.fullName}? History, applications, documents and '
              'payments stay on the server unless their workspace rules say '
              'otherwise.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (yes != true) return;
    try {
      await repo.delete(c.id);
      _snack('Client deleted');
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _exportCsv() async {
    final rows = <List<dynamic>>[
      [
        'Name',
        'Email',
        'Phone',
        'Country',
        'University',
        'Passport',
        'Visa status',
        'Stage',
        'Updated',
      ],
      ...filtered.map(
        (c) => [
          c.fullName,
          c.email,
          c.phone,
          c.country,
          c.university,
          c.passportNumber,
          c.visaStatus,
          c.stage,
          DateFormat('yyyy-MM-dd').format(c.updatedAt),
        ],
      ),
    ];
    await exportCsv(
      context,
      rows,
      fileName: 'vasflow-clients.csv',
      dialogTitle: 'Export VasFlow clients',
    );
  }

  Color _stageColor(String stage) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Color pick(Color light, Color darkColor) => dark ? darkColor : light;
    return switch (stage) {
      'New lead' => pick(const Color(0xFF0E7490), const Color(0xFF5FC8D8)),
      'Consultation' => pick(const Color(0xFF0F766E), const Color(0xFF66C9B2)),
      'Documents' => pick(const Color(0xFFB45309), const Color(0xFFE0A25A)),
      'Application submitted' => pick(
        const Color(0xFF0A7B3E),
        const Color(0xFF6FDE94),
      ),
      'Visa decision' => pick(const Color(0xFF076B4E), const Color(0xFF8FE6B7)),
      'Completed' => pick(const Color(0xFF0BA84A), const Color(0xFF7FE39F)),
      _ => pick(const Color(0xFF54705F), const Color(0xFF9DB8AA)),
    };
  }

  Widget _stageBadge(String stage) {
    final theme = Theme.of(context);
    final color = _stageColor(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _avatar(ClientRecord c, {double size = 46}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _clientRow(ClientRecord c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        radius: 20,
        onTap: () => _showDetails(c),
        child: Row(
          children: [
            _avatar(c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _stageBadge(c.stage),
                      if (c.country.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.place_outlined,
                          size: 13,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            c.country,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: Icon(
                Icons.more_vert,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
              onSelected: (action) {
                switch (action) {
                  case 'edit':
                    _openForm(c);
                  case 'applications':
                    _openApplications(c);
                  case 'documents':
                    _openDocuments(c);
                  case 'payments':
                    _openPayments(c);
                  case 'archive':
                    _setArchived(c);
                  case 'delete':
                    _delete(c);
                }
              },
              itemBuilder:
                  (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit client'),
                    ),
                    const PopupMenuItem(
                      value: 'applications',
                      child: Text('Applications'),
                    ),
                    const PopupMenuItem(
                      value: 'documents',
                      child: Text('Documents'),
                    ),
                    const PopupMenuItem(
                      value: 'payments',
                      child: Text('Payments'),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(c.archived ? 'Restore client' : 'Archive'),
                    ),
                    if (widget.auth.role == 'admin')
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                  ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _clientCard(ClientRecord c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      radius: 20,
      onTap: () => _showDetails(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(c, size: 42),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      _openForm(c);
                    case 'archive':
                      _setArchived(c);
                    case 'delete':
                      _delete(c);
                  }
                },
                itemBuilder:
                    (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(c.archived ? 'Restore' : 'Archive'),
                      ),
                      if (widget.auth.role == 'admin')
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                    ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            c.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          _stageBadge(c.stage),
          const Spacer(),
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 13,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  c.country.isEmpty ? 'No country yet' : c.country,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openApplications(ClientRecord c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ApplicationsScreen(auth: widget.auth, clientId: c.id),
      ),
    );
    await load();
  }

  Future<void> _openDocuments(ClientRecord c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentsScreen(auth: widget.auth, clientId: c.id),
      ),
    );
    await load();
  }

  Future<void> _openPayments(ClientRecord c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsScreen(auth: widget.auth, clientId: c.id),
      ),
    );
    await load();
  }

  void _showDetails(ClientRecord c) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Row(
              children: [
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    c.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.stage} · Visa: ${c.visaStatus}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text('Email: ${c.email.isEmpty ? '—' : c.email}'),
                    Text('Phone: ${c.phone.isEmpty ? '—' : c.phone}'),
                    Text('Country: ${c.country.isEmpty ? '—' : c.country}'),
                    Text(
                      'University: ${c.university.isEmpty ? '—' : c.university}',
                    ),
                    Text('Nationality: ${c.details['nationality'] ?? '—'}'),
                    Text('Course: ${c.details['intended_course'] ?? '—'}'),
                    Text(
                      'Study level: ${c.details['study_level'] ?? '—'} · '
                      'Intake: ${c.details['intake'] ?? '—'}',
                    ),
                    Text(
                      'Passport: ${c.passportNumber.isEmpty ? '—' : c.passportNumber}',
                    ),
                    if (c.details['passport_expiry_date'] is String &&
                        '${c.details['passport_expiry_date']}'.isNotEmpty)
                      Text(
                        'Passport expires: ${dayLabel(ClientRecord.dateFromDetails(c.details, 'passport_expiry_date')!, DateTime.now())}',
                      ),
                    if (c.details['consultant'] is String &&
                        '${c.details['consultant']}'.isNotEmpty)
                      Text('Consultant: ${c.details['consultant']}'),
                    if (ClientRecord.receivedDocuments(c.details).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Documents on file: '
                          '${ClientRecord.receivedDocuments(c.details).join(', ')}',
                        ),
                      ),
                    if (c.notes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Notes: ${c.notes}'),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Updated ${timeAgo(c.updatedAt, DateTime.now())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _openApplications(c);
                          },
                          icon: const Icon(
                            Icons.flight_takeoff_outlined,
                            size: 18,
                          ),
                          label: const Text('Applications'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _openDocuments(c);
                          },
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 18,
                          ),
                          label: const Text('Documents'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _openPayments(c);
                          },
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('Payments'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _setArchived(c);
                },
                child: Text(c.archived ? 'Restore' : 'Archive'),
              ),
              if (widget.auth.role == 'admin')
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _delete(c);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Delete'),
                ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openForm(c);
                },
                child: const Text('Edit'),
              ),
            ],
          ),
    );
  }

  Future<(bool, String?)?> _pickFilter(
    String title,
    String? current,
    List<String> options,
  ) async => showModalBottomSheet<(bool, String?)>(
    context: context,
    builder:
        (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                title: const Text('All'),
                trailing: current == null ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, (true, null)),
              ),
              for (final option in options)
                ListTile(
                  title: Text(option),
                  trailing: current == option ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(sheetContext, (true, option)),
                ),
            ],
          ),
        ),
  );

  Widget _filters() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            FilterChip(
              selected: stageFilter != null,
              label: Text(stageFilter ?? 'Status: All'),
              onSelected: (_) async {
                final picked = await _pickFilter(
                  'Filter by stage',
                  stageFilter,
                  availableStages,
                );
                if (picked != null) setState(() => stageFilter = picked.$2);
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: countryFilter != null,
              label: Text(countryFilter ?? 'Country: All'),
              onSelected: (_) async {
                final picked = await _pickFilter(
                  'Filter by destination country',
                  countryFilter,
                  availableCountries,
                );
                if (picked != null) setState(() => countryFilter = picked.$2);
              },
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: showArchived,
              avatar: Icon(
                Icons.archive_outlined,
                size: 16,
                color: showArchived ? scheme.onSecondaryContainer : null,
              ),
              label: const Text('Archived'),
              onSelected: (v) => setState(() => showArchived = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyList() {
    final items = filtered;
    if (gridMode) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 150,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _clientCard(items[i]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
      itemCount: items.length,
      itemBuilder: (context, i) => _clientRow(items[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.exportOnly ? 'Reports & export' : 'Clients'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.exportOnly ? 'Reports & export' : 'Clients'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      loading = true;
                      loadError = null;
                    });
                    load();
                  },
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final items = filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exportOnly ? 'Reports & export' : 'Clients'),
        actions: [
          if (!widget.exportOnly)
            IconButton(
              tooltip: gridMode ? 'List view' : 'Grid view',
              onPressed: () => setState(() => gridMode = !gridMode),
              icon: Icon(
                gridMode ? Icons.view_list_outlined : Icons.grid_view_outlined,
              ),
            ),
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton:
          widget.exportOnly
              ? FloatingActionButton.extended(
                onPressed: _exportCsv,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export CSV'),
              )
              : FloatingActionButton.extended(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add client'),
              ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search name, email or phone',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                suffixIcon:
                    search.text.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            search.clear();
                            setState(() {});
                          },
                        ),
              ),
            ),
          ),
          if (!widget.exportOnly) _filters(),
          Expanded(
            child:
                items.isEmpty
                    ? Center(
                      child: Text(
                        search.text.isNotEmpty ||
                                stageFilter != null ||
                                countryFilter != null
                            ? 'No clients match these filters.'
                            : showArchived
                            ? 'No archived clients.'
                            : 'No clients yet. Add your first client with the button below.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    )
                    : _bodyList(),
          ),
        ],
      ),
    );
  }
}
