import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_record.dart';
import '../models/options.dart';
import '../models/payment_record.dart';
import '../services/auth_service.dart';
import '../services/business_repositories.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../utils/file_export.dart';

/// Consultation fees, application fees, amounts paid, balances and
/// transaction references per client. Balance = amount - paid_amount.
class PaymentsScreen extends StatefulWidget {
  final AuthService auth;
  final String? clientId;

  const PaymentsScreen({super.key, required this.auth, this.clientId});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late final repo = PaymentRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final clientsRepo = ClientRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  List<PaymentRecord> payments = [];
  List<ClientRecord> clients = [];
  bool loading = true;
  String? error;
  String? feeFilter;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final pays = await repo.load();
      final cls = await clientsRepo.all();
      if (mounted) {
        setState(() {
          payments = pays;
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
    return 'Removed client';
  }

  List<PaymentRecord> get filtered {
    final scoped =
        widget.clientId == null
            ? payments
            : payments.where((p) => p.clientId == widget.clientId).toList();
    return scoped
        .where((p) => feeFilter == null || p.feeType == feeFilter)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  double get _billed => filtered.fold(0, (sum, p) => sum + p.amount);
  double get _paidTotal => filtered.fold(0, (sum, p) => sum + p.paidAmount);
  double get _outstanding => filtered.fold(0, (sum, p) => sum + p.outstanding);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editor([PaymentRecord? existing]) async {
    if (clients.isEmpty) {
      _snack('Add a client before recording payments.');
      return;
    }
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (_) => PaymentEditor(
              repo: repo,
              existing: existing,
              clients: clients,
              fixedClientId: widget.clientId,
            ),
      ),
    );
    await load();
  }

  Future<void> _delete(PaymentRecord payment) async {
    try {
      await repo.delete(payment.id);
      _snack('Payment record deleted');
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _exportCsv() async {
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
        'Updated',
      ],
      ...filtered.map(
        (p) => [
          clientName(p.clientId),
          p.feeType,
          p.description,
          moneyAmount(p.amount),
          moneyAmount(p.paidAmount),
          moneyAmount(p.outstanding),
          p.paidDate == null
              ? ''
              : DateFormat('yyyy-MM-dd').format(p.paidDate!),
          p.reference,
          DateFormat('yyyy-MM-dd').format(p.updatedAt),
        ],
      ),
    ];
    if (!mounted) return;
    await exportCsv(
      context,
      rows,
      fileName: 'vasflow-payments.csv',
      dialogTitle: 'Export VasFlow payments',
    );
  }

  Widget _summaryCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(child: _summaryCell('Billed', moneyAmount(_billed))),
            Container(width: 1, height: 34, color: scheme.outlineVariant),
            Expanded(child: _summaryCell('Paid', moneyAmount(_paidTotal))),
            Container(width: 1, height: 34, color: scheme.outlineVariant),
            Expanded(
              child: _summaryCell(
                'Outstanding',
                moneyAmount(_outstanding),
                highlight: _outstanding > 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCell(String label, String value, {bool highlight = false}) =>
      Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: highlight ? Theme.of(context).colorScheme.error : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      );

  Color _feeColor(String feeType, bool dark) => switch (feeType) {
    'Consultation fee' =>
      dark ? const Color(0xFF5FC8D8) : const Color(0xFF0E7490),
    'Application fee' =>
      dark ? const Color(0xFF6FDE94) : const Color(0xFF0A7B3E),
    'Tuition deposit' =>
      dark ? const Color(0xFF8FE6B7) : const Color(0xFF076B4E),
    'Visa fee' => dark ? const Color(0xFFE0A25A) : const Color(0xFFB0650E),
    _ => dark ? const Color(0xFF9DB8AA) : const Color(0xFF54705F),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Payments')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Payments')),
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
            ? 'Payments'
            : 'Payments · ${clientName(widget.clientId!)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: items.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editor(),
        icon: const Icon(Icons.add),
        label: const Text('Record payment'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _summaryCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    selected: feeFilter == null,
                    label: const Text('All fees'),
                    onSelected: (_) => setState(() => feeFilter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final fee in kFeeTypes) ...[
                    FilterChip(
                      selected: feeFilter == fee,
                      label: Text(fee),
                      onSelected: (_) => setState(() => feeFilter = fee),
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
                            Icons.payments_outlined,
                            size: 40,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No payment records yet.\nRecord fees, amounts paid and references.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final payment = items[i];
                        final color = _feeColor(
                          payment.feeType,
                          theme.brightness == Brightness.dark,
                        );
                        final outstanding = payment.outstanding;
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
                              backgroundColor: color.withValues(alpha: 0.14),
                              child: Icon(
                                Icons.receipt_long_outlined,
                                size: 20,
                                color: color,
                              ),
                            ),
                            title: Text(
                              payment.description.isEmpty
                                  ? payment.feeType
                                  : payment.description,
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
                                  '${moneyAmount(payment.paidAmount)} paid of ${moneyAmount(payment.amount)}'
                                  '${payment.paidDate == null ? '' : ' · ${DateFormat('d MMM y').format(payment.paidDate!)}'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.clientId == null)
                                  Text(
                                    clientName(payment.clientId),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (payment.reference.isNotEmpty)
                                  Text(
                                    'Ref ${payment.reference}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  outstanding > 0.0001
                                      ? '${moneyAmount(outstanding)} due'
                                      : 'Paid',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color:
                                        outstanding > 0.0001
                                            ? theme.colorScheme.error
                                            : theme.colorScheme.primary,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _editor(payment);
                                    if (v == 'delete') _delete(payment);
                                  },
                                  itemBuilder:
                                      (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit payment'),
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

/// Full-screen editor for one payment. When `fixedClientId` is set the client
/// cannot be changed.
class PaymentEditor extends StatefulWidget {
  final PaymentRepository repo;
  final PaymentRecord? existing;
  final List<ClientRecord> clients;
  final String? fixedClientId;

  const PaymentEditor({
    super.key,
    required this.repo,
    this.existing,
    required this.clients,
    this.fixedClientId,
  });

  @override
  State<PaymentEditor> createState() => _PaymentEditorState();
}

class _PaymentEditorState extends State<PaymentEditor> {
  late final _description = TextEditingController(
    text: payment?.description ?? '',
  );
  late final _amount = TextEditingController(
    text: payment == null ? '' : moneyAmount(payment!.amount),
  );
  late final _paid = TextEditingController(
    text: payment == null ? '' : moneyAmount(payment!.paidAmount),
  );
  late final _reference = TextEditingController(text: payment?.reference ?? '');
  String? _client;
  String _feeType = kFeeTypes.first;
  DateTime? _paidDate;
  bool _saving = false;

  PaymentRecord? get payment => widget.existing;

  @override
  void initState() {
    super.initState();
    _client = widget.existing?.clientId ?? widget.fixedClientId;
    _feeType = widget.existing?.feeType ?? kFeeTypes.first;
    _paidDate = widget.existing?.paidDate;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _paid.dispose();
    _reference.dispose();
    super.dispose();
  }

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  double? _parse(String raw) => double.tryParse(raw.trim().replaceAll(',', ''));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _paidDate = picked);
  }

  Future<void> _save() async {
    final amount = _parse(_amount.text);
    final paid = _parse(_paid.text);
    if (_client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose the client this payment belongs to.'),
        ),
      );
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the fee amount as a number.')),
      );
      return;
    }
    if (paid == null || paid < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the amount paid (0 or more).')),
      );
      return;
    }
    if (paid > amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amount paid cannot be more than the fee.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final record =
        widget.existing?.copyWith(
          clientId: _client!,
          feeType: _feeType,
          description: _description.text.trim(),
          amount: amount,
          paidAmount: paid,
          paidDate: _paidDate,
          reference: _reference.text.trim(),
        ) ??
        PaymentRecord(
          id: widget.repo.table.local.newId(),
          clientId: _client!,
          feeType: _feeType,
          description: _description.text.trim(),
          amount: amount,
          paidAmount: paid,
          paidDate: _paidDate,
          reference: _reference.text.trim(),
          updatedAt: DateTime.now(),
        );
    String message = 'Payment saved';
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
          widget.existing == null ? 'Record payment' : 'Edit payment',
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: Icon(_saving ? Icons.hourglass_top : Icons.save_outlined),
          label: const Text('Save payment'),
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
            DropdownButtonFormField<String>(
              initialValue: _feeType,
              items: [
                for (final fee in kFeeTypes)
                  DropdownMenuItem(value: fee, child: Text(fee)),
              ],
              onChanged: (v) => setState(() => _feeType = v ?? _feeType),
              decoration: _decor('Fee type'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _description,
                decoration: _decor('Description (optional)'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decor('Fee amount'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _paid,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decor('Amount paid'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: _decor('Payment date').copyWith(
                    suffixIcon:
                        _paidDate == null
                            ? const Icon(Icons.event_outlined)
                            : IconButton(
                              tooltip: 'Clear',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() => _paidDate = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                  ),
                  child: Text(
                    _paidDate == null
                        ? ''
                        : DateFormat('d MMM y').format(_paidDate!),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            TextField(
              controller: _reference,
              decoration: _decor('Transaction reference'),
            ),
          ],
        ),
      ),
    );
  }
}
