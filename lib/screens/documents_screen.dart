import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/client_record.dart';
import '../models/document_record.dart';
import '../models/options.dart';
import '../services/auth_service.dart';
import '../services/business_repositories.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../utils/file_export.dart';
import '../widgets/document_status_badge.dart';

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
  static const _allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

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
  bool uploading = false;
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

  bool _isImage(String name) =>
      ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(
        name.split('.').last.toLowerCase(),
      );

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

  String? _fileError(_PickedDocument file) {
    final ext = file.name.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      return 'Unsupported file type: ${file.name}. '
          'Use PDF, JPG, JPEG or PNG.';
    }
    if (file.bytes.length > _maxUploadBytes) {
      return '${file.name} is larger than 20 MB. '
          'Split it or compress first.';
    }
    return null;
  }

  Future<String?> _pickUploadSource() => showModalBottomSheet<String>(
    context: context,
    builder:
        (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Add a document from',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Files'),
                subtitle: const Text('PDF, JPG, JPEG, PNG'),
                onTap: () => Navigator.pop(sheetContext, 'files'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(sheetContext, 'gallery'),
              ),
            ],
          ),
        ),
  );

  Future<String?> _pickCategory() => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder:
        (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Document category',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final category in kDocumentTypes)
                ListTile(
                  dense: true,
                  title: Text(category),
                  trailing:
                      category ==
                              (categoryFilter ?? 'Other supporting documents')
                          ? const Icon(Icons.check)
                          : null,
                  onTap: () => Navigator.pop(sheetContext, category),
                ),
            ],
          ),
        ),
  );

  Future<List<_PickedDocument>?> _pickDocuments(String source) async {
    try {
      if (source == 'files') {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: _allowedExtensions,
          allowMultiple: true,
          withData: true,
        );
        if (picked == null) return null;
        final files = <_PickedDocument>[];
        for (final file in picked.files) {
          final bytes = file.bytes;
          if (bytes == null) {
            _snack('Could not read ${file.name}.');
            return null;
          }
          files.add(_PickedDocument(file.name, bytes));
        }
        return files;
      }
      final picked = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 90,
      );
      if (picked == null) return null;
      final bytes = await picked.readAsBytes();
      final name = picked.name.isEmpty ? 'camera-image.jpg' : picked.name;
      return [_PickedDocument(name, bytes)];
    } catch (e) {
      _snack('Could not pick a file: ${'$e'.replaceFirst('Exception: ', '')}');
      return null;
    }
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
    final source = await _pickUploadSource();
    if (source == null) return;
    final files = await _pickDocuments(source);
    if (files == null || files.isEmpty) return;
    for (final file in files) {
      final problem = _fileError(file);
      if (problem != null) {
        _snack(problem);
        return;
      }
    }
    final category = await _pickCategory();
    if (category == null || !mounted) return;

    setState(() => uploading = true);
    var uploaded = 0;
    String? failure;
    try {
      for (final file in files) {
        final cleanName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final fileName = '${docsRepo.table.local.newId()}-$cleanName';
        final path = await docsRepo.upload(
          workspaceFolder: widget.auth.workspaceId!,
          clientFolder: clientId,
          fileName: fileName,
          bytes: file.bytes,
          contentType: _mimeType(file.name),
        );
        await docsRepo.upsert(
          DocumentRecord(
            id: docsRepo.table.local.newId(),
            clientId: clientId,
            name: file.name,
            category: category,
            filePath: path,
            mimeType: _mimeType(file.name),
            sizeBytes: file.bytes.length,
            uploadedBy: widget.auth.currentEmail,
            status: 'Uploaded',
            updatedAt: DateTime.now(),
          ),
        );
        uploaded++;
      }
    } catch (e) {
      failure = '$e'.replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => uploading = false);
      if (uploaded > 0) await load();
    }
    if (failure != null) {
      _snack(
        'Upload failed after $uploaded of ${files.length} file(s): $failure',
      );
    } else {
      _snack(
        uploaded == 1 ? 'Document uploaded' : '$uploaded documents uploaded',
      );
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

  Future<void> _preview(DocumentRecord doc) async {
    if (!_backendReady) {
      _snack('Previews need a Supabase connection.');
      return;
    }
    if (!_isImage(doc.name)) {
      await _download(doc);
      return;
    }
    try {
      final url = await docsRepo.createSignedUrl(doc.filePath, seconds: 60);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            doc.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: InteractiveViewer(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder:
                              (context, child, progress) =>
                                  progress == null
                                      ? child
                                      : const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(24),
                                          child: CircularProgressIndicator(),
                                        ),
                                      ),
                          errorBuilder:
                              (context, error, stackTrace) => const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('Could not load this preview.'),
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      );
    } catch (e) {
      _snack('Preview failed: ${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _download(DocumentRecord doc) async {
    if (!_backendReady) {
      _snack('Downloads need a Supabase connection.');
      return;
    }
    try {
      final bytes = await docsRepo.download(doc.filePath, seconds: 60);
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
      _snack('Download failed: ${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _replace(DocumentRecord doc) async {
    if (!_backendReady) {
      _snack('Replacing a file needs a Supabase connection.');
      return;
    }
    if (widget.auth.workspaceId == null) return;
    final source = await _pickUploadSource();
    if (source == null) return;
    final files = await _pickDocuments(source);
    if (files == null || files.isEmpty) return;
    final file = files.first;
    final problem = _fileError(file);
    if (problem != null) {
      _snack(problem);
      return;
    }
    if (!mounted) return;
    setState(() => uploading = true);
    String? newPath;
    try {
      final cleanName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final fileName = '${docsRepo.table.local.newId()}-$cleanName';
      newPath = await docsRepo.upload(
        workspaceFolder: widget.auth.workspaceId!,
        clientFolder: doc.clientId,
        fileName: fileName,
        bytes: file.bytes,
        contentType: _mimeType(file.name),
      );
      await docsRepo.upsert(
        doc.copyWith(
          name: file.name,
          filePath: newPath,
          mimeType: _mimeType(file.name),
          sizeBytes: file.bytes.length,
          status: 'Uploaded',
          updatedAt: DateTime.now(),
        ),
      );
      try {
        await docsRepo.removeFile(doc.filePath);
      } catch (_) {}
      _snack('Document replaced');
      await load();
    } catch (e) {
      if (newPath != null) {
        try {
          await docsRepo.removeFile(newPath);
        } catch (_) {}
      }
      _snack('Replace failed: ${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => uploading = false);
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
    } catch (_) {}
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
    final categories = [
      ...kDocumentTypes,
      if (!kDocumentTypes.contains(doc.category)) doc.category,
    ];
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
                            for (final t in categories)
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
    if (ok != true) {
      name.dispose();
      return;
    }
    try {
      await docsRepo.upsert(
        doc.copyWith(
          name: name.text.trim().isEmpty ? doc.name : name.text.trim(),
          category: category,
          updatedAt: DateTime.now(),
        ),
      );
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      name.dispose();
    }
  }

  Future<void> _editAdmin(DocumentRecord doc) async {
    if (!widget.auth.isAdmin) {
      _snack('Only an Admin can review or change document status.');
      return;
    }
    final notes = TextEditingController(text: doc.adminNotes);
    String status =
        kDocumentStatuses.contains(doc.status)
            ? doc.status
            : kDocumentStatuses.first;
    final statuses = [
      ...kDocumentStatuses,
      if (!kDocumentStatuses.contains(doc.status)) doc.status,
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Review document'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: status,
                          items: [
                            for (final value in statuses)
                              DropdownMenuItem(value: value, child: Text(value)),
                          ],
                          onChanged:
                              (v) => setDialogState(
                                () => status = v ?? status,
                              ),
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Admin notes',
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
    if (ok != true) {
      notes.dispose();
      return;
    }
    try {
      await docsRepo.upsert(
        doc.copyWith(
          status: status,
          adminNotes: notes.text.trim(),
          updatedAt: DateTime.now(),
        ),
      );
      _snack('Document review updated');
      await load();
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      notes.dispose();
    }
  }

  Widget _metaLine(IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.onSurface.withValues(alpha: 0.55)),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _windowSummary(ClientRecord client) {
    final clientDocs = documents.where((d) => d.clientId == client.id).toList();
    final approved =
        clientDocs.where((d) => isDocumentApproved(d.status)).length;
    final outstanding =
        clientDocs.where((d) => isDocumentOutstanding(d.status)).length;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            client.fullName.isEmpty ? 'Unnamed client' : client.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '$outstanding outstanding · $approved approved',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color:
                  outstanding > 0
                      ? documentStatusColor(context, 'Needs replacement')
                      : documentStatusColor(context, 'Approved'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clientSummary() {
    if (widget.clientId != null || clients.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Client document summary',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: clients.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _windowSummary(clients[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentCard(DocumentRecord doc) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _preview(doc),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      _fileIcon(doc.name),
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          doc.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        if (widget.clientId == null)
                          Text(
                            clientName(doc.clientId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'preview') _preview(doc);
                      if (v == 'download') _download(doc);
                      if (v == 'replace') _replace(doc);
                      if (v == 'edit') _editMeta(doc);
                      if (v == 'status') _editAdmin(doc);
                      if (v == 'delete') _delete(doc);
                    },
                    itemBuilder:
                        (menuContext) => [
                          PopupMenuItem(
                            value: 'preview',
                            child: Text(
                              _isImage(doc.name)
                                  ? 'Preview image'
                                  : 'Open / save copy',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'download',
                            child: Text('Download a copy'),
                          ),
                          const PopupMenuItem(
                            value: 'replace',
                            child: Text('Replace file'),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Rename / recategorize'),
                          ),
                          if (widget.auth.isAdmin)
                            const PopupMenuItem(
                              value: 'status',
                              child: Text('Status and admin notes'),
                            ),
                          if (widget.auth.isAdmin)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete (Admin)'),
                            ),
                        ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 52, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DocumentStatusBadge(status: doc.status),
                        _metaLine(
                          Icons.calendar_today_outlined,
                          'Uploaded ${DateFormat('d MMM y').format(doc.updatedAt)}',
                        ),
                        if (_sizeLabel(doc.sizeBytes).isNotEmpty)
                          _metaLine(
                            Icons.data_usage_outlined,
                            _sizeLabel(doc.sizeBytes),
                          ),
                      ],
                    ),
                    if (doc.adminNotes.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Admin notes: ${doc.adminNotes.trim()}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        onPressed: uploading ? null : _upload,
        icon:
            uploading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                : const Icon(Icons.upload_file_outlined),
        label: Text(uploading ? 'Uploading…' : 'Add document'),
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
          _clientSummary(),
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
                      itemBuilder: (context, i) => _documentCard(items[i]),
                    ),
          ),
        ],
      ),
    );
  }
}

class _PickedDocument {
  final String name;
  final Uint8List bytes;

  const _PickedDocument(this.name, this.bytes);
}
