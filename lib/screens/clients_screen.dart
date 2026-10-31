import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_record.dart';
import '../models/stages.dart';
import '../services/auth_service.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../theme/brand.dart';
import '../theme/glass_widgets.dart';
import '../utils/file_export.dart';
import '../widgets/client_avatar.dart';
import 'applications_screen.dart';
import 'client_form_screen.dart';
import 'client_profile_screen.dart';
import 'documents_screen.dart';
import 'payments_screen.dart';

/// Client list: search, stage/country filters, list/grid cards, archived
/// view, and quick access to details, editing, Applications, Documents and
/// Payments. All data comes from the real repository (Supabase + cache).
class ClientsScreen extends StatefulWidget {
  final AuthService auth;
  final bool exportOnly;

  /// Extra space below the action button. The workspace shell uses this to lift
  /// the button above its floating navigation pill.
  final double fabBottomInset;
  const ClientsScreen({
    super.key,
    required this.auth,
    this.exportOnly = false,
    this.fabBottomInset = 0,
  });

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
      ...kClientStages,
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

  Widget _avatar(ClientRecord c, {double size = 46}) =>
      ClientAvatar(photoPath: c.photoPath, name: c.fullName, size: size);

  Widget _clientRow(ClientRecord c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
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
                      Icon(
                        Icons.place_outlined,
                        size: 13,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 2),
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
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 104),
              child: _stageBadge(c.stage),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
            PopupMenuButton<String>(
              tooltip: 'Actions',
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert,
                size: 20,
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

  Future<void> _showDetails(ClientRecord c) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder:
            (_) =>
                ClientProfileScreen(auth: widget.auth, repo: repo, client: c),
      ),
    );
    await load();
  }

  Widget _searchRow() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
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
          if (!widget.exportOnly) ...[
            const SizedBox(width: 8),
            _filterButton(theme),
          ],
        ],
      ),
    );
  }

  Widget _filterButton(ThemeData theme) {
    final scheme = theme.colorScheme;
    final active = countryFilter != null || showArchived;
    return Tooltip(
      message: 'Filters',
      child: GlassPanel(
        padding: EdgeInsets.zero,
        radius: 14,
        onTap: _showFilters,
        child: SizedBox(
          width: 54,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.tune_rounded,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
              if (active)
                Positioned(
                  top: 13,
                  right: 13,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Brand.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChips() {
    final scheme = Theme.of(context).colorScheme;
    final options = <String?>[null, ...availableStages];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              ChoiceChip(
                label: Text(options[i] ?? 'All'),
                selected: stageFilter == options[i],
                showCheckmark: false,
                selectedColor: Brand.green,
                backgroundColor:
                    scheme.brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.06)
                        : scheme.surfaceContainerHighest,
                shape: StadiumBorder(
                  side: BorderSide(
                    color:
                        stageFilter == options[i]
                            ? Brand.green
                            : scheme.outline.withValues(alpha: 0.35),
                  ),
                ),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color:
                      stageFilter == options[i]
                          ? Brand.onGreen
                          : scheme.onSurface.withValues(alpha: 0.8),
                ),
                onSelected: (_) => setState(() => stageFilter = options[i]),
              ),
              if (i != options.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            void refresh() => setSheetState(() {});
            final countries = <String?>[null, ...availableCountries];
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.72,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Filters', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      Text(
                        'Country',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final country in countries)
                            ChoiceChip(
                              label: Text(country ?? 'All countries'),
                              selected: countryFilter == country,
                              showCheckmark: false,
                              selectedColor: Brand.green,
                              backgroundColor: scheme.surfaceContainerHighest,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color:
                                      countryFilter == country
                                          ? Brand.green
                                          : scheme.outline.withValues(
                                            alpha: 0.35,
                                          ),
                                ),
                              ),
                              labelStyle: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color:
                                    countryFilter == country
                                        ? Brand.onGreen
                                        : scheme.onSurface.withValues(
                                          alpha: 0.8,
                                        ),
                              ),
                              onSelected: (_) {
                                setState(() => countryFilter = country);
                                refresh();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: showArchived,
                        onChanged: (value) {
                          setState(() => showArchived = value);
                          refresh();
                        },
                        title: const Text('Archived clients'),
                        subtitle: const Text('Show clients that were archived'),
                        secondary: Icon(
                          Icons.archive_outlined,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      if (countryFilter != null || showArchived)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                countryFilter = null;
                                showArchived = false;
                              });
                              refresh();
                            },
                            icon: const Icon(
                              Icons.filter_alt_off_outlined,
                              size: 18,
                            ),
                            label: const Text('Clear filters'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _bodyList() {
    final items = filtered;
    if (gridMode) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          14,
          8,
          14,
          AppLayout.bottomContentPadding,
        ),
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
      padding: const EdgeInsets.fromLTRB(
        14,
        8,
        14,
        AppLayout.bottomContentPadding,
      ),
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
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: widget.fabBottomInset),
        child:
            widget.exportOnly
                ? FloatingActionButton.extended(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export CSV'),
                )
                : Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.glow,
                  ),
                  child: FloatingActionButton(
                    tooltip: 'Add client',
                    shape: const CircleBorder(),
                    onPressed: () => _openForm(),
                    child: const Icon(Icons.add_rounded, size: 30),
                  ),
                ),
      ),
      body: Column(
        children: [
          _searchRow(),
          if (!widget.exportOnly) _statusChips(),
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
