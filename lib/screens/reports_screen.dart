import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/application_record.dart';
import '../models/client_record.dart';
import '../models/document_record.dart';
import '../models/payment_record.dart';
import '../models/stages.dart';
import '../models/task_record.dart';
import '../services/auth_service.dart';
import '../services/business_repositories.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../utils/file_export.dart';
import 'clients_screen.dart';

/// Real summaries over saved records, plus CSV exports for applications and
/// payments (clients export lives inside Clients for its search & filters).
class ReportsScreen extends StatefulWidget {
  final AuthService auth;
  const ReportsScreen({super.key, required this.auth});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final clientsRepo = ClientRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final appsRepo = ApplicationRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final paysRepo = PaymentRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final docsRepo = DocumentRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  final store = LocalStore();

  List<ClientRecord> clients = const [];
  List<ApplicationRecord> applications = const [];
  List<PaymentRecord> payments = const [];
  List<DocumentRecord> documents = const [];
  List<TaskRecord> tasks = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final cls = await clientsRepo.all();
    final apps = await appsRepo.load();
    final pays = await paysRepo.load();
    final docs = await docsRepo.load();
    final tsks = await store.getTasks();
    if (mounted) {
      setState(() {
        clients = cls;
        applications = apps;
        payments = pays;
        documents = docs;
        tasks = tsks;
        loading = false;
      });
    }
  }

  List<ClientRecord> get active => clients.where((c) => !c.archived).toList();

  int get _openTasks => tasks.where((t) => !t.done).length;
  int get _overdueTasks {
    final now = DateTime.now();
    return tasks
        .where(
          (t) =>
              !t.done &&
              t.dueDate != null &&
              t.dueDate!.isBefore(DateTime(now.year, now.month, now.day)),
        )
        .length;
  }

  double get _billed => payments.fold(0.0, (sum, p) => sum + p.amount);
  double get _paid => payments.fold(0.0, (sum, p) => sum + p.paidAmount);

  Future<void> _exportApplications(BuildContext context) async {
    final nameOf = {for (final c in clients) c.id: c.fullName};
    final rows = <List<dynamic>>[
      [
        'Client',
        'Type',
        'Institution',
        'Course',
        'Country',
        'Intake',
        'Status',
        'Submitted',
        'Deadline',
      ],
      ...applications.map(
        (a) => [
          nameOf[a.clientId] ?? a.clientId,
          a.type,
          a.institution,
          a.course,
          a.country,
          a.intake,
          a.status,
          a.submissionDate == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(a.submissionDate!),
          a.deadline == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(a.deadline!),
        ],
      ),
    ];
    if (!context.mounted) return;
    await exportCsv(
      context,
      rows,
      fileName: 'vasflow-applications.csv',
      dialogTitle: 'Export VasFlow applications',
    );
  }

  Future<void> _exportPayments(BuildContext context) async {
    final nameOf = {for (final c in clients) c.id: c.fullName};
    final rows = <List<dynamic>>[
      [
        'Client',
        'Fee type',
        'Description',
        'Amount',
        'Paid',
        'Outstanding',
        'Paid date',
        'Reference',
      ],
      ...payments.map(
        (p) => [
          nameOf[p.clientId] ?? p.clientId,
          p.feeType,
          p.description,
          moneyAmount(p.amount),
          moneyAmount(p.paidAmount),
          moneyAmount(p.outstanding),
          p.paidDate == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(p.paidDate!),
          p.reference,
        ],
      ),
    ];
    if (!context.mounted) return;
    await exportCsv(
      context,
      rows,
      fileName: 'vasflow-payments.csv',
      dialogTitle: 'Export VasFlow payments',
    );
  }

  Widget _summaryTile(String value, String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        margin: const EdgeInsets.all(4),
        child: Column(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
                fontSize: 11,
              ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & export')),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                  children: [
                    Row(
                      children: [
                        _summaryTile(
                          '${active.length}',
                          'Active clients',
                          Icons.people_alt_outlined,
                        ),
                        _summaryTile(
                          '${applications.length}',
                          'Applications',
                          Icons.flight_takeoff_outlined,
                        ),
                        _summaryTile(
                          '${documents.length}',
                          'Documents',
                          Icons.folder_open_outlined,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _summaryTile(
                          '$_openTasks',
                          'Open tasks',
                          Icons.task_alt_outlined,
                        ),
                        _summaryTile(
                          '$_overdueTasks',
                          'Overdue tasks',
                          Icons.warning_amber_outlined,
                        ),
                        _summaryTile(
                          '${clients.length - active.length}',
                          'Archived clients',
                          Icons.archive_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Money summary',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            _moneyRow('Total billed', moneyAmount(_billed)),
                            _moneyRow('Total paid', moneyAmount(_paid)),
                            _moneyRow(
                              'Outstanding',
                              moneyAmount(_billed - _paid),
                              highlight: _billed - _paid > 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clients by pipeline stage',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            for (final stage in kClientStages)
                              _stageRow(stage, active),
                            if (active.isEmpty)
                              Text(
                                'No active clients yet.',
                                style: theme.textTheme.bodySmall,
                              ),
                            if (applications.isNotEmpty) ...[
                              const Divider(height: 24),
                              Text(
                                'Applications by status',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),
                              for (final status
                                  in applications.map((a) => a.status).toSet())
                                _statusRow(status),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.file_download_outlined),
                            title: const Text('Export clients as CSV'),
                            subtitle: const Text(
                              'Opens the client list export',
                            ),
                            onTap:
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => ClientsScreen(
                                          auth: widget.auth,
                                          exportOnly: true,
                                        ),
                                  ),
                                ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.file_download_outlined),
                            title: const Text('Export applications as CSV'),
                            onTap: () => _exportApplications(context),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.file_download_outlined),
                            title: const Text('Export payments as CSV'),
                            onTap: () => _exportPayments(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Summaries come from saved records only - nothing here is '
                      'estimated or generated.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  Widget _moneyRow(String label, String value, {bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: highlight ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ],
        ),
      );

  Widget _stageRow(String stage, List<ClientRecord> activeClients) {
    final count = activeClients.where((c) => c.stage == stage).length;
    final fraction =
        activeClients.isEmpty
            ? 0.0
            : (count / activeClients.length).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(
              stage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String status) {
    final count = applications.where((a) => a.status == status).length;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              '$count record${count == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
