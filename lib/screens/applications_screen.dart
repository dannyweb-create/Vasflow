import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/application_record.dart';
import '../models/client_record.dart';
import '../models/options.dart';
import '../services/auth_service.dart';
import '../services/business_repositories.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../utils/dates.dart';

Color applicationStatusColor(String status, bool dark) {
  Color pick(Color light, Color darkColor) => dark ? darkColor : light;
  return switch (status) {
    'Submitted' => pick(const Color(0xFF0E7490), const Color(0xFF5FC8D8)),
    'Offer received' => pick(const Color(0xFFB0650E), const Color(0xFFE0A25A)),
    'Accepted' => pick(const Color(0xFF0A7B3E), const Color(0xFF6FDE94)),
    'Visa pending' => pick(const Color(0xFFB0650E), const Color(0xFFE0A25A)),
    'Visa approved' => pick(const Color(0xFF0A7B3E), const Color(0xFF6FDE94)),
    'Visa refused' => pick(const Color(0xFFB3261E), const Color(0xFFF2B8B5)),
    'Withdrawn' => pick(const Color(0xFF54705F), const Color(0xFF9DB8AA)),
    _ => pick(const Color(0xFF54705F), const Color(0xFF9DB8AA)),
  };
}

/// Tracks multiple university and visa applications per client. Opened from
/// the dashboard (all applications) or from a client (that client's only).
class ApplicationsScreen extends StatefulWidget {
  final AuthService auth;
  final String? clientId;

  const ApplicationsScreen({super.key, required this.auth, this.clientId});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  late final repo = ApplicationRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final clientsRepo = ClientRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  List<ClientRecord> clients = [];
  List<ApplicationRecord> applications = [];
  bool loading = true;
  String? error;
  String? statusFilter;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final apps = await repo.load();
      final cls = await clientsRepo.all();
      if (mounted) {
        setState(() {
          applications = apps;
          clients = cls;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String clientName(String clientId) {
    for (final c in clients) {
      if (c.id == clientId) return c.fullName;
    }
    return clientId.isEmpty ? 'No client' : 'Unknown client';
  }

  List<ApplicationRecord> get filtered {
    final scoped =
        widget.clientId == null
            ? applications
            : applications.where((a) => a.clientId == widget.clientId).toList();
    return scoped
        .where((a) => statusFilter == null || a.status == statusFilter)
        .toList()
      ..sort((a, b) {
        final aDate = a.deadline ?? DateTime(9999);
        final bDate = b.deadline ?? DateTime(9999);
        return aDate.compareTo(bDate);
      });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editor([ApplicationRecord? existing]) async {
    if (clients.isEmpty) {
      _snack('Add a client before creating an application.');
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ApplicationEditor(
              repo: repo,
              existing: existing,
              clients: clients,
              fixedClientId: widget.clientId,
            ),
      ),
    );
    await load();
  }

  Future<void> _delete(ApplicationRecord app) async {
    try {
      await repo.delete(app.id);
      _snack('Application deleted');
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Widget _statusBadge(String status) {
    final theme = Theme.of(context);
    final color = applicationStatusColor(
      status,
      theme.brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
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

  EdgeInsetsGeometry get _listPadding =>
      const EdgeInsets.fromLTRB(14, 8, 14, 96);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applications')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applications')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () {
                    setState(() => loading = true);
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
    final title =
        widget.clientId == null
            ? 'Applications'
            : 'Applications · ${clientName(widget.clientId!)}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editor(),
        icon: const Icon(Icons.add),
        label: const Text('New application'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    selected: statusFilter == null,
                    label: const Text('All statuses'),
                    onSelected: (_) => setState(() => statusFilter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final status in kApplicationStatuses) ...[
                    FilterChip(
                      selected: statusFilter == status,
                      label: Text(status),
                      onSelected: (_) => setState(() => statusFilter = status),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child:
                items.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flight_takeoff_outlined,
                            size: 40,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No applications yet.\nAdd the first university or visa application.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                    : ListView.separated(
                      padding: _listPadding,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final app = items[i];
                        final statusColor = applicationStatusColor(
                          app.status,
                          theme.brightness == Brightness.dark,
                        );
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              14,
                              8,
                              6,
                              8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: statusColor.withValues(
                                alpha: 0.14,
                              ),
                              child: Icon(
                                app.type.contains('Visa')
                                    ? Icons.public
                                    : Icons.school,
                                size: 20,
                                color: statusColor,
                              ),
                            ),
                            title: Text(
                              app.institution.isEmpty
                                  ? (app.course.isEmpty
                                      ? 'Untitled application'
                                      : app.course)
                                  : app.institution,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    if (app.type.isNotEmpty) app.type,
                                    if (app.course.isNotEmpty) app.course,
                                    if (app.country.isNotEmpty) app.country,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.clientId == null)
                                  Text(
                                    clientName(app.clientId),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (app.intake.isNotEmpty)
                                  Text(
                                    'Intake ${app.intake}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (app.deadline != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'Deadline ${dayLabel(app.deadline!, DateTime.now())}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                isOverdue(
                                                      app.deadline!,
                                                      DateTime.now(),
                                                    )
                                                    ? theme.colorScheme.error
                                                    : theme
                                                        .colorScheme
                                                        .onSurface
                                                        .withValues(alpha: 0.6),
                                            fontWeight:
                                                isOverdue(
                                                      app.deadline!,
                                                      DateTime.now(),
                                                    )
                                                    ? FontWeight.w700
                                                    : null,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _statusBadge(app.status),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _editor(app);
                                    if (v == 'delete') _delete(app);
                                  },
                                  itemBuilder:
                                      (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit application'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen editor for one application. When `fixedClientId` is set the
/// client is fixed and cannot be chosen.
class ApplicationEditor extends StatefulWidget {
  final ApplicationRepository repo;
  final ApplicationRecord? existing;
  final List<ClientRecord> clients;
  final String? fixedClientId;

  const ApplicationEditor({
    super.key,
    required this.repo,
    this.existing,
    required this.clients,
    this.fixedClientId,
  });

  @override
  State<ApplicationEditor> createState() => _ApplicationEditorState();
}

class _ApplicationEditorState extends State<ApplicationEditor> {
  late final _institution = TextEditingController(
    text: widget.existing?.institution ?? '',
  );
  late final _course = TextEditingController(
    text: widget.existing?.course ?? '',
  );
  late final _country = TextEditingController(
    text: widget.existing?.country ?? '',
  );
  String? _client;
  String? _intake;
  String _status = kApplicationStatuses.first;
  String _type = kApplicationTypes.first;
  DateTime? _submission;
  DateTime? _deadline;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _client = widget.existing?.clientId ?? widget.fixedClientId;
    _intake = widget.existing?.intake;
    _status = widget.existing?.status ?? kApplicationStatuses.first;
    _type = widget.existing?.type ?? kApplicationTypes.first;
    _submission = widget.existing?.submissionDate;
    _deadline = widget.existing?.deadline;
  }

  @override
  void dispose() {
    _institution.dispose();
    _course.dispose();
    _country.dispose();
    super.dispose();
  }

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  Future<void> _pickDate(bool deadline) async {
    final now = DateTime.now();
    final current = deadline ? _deadline : _submission;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => deadline ? _deadline = picked : _submission = picked);
    }
  }

  Widget _dateField(String label, DateTime? value, bool deadline) {
    Future<void> pick() => _pickDate(deadline);
    void clear() =>
        setState(() => deadline ? _deadline = null : _submission = null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: pick,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: _decor(label).copyWith(
            suffixIcon:
                value == null
                    ? const Icon(Icons.event_outlined)
                    : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Clear',
                          visualDensity: VisualDensity.compact,
                          onPressed: clear,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: pick,
                          icon: const Icon(Icons.event_outlined, size: 20),
                        ),
                      ],
                    ),
          ),
          child: Text(
            value == null ? '' : DateFormat('d MMM y').format(value),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _dropdown(
    String? value,
    String label,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    final items = [
      ...options,
      if (value != null && value.isNotEmpty && !options.contains(value)) value,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: [
          for (final v in items.toSet())
            DropdownMenuItem(value: v, child: Text(v, maxLines: 1)),
        ],
        onChanged: onChanged,
        decoration: _decor(label),
      ),
    );
  }

  Future<void> _save() async {
    if (_client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose the client this application belongs to.'),
        ),
      );
      return;
    }
    if (_submission != null &&
        _deadline != null &&
        _deadline!.isBefore(_submission!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The deadline cannot be before the submission date.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final record =
        widget.existing?.copyWith(
          clientId: _client!,
          country: _country.text.trim(),
          institution: _institution.text.trim(),
          course: _course.text.trim(),
          intake: _intake ?? '',
          status: _status,
          type: _type,
          submissionDate: _submission,
          deadline: _deadline,
        ) ??
        ApplicationRecord(
          id: widget.repo.table.local.newId(),
          clientId: _client!,
          country: _country.text.trim(),
          institution: _institution.text.trim(),
          course: _course.text.trim(),
          intake: _intake ?? '',
          status: _status,
          type: _type,
          submissionDate: _submission,
          deadline: _deadline,
          updatedAt: DateTime.now(),
        );
    String message = 'Application saved';
    try {
      await widget.repo.upsert(record);
    } catch (e) {
      message = 'Saved on this device. Online save failed: $e'.replaceFirst(
        'Exception: ',
        '',
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'New application' : 'Edit application',
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: Icon(_saving ? Icons.hourglass_top : Icons.save_outlined),
          label: const Text('Save application'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: [
            if (widget.fixedClientId == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  initialValue: _client,
                  items: [
                    for (final c in widget.clients)
                      DropdownMenuItem(value: c.id, child: Text(c.fullName)),
                  ],
                  onChanged: (v) => setState(() => _client = v),
                  decoration: _decor('Client'),
                ),
              ),
            _dropdown(
              _type,
              'Application type',
              kApplicationTypes,
              (v) => setState(() => _type = v ?? _type),
            ),
            _field(_institution, 'Institution'),
            _field(_course, 'Course'),
            _field(_country, 'Country'),
            _dropdown(
              _intake,
              'Intake',
              intakeOptions(),
              (v) => setState(() => _intake = v),
            ),
            _dropdown(
              _status,
              'Status',
              kApplicationStatuses,
              (v) => setState(() => _status = v ?? _status),
            ),
            _dateField('Submission date', _submission, false),
            _dateField('Deadline', _deadline, true),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: controller, decoration: _decor(label)),
  );
}
