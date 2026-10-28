import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_record.dart';
import '../services/auth_service.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';

const List<String> kClientStages = [
  'New lead',
  'Consultation',
  'Documents',
  'Application submitted',
  'Visa decision',
  'Completed',
];

class ClientsScreen extends StatefulWidget {
  final AuthService auth;
  final bool exportOnly;
  const ClientsScreen({super.key, required this.auth, this.exportOnly = false});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final repo = ClientRepository(LocalStore());
  final search = TextEditingController();
  List<ClientRecord> clients = [];
  bool loading = true;

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
    final c = await repo.all();
    if (mounted) {
      setState(() {
        clients = c;
        loading = false;
      });
    }
  }

  List<ClientRecord> get filtered {
    final q = search.text.toLowerCase();
    return clients
        .where(
          (c) => '${c.fullName} ${c.email} ${c.phone} ${c.country}'
              .toLowerCase()
              .contains(q),
        )
        .toList();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> addOrEdit([ClientRecord? old]) async {
    final name = TextEditingController(text: old?.fullName ?? '');
    final email = TextEditingController(text: old?.email ?? '');
    final phone = TextEditingController(text: old?.phone ?? '');
    final country = TextEditingController(text: old?.country ?? '');
    final uni = TextEditingController(text: old?.university ?? '');
    final passport = TextEditingController(text: old?.passportNumber ?? '');
    final notes = TextEditingController(text: old?.notes ?? '');
    String stage = old?.stage ?? kClientStages.first;
    // A stage saved on the server that is not in our list would crash the dropdown.
    if (!kClientStages.contains(stage)) stage = kClientStages.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(old == null ? 'Add client' : 'Edit client'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(name, 'Full name *'),
                  _field(email, 'Email'),
                  _field(phone, 'Phone'),
                  _field(country, 'Preferred country'),
                  _field(uni, 'Preferred university'),
                  _field(passport, 'Passport number'),
                  _field(notes, 'Notes', lines: 3),
                  DropdownButtonFormField<String>(
                    value: stage,
                    decoration: const InputDecoration(labelText: 'Pipeline stage'),
                    items: kClientStages
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => stage = v ?? kClientStages.first),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (name.text.trim().isEmpty) {
      _snack('A client name is required, so nothing was saved.');
      return;
    }
    final rec = ClientRecord(
      id: old?.id ?? LocalStore().newId(),
      fullName: name.text.trim(),
      email: email.text.trim(),
      phone: phone.text.trim(),
      country: country.text.trim(),
      university: uni.text.trim(),
      passportNumber: passport.text.trim(),
      notes: notes.text.trim(),
      stage: stage,
      updatedAt: DateTime.now(),
      visaStatus: old?.visaStatus ?? 'Not started',
    );
    try {
      await repo.upsert(rec);
    } catch (e) {
      _snack('Online save failed: $e');
    }
    await load();
  }

  Widget _field(TextEditingController c, String label, {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> exportCsv() async {
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
    final content = const ListToCsvConverter().convert(rows);
    final bytes = Uint8List.fromList(utf8.encode(content));
    // On Android/iOS the file picker writes the file itself and needs the bytes.
    // On desktop it only returns a path and we write the file ourselves.
    final onMobile = Platform.isAndroid || Platform.isIOS;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export VasFlow clients',
        fileName: 'vasflow-clients.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: onMobile ? bytes : null,
      );
      if (path == null) return; // person cancelled
      if (!onMobile) await File(path).writeAsBytes(bytes);
      _snack('CSV exported');
    } catch (e) {
      _snack('Could not export the CSV file: $e');
    }
  }

  Future<void> _onMenu(String action, ClientRecord c) async {
    if (action == 'edit') {
      await addOrEdit(c);
    } else if (action == 'documents') {
      _snack('Document upload is not available yet.');
    } else if (action == 'delete') {
      if (widget.auth.role != 'admin') {
        _snack('Only an Admin can delete critical data.');
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete client?'),
          content: Text('Delete ${c.fullName}?'),
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
      } catch (e) {
        _snack('$e'.replaceFirst('Exception: ', ''));
      }
      await load();
    }
  }

  void _showDetails(ClientRecord c) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(c.fullName),
        content: Text(
          'Email: ${c.email}\n'
          'Phone: ${c.phone}\n'
          'Country: ${c.country}\n'
          'University: ${c.university}\n'
          'Passport: ${c.passportNumber}\n'
          'Visa status: ${c.visaStatus}\n'
          'Notes: ${c.notes}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _clientTile(ClientRecord c) {
    final country = c.country.isEmpty ? 'Country not set' : c.country;
    final contact = c.email.isEmpty ? c.phone : c.email;
    return ListTile(
      leading: CircleAvatar(
        child: Text(c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase()),
      ),
      title: Text(
        c.fullName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$country · ${c.stage}\n$contact',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _onMenu(v, c),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit profile')),
          PopupMenuItem(value: 'documents', child: Text('Documents (coming soon)')),
          PopupMenuItem(value: 'delete', child: Text('Delete (Admin only)')),
        ],
      ),
      onTap: () => _showDetails(c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exportOnly ? 'Reports & export' : 'Clients'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: exportCsv,
            icon: const Icon(Icons.file_download_outlined),
          ),
          if (!widget.exportOnly)
            IconButton(
              tooltip: 'Add client',
              onPressed: () => addOrEdit(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search clients by name, email, phone or country',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          search.text.isEmpty
                              ? 'No clients yet. Tap + to add your first client.'
                              : 'No clients match your search.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) => _clientTile(items[i]),
                      ),
          ),
        ],
      ),
    );
  }
}
