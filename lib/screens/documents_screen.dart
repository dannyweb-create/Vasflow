import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/client_record.dart';
import '../models/document_record.dart';
import '../models/options.dart';
import '../services/auth_service.dart';
import '../services/business_repositories.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../utils/dates.dart';
import '../utils/file_export.dart';

/// Client documents. Files live in a PRIVATE Supabase Storage bucket
/// (workspace_id/client_id/uuid-filename). Metadata rows are in the
/// `client_documents` table. Upload/download/delete all need the backend -
/// nothing is faked when it is not configured.
class DocumentsScreen extends StatefulWidget {
  final AuthService auth;
  final String? clientId;

  const DocumentsScreen({super.key, required this.auth, this.clientId});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  static const _maxUploadBytes = 20 * 1024 * 1024;

  late final docsRepo = DocumentRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  late final clientsRepo = ClientRepository(
    LocalStore(),
    workspaceId: widget.auth.workspaceId,
  );
  List<DocumentRecord> documents = [];
  List<ClientRecord> clients = [];
  bool loading = true;
  String? error;
  String? categoryFilter;
  final search = TextEditingController();

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
      final docs = await docsRepo.load();
      final cls = await clientsRepo.all();
      if (mounted) {
        setState(() {
          documents = docs;
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

  List<DocumentRecord> get filtered {
    final scoped =
        widget.clientId == null
            ? documents
            : documents.where((d) => d.clientId == widget.clientId).toList();
    final q = search.text.trim().toLowerCase();
    return scoped
        .where(
          (d) =>
              (categoryFilter == null || d.category == categoryFilter) &&
              (q.isEmpty ||
                  '${d.name} ${d.category} ${clientName(d.clientId)}'
                      .toLowerCase()
                      .contains(q)),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _backendReady => !docsRepo.backendRequired;

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
      return Icons.image_outlined;
    }
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    if (['doc', 'docx', 'rtf'].contains(ext)) return Icons.description_outlined;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _mimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _upload() async {
    if (!_backendReady) {
      _snack(
        'Documents upload needs Supabase. '
        'Set SUPABASE_URL / SUPABASE_ANON_KEY and run phase4_features.sql.',
      );
      return;
    }
    if (widget.auth.workspaceId == null) return;
    String clientId = widget.clientId ?? '';
    if (widget.clientId == null) {
      if (clients.isEmpty) {
        _snack('Add a client before uploading documents.');
        return;
      }
      clientId = await _pickClient();
      if (clientId.isEmpty) return;
    }
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    if ((file.size) > _maxUploadBytes) {
      _snack('File is larger than 20 MB. Split it or compress first.');
      return;
    }
    final bytes = file.bytes!;
    final cleanName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final fileName = '${docsRepo.table.local.newId()}-$cleanName';
    _snack('Uploading…');
    try {
      final path = await docsRepo.upload(
        workspaceFolder: widget.auth.workspaceId!,
        clientFolder: clientId,
        fileName: fileName,
        bytes: bytes,
        contentType: _mimeType(file.name),
      );
      await docsRepo.upsert(
        DocumentRecord(
          id: docsRepo.table.local.newId(),
          clientId: clientId,
          name: file.name,
          category: categoryFilter ?? kDocumentTypes.last,
          filePath: path,
          mimeType: _mimeType(file.name),
          sizeBytes: bytes.length,
          uploadedBy: widget.auth.currentEmail,
          updatedAt: DateTime.now(),
        ),
      );
      _snack('Document uploaded');
      await load();
    } catch (e) {
      _snack('Upload failed: $e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<String> _pickClient() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Which client is this document for?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                for (final c in clients)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(c.fullName.isEmpty ? '?' : c.fullName[0]),
                    ),
                    title: Text(c.fullName),
                    onTap: () => Navigator.pop(sheetContext, c.id),
                  ),
              ],
            ),
          ),
    );
    return picked ?? '';
  }

  Future<void> _download(DocumentRecord doc) async {
    if (!_backendReady) {
      _snack('Downloads need a Supabase connection.');
      return;
    }
    try {
      final bytes = await docsRepo.download(doc.filePath);
      if (bytes == null) return;
      if (mounted) {
        await saveBytes(
          context,
          Uint8List.fromList(bytes),
          fileName: doc.name,
          dialogTitle: 'Save document copy',
        );
      }
    } catch (e) {
      _snack('Download failed: $e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _delete(DocumentRecord doc) async {
    if (!widget.auth.isAdmin) {
      _snack('Only an Admin can delete client documents.');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete document?'),
            content: Text('Delete "${doc.name}" and its stored file?'),
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
      await docsRepo.removeFile(doc.filePath);
    } catch (_) {
      // Even if storage cleanup fails, still drop the row the server allows.
    }
    try {
      await docsRepo.delete(doc.id);
      _snack('Document deleted');
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editMeta(DocumentRecord doc) async {
    final name = TextEditingController(text: doc.name);
    String category = doc.category;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Document details'),
                  content: SizedBox(
                    width: 400,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: 'Display name',
                            ),
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          items: [
                            for (final t in kDocumentTypes)
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          onChanged:
                              (v) => setDialogState(
                                () => category = v ?? category,
                              ),
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                        ),
                      ],
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
    try {
      await docsRepo.upsert(
        doc.copyWith(
          name: name.text.trim().isEmpty ? doc.name : name.text.trim(),
          category: category,
        ),
      );
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documents')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documents')),
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
            ? 'Documents'
            : 'Documents · ${clientName(widget.clientId!)}';
    final categoriesUsed = {
      for (final d
          in (widget.clientId == null
              ? documents
              : documents.where((d) => d.clientId == widget.clientId)))
        d.category,
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _upload,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Add document'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search documents',
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
          if (!_backendReady)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Offline view. Uploads and downloads need Supabase.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    selected: categoryFilter == null,
                    label: const Text('All types'),
                    onSelected: (_) => setState(() => categoryFilter = null),
                  ),
                  const SizedBox(width: 8),
                  for (final category in kDocumentTypes.where(
                    categoriesUsed.contains,
                  )) ...[
                    FilterChip(
                      selected: categoryFilter == category,
                      label: Text(category),
                      onSelected:
                          (_) => setState(() => categoryFilter = category),
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
                            Icons.folder_open_outlined,
                            size: 40,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No documents here yet.\nUse Add document to upload passports, transcripts and more.',
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
                        final doc = items[i];
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
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Icon(
                                _fileIcon(doc.name),
                                size: 20,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              doc.name,
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
                                  doc.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.clientId == null)
                                  Text(
                                    clientName(doc.clientId),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                Text(
                                  [
                                    if (_sizeLabel(doc.sizeBytes).isNotEmpty)
                                      _sizeLabel(doc.sizeBytes),
                                    timeAgo(doc.updatedAt, DateTime.now()),
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'download') _download(doc);
                                if (v == 'edit') _editMeta(doc);
                                if (v == 'delete') _delete(doc);
                              },
                              itemBuilder:
                                  (menuContext) => [
                                    const PopupMenuItem(
                                      value: 'download',
                                      child: Text('Download a copy'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Rename / recategorize'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      enabled: widget.auth.isAdmin,
                                      child: Text(
                                        widget.auth.isAdmin
                                            ? 'Delete (Admin)'
                                            : 'Delete (Admin only)',
                                      ),
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
