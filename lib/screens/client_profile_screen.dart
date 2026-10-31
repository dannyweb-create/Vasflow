import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/client_record.dart';
import '../models/client_record_extensions.dart';
import '../models/document_record.dart';
import '../models/options.dart';
import '../services/auth_service.dart';
import '../services/business_repositories.dart';
import '../services/client_photo_service.dart';
import '../services/client_repository.dart';
import '../services/local_store.dart';
import '../theme/brand.dart';
import '../theme/glass_widgets.dart';
import '../utils/client_export.dart';
import '../utils/dates.dart';
import '../utils/file_export.dart';
import '../widgets/client_avatar.dart';
import '../widgets/document_status_badge.dart';
import 'applications_screen.dart';
import 'client_form_screen.dart';
import 'documents_screen.dart';
import 'payments_screen.dart';
import 'tasks_screen.dart';

class ClientProfileScreen extends StatefulWidget {
  final AuthService auth;
  final ClientRepository repo;
  final ClientRecord client;

  const ClientProfileScreen({
    super.key,
    required this.auth,
    required this.repo,
    required this.client,
  });

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  late ClientRecord _client;
  late final DocumentRepository _documentsRepo;
  List<DocumentRecord> _documents = [];
  bool _docsLoading = true;
  bool _exporting = false;
  String? _docsError;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _documentsRepo = DocumentRepository(
      LocalStore(),
      workspaceId: widget.auth.workspaceId,
    );
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final docs = await _documentsRepo.forClient(_client.id);
      docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _docsLoading = false;
        _docsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _docsLoading = false;
        _docsError = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _reloadClient() async {
    try {
      final clients = await widget.repo.all();
      for (final client in clients) {
        if (client.id == _client.id) {
          if (mounted) setState(() => _client = client);
          return;
        }
      }
    } catch (_) {}
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<ImageSource?> _choosePhotoSource() =>
      showModalBottomSheet<ImageSource>(
        context: context,
        builder:
            (sheetContext) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Client photo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take a photo'),
                    onTap:
                        () => Navigator.pop(sheetContext, ImageSource.camera),
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from gallery'),
                    onTap:
                        () => Navigator.pop(sheetContext, ImageSource.gallery),
                  ),
                ],
              ),
            ),
      );

  Future<void> _showPhotoActions() async {
    final hasPhoto = _client.photoPath.isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (hasPhoto)
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('View photo'),
                    onTap: () => Navigator.pop(sheetContext, 'view'),
                  ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(
                    hasPhoto
                        ? 'Change photo with camera'
                        : 'Add photo with camera',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(
                    hasPhoto
                        ? 'Change photo from gallery'
                        : 'Add photo from gallery',
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'gallery'),
                ),
                if (hasPhoto)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Remove photo',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () => Navigator.pop(sheetContext, 'remove'),
                  ),
              ],
            ),
          ),
    );
    if (action == 'view') await _viewClientPhoto();
    if (action == 'camera') await _pickClientPhoto(ImageSource.camera);
    if (action == 'gallery') await _pickClientPhoto(ImageSource.gallery);
    if (action == 'remove') await _removeClientPhoto();
  }

  Future<void> _viewClientPhoto() async {
    final path = _client.photoPath;
    if (path.isEmpty) return;
    try {
      final url = await ClientPhotoService().signedUrl(path, seconds: 60);
      if (url == null || url.isEmpty || !mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: InteractiveViewer(
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (context, error, stackTrace) => const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('Could not load this photo.'),
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
      _snack('Photo preview failed: ${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _pickClientPhoto(ImageSource source) async {
    try {
      final file = await ClientPhotoService.pick(source);
      if (file == null) return;
      final ext = ClientPhotoService.extensionOf(file.name);
      if (!ClientPhotoService.isSupportedExtension(ext)) {
        _snack('Client photos must be JPG or PNG.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        _snack('That photo is too large. Choose a smaller image.');
        return;
      }
      final workspaceId = widget.auth.workspaceId;
      if (workspaceId == null) {
        _snack('Join or create a workspace before uploading a client photo.');
        return;
      }
      final service = ClientPhotoService();
      String? newPath;
      try {
        newPath = await service.upload(
          workspaceId: workspaceId,
          clientId: _client.id,
          bytes: bytes,
          extension: ext,
        );
        final oldPath = _client.photoPath;
        final updated = _client.copyWith(
          photoPath: newPath,
          updatedAt: DateTime.now(),
        );
        await widget.repo.upsert(updated);
        if (oldPath.isNotEmpty && oldPath != newPath) {
          try {
            await service.remove(oldPath);
          } catch (_) {}
        }
        if (!mounted) return;
        setState(() => _client = updated);
        _snack('Client photo updated');
      } catch (e) {
        if (newPath != null) {
          try {
            await service.remove(newPath);
          } catch (_) {}
        }
        _snack('Photo update failed: ${'$e'.replaceFirst('Exception: ', '')}');
      }
    } catch (e) {
      _snack('Could not pick a photo: ${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _removeClientPhoto() async {
    final oldPath = _client.photoPath;
    if (oldPath.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove client photo?'),
            content: const Text('The stored photo will also be deleted.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (yes != true) return;
    final updated = _client.copyWith(photoPath: '', updatedAt: DateTime.now());
    try {
      await widget.repo.upsert(updated);
      var fileRemoved = true;
      try {
        await ClientPhotoService().remove(oldPath);
      } catch (_) {
        fileRemoved = false;
      }
      if (!mounted) return;
      setState(() => _client = updated);
      _snack(
        fileRemoved
            ? 'Client photo removed'
            : 'Photo removed, but the stored file could not be deleted.',
      );
    } catch (e) {
      _snack('Could not remove photo: ${'$e'.replaceFirst('Exception: ', '')}');
    }
  }

  String _detail(String key) {
    final raw = _client.details[key];
    if (raw == null) return '';
    final value = '$raw'.trim();
    return value == 'null' ? '' : value;
  }

  String _dateText(String key) {
    final value = _detail(key);
    if (value.isEmpty) return '';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return DateFormat('d MMM y').format(date);
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

  Widget _pill(String label, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _avatar({double size = 88}) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.3);
    return GestureDetector(
      onTap: _showPhotoActions,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.3 + 2),
              color: scheme.surface.withValues(alpha: 0.35),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.32)),
            ),
            child: ClientAvatar(
              photoPath: _client.photoPath,
              name: _client.fullName,
              size: size,
              borderRadius: radius,
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Icon(
                _client.photoPath.isEmpty
                    ? Icons.add_a_photo_outlined
                    : Icons.edit_outlined,
                size: 14,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        radius: 18,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: enabled ? null : scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 16),
      radius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  'Client profile',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.auth.isAdmin)
                IconButton(
                  tooltip: 'Export client',
                  onPressed: _exporting ? null : _exportClient,
                  icon:
                      _exporting
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.ios_share_outlined),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatar(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _client.fullName.isEmpty ? '—' : _client.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 15,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              _client.country.isEmpty ? '—' : _client.country,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _pill(_client.stage, _stageColor(_client.stage)),
                          if (_client.archived)
                            _pill('Archived', scheme.outline),
                          OutlinedButton.icon(
                            onPressed: _edit,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow() {
    return Row(
      children: [
        Expanded(
          child: _actionTile(
            Icons.call_outlined,
            'Call',
            () => _showContact('Phone', _client.phone),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionTile(
            Icons.mail_outline_rounded,
            'Email',
            () => _showContact('Email', _client.email),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionTile(
            Icons.ios_share_outlined,
            'Export',
            widget.auth.isAdmin && !_exporting ? _exportClient : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionTile(Icons.more_horiz_rounded, 'More', _showMore),
        ),
      ],
    );
  }

  Future<void> _showContact(String label, String value) async {
    final text = value.trim();
    if (text.isEmpty) {
      _snack('No ${label.toLowerCase()} saved for this client.');
      return;
    }
    final copy = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(label),
            content: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
    );
    if (copy != true) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack('$label copied');
  }

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit client'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _edit();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flight_takeoff_outlined),
                  title: const Text('Applications'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openApplications();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Documents'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openDocuments();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Payments'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openPayments();
                  },
                ),
                ListTile(
                  leading: Icon(
                    _client.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  title: Text(
                    _client.archived ? 'Restore client' : 'Archive client',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _setArchived();
                  },
                ),
                if (widget.auth.isAdmin)
                  ListTile(
                    leading: const Icon(Icons.ios_share_outlined),
                    title: const Text('Export client'),
                    subtitle: const Text('PDF, XLSX, CSV or JSON'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _exportClient();
                    },
                  ),
                if (widget.auth.role == 'admin')
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Delete client',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _delete();
                    },
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (_) => ClientFormScreen(
              repo: widget.repo,
              auth: widget.auth,
              existing: _client,
            ),
      ),
    );
    if (saved == true) await _reloadClient();
  }

  Future<void> _setArchived() async {
    final archived = !_client.archived;
    try {
      await widget.repo.setArchived(_client.id, archived);
      if (!mounted) return;
      setState(() => _client = _client.copyWith(archived: archived));
      _snack(
        archived ? 'Client archived' : 'Client restored to the active list',
      );
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _delete() async {
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
              'Delete ${_client.fullName}? History, applications, documents and '
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
      await widget.repo.delete(_client.id);
      if (!mounted) return;
      _snack('Client deleted');
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openApplications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ApplicationsScreen(auth: widget.auth, clientId: _client.id),
      ),
    );
    if (mounted) await _reloadClient();
  }

  Future<void> _openDocuments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => DocumentsScreen(auth: widget.auth, clientId: _client.id),
      ),
    );
    if (mounted) await _loadDocuments();
  }

  Future<void> _openPayments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsScreen(auth: widget.auth, clientId: _client.id),
      ),
    );
    if (mounted) await _reloadClient();
  }

  Future<void> _exportClient() async {
    if (!widget.auth.isAdmin) {
      _snack('Only an Admin can export client data.');
      return;
    }
    final choice = await showModalBottomSheet<_ClientExportChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        var format = ClientExportFormat.pdf;
        var includeDocuments = false;
        return StatefulBuilder(
          builder:
              (context, setSheetState) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export client',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Document names and statuses are always included.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 8),
                      RadioGroup<ClientExportFormat>(
                        groupValue: format,
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => format = value);
                        },
                        child: Column(
                          children: [
                            for (final option in ClientExportFormat.values)
                              RadioListTile<ClientExportFormat>(
                                value: option,
                                contentPadding: EdgeInsets.zero,
                                title: Text(option.label),
                                subtitle: Text(option.description),
                              ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: includeDocuments,
                        onChanged: (value) {
                          setSheetState(() => includeDocuments = value);
                        },
                        title: const Text('Include document files (ZIP)'),
                        subtitle: const Text(
                          'Bundles the export and the original uploaded files '
                          'in one ZIP.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              sheetContext,
                              _ClientExportChoice(
                                format: format,
                                includeDocuments: includeDocuments,
                              ),
                            );
                          },
                          icon: const Icon(Icons.download_outlined),
                          label: Text(
                            includeDocuments
                                ? 'Export ZIP'
                                : 'Export ${format.label}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        );
      },
    );
    if (choice == null || !mounted) return;
    await _runExport(choice);
  }

  Future<void> _runExport(_ClientExportChoice choice) async {
    setState(() => _exporting = true);
    try {
      final applications = await ApplicationRepository(
        LocalStore(),
        workspaceId: widget.auth.workspaceId,
      ).forClient(_client.id);
      final payments = await PaymentRepository(
        LocalStore(),
        workspaceId: widget.auth.workspaceId,
      ).forClient(_client.id);
      final documents = await _documentsRepo.forClient(_client.id);
      final data = ClientExportData(
        client: _client,
        applications: applications,
        payments: payments,
        documents: documents,
      );

      Uint8List bytes;
      var fileName = clientExportFileName(data, choice.format);
      String? note;
      if (choice.includeDocuments) {
        final files = <String, Uint8List>{};
        var missing = 0;
        for (final document in documents) {
          if (document.filePath.trim().isEmpty) {
            missing++;
            continue;
          }
          try {
            final downloaded = await _documentsRepo.download(document.filePath);
            if (downloaded == null) {
              missing++;
            } else {
              files[document.id] = downloaded;
            }
          } catch (_) {
            missing++;
          }
        }
        bytes = await buildClientExportZip(data, choice.format, files);
        fileName = clientExportFileName(data, choice.format, zip: true);
        if (missing > 0) {
          note =
              '$missing document file${missing == 1 ? '' : 's'} '
              'could not be downloaded.';
        }
      } else {
        bytes = await buildClientExport(data, choice.format);
      }

      if (!mounted) return;
      await saveBytes(
        context,
        bytes,
        fileName: fileName,
        dialogTitle: 'Export ${_client.fullName}',
      );
      if (note != null && mounted) _snack(note);
    } catch (e) {
      if (mounted) {
        _snack('Export failed: ${'$e'.replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _infoRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value.trim(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> rows) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _notesCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = _client.notes.trim();
    final followUp = _detail('follow_up');
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Notes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            notes.isEmpty ? '—' : notes,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          if (followUp.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Follow-up requirements',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              followUp,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickTile(
    IconData icon,
    String label,
    VoidCallback? onTap, {
    String? disabledHint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final tile = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 19, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color:
                          enabled
                              ? null
                              : scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (disabledHint == null || enabled) return tile;
    return Tooltip(message: disabledHint, child: tile);
  }

  Widget _quickActions() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Quick actions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.4,
            children: [
              _quickTile(
                Icons.upload_file_outlined,
                'Add Document',
                _openDocuments,
              ),
              _quickTile(
                Icons.task_alt_outlined,
                'Add Task',
                null,
                disabledHint: 'Tasks are not linked to clients yet.',
              ),
              _quickTile(
                Icons.payments_outlined,
                'Record Payment',
                _openPayments,
              ),
              _quickTile(Icons.sticky_note_2_outlined, 'Add Note', _edit),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openApplications,
                icon: const Icon(Icons.flight_takeoff_outlined, size: 18),
                label: const Text('Applications'),
              ),
              OutlinedButton.icon(
                onPressed: _openDocuments,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Documents'),
              ),
              OutlinedButton.icon(
                onPressed: _openPayments,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Payments'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityRow(_ActivityEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(entry.icon, size: 17, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.detail,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentActivityCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final events = <_ActivityEntry>[
      _ActivityEntry(
        at: _client.updatedAt,
        icon: Icons.update_rounded,
        title: 'Client record updated',
        detail:
            '${DateFormat('d MMM y, HH:mm').format(_client.updatedAt)} · '
            '${timeAgo(_client.updatedAt, DateTime.now())}',
      ),
      for (final doc in _documents)
        _ActivityEntry(
          at: doc.updatedAt,
          icon: Icons.description_outlined,
          title: doc.name,
          detail: [
            if (doc.category.trim().isNotEmpty) doc.category.trim(),
            'Updated ${DateFormat('d MMM y').format(doc.updatedAt)}',
          ].join(' · '),
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final recent = events.take(4).toList();
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recent activity',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < recent.length; i++) ...[
            _activityRow(recent[i]),
            if (i != recent.length - 1)
              Divider(color: scheme.outlineVariant, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _overviewTab() {
    return ListView(
      key: const PageStorageKey('client-overview'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      children: [
        _section('Application details', Icons.assignment_outlined, [
          _infoRow('Preferred country', _client.country),
          _infoRow('Preferred university', _client.university),
          _infoRow('Intended course', _detail('intended_course')),
          _infoRow('Study level', _detail('study_level')),
          _infoRow('Intended travel date', _dateText('travel_date')),
          _infoRow('Intake', _detail('intake')),
          _infoRow('Application type', _detail('application_type')),
          _infoRow('Application deadline', _dateText('application_deadline')),
        ]),
        const SizedBox(height: 12),
        _section('Personal and contact', Icons.person_outline_rounded, [
          _infoRow('Full name', _client.fullName),
          _infoRow('Email', _client.email),
          _infoRow('Phone', _client.phone),
          _infoRow('Date of birth', _dateText('dob')),
          _infoRow('Nationality', _detail('nationality')),
          _infoRow('Address', _detail('address')),
        ]),
        const SizedBox(height: 12),
        _section('Passport and identity', Icons.badge_outlined, [
          _infoRow('Passport number', _client.passportNumber),
          _infoRow('Country of issue', _detail('passport_country')),
          _infoRow('Issue date', _dateText('passport_issue_date')),
          _infoRow('Expiry date', _dateText('passport_expiry_date')),
          _infoRow('Visa status', _client.visaStatus),
        ]),
        const SizedBox(height: 12),
        _section('School and consultant', Icons.school_outlined, [
          _infoRow('Current school', _detail('current_school')),
          _infoRow('Qualifications', _detail('qualifications')),
          _infoRow('Consultant', _detail('consultant')),
          _infoRow(
            'Documents marked received',
            ClientRecord.receivedDocuments(_client.details).join(', '),
          ),
        ]),
        const SizedBox(height: 12),
        _quickActions(),
        const SizedBox(height: 12),
        _notesCard(),
        const SizedBox(height: 12),
        _recentActivityCard(),
      ],
    );
  }

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

  String _documentSubtitle(DocumentRecord doc) {
    return [
      doc.category,
      'Uploaded ${DateFormat('d MMM y').format(doc.updatedAt)}',
      if (_sizeLabel(doc.sizeBytes).isNotEmpty) _sizeLabel(doc.sizeBytes),
    ].join(' · ');
  }

  Widget _documentsTab() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_docsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_docsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(_docsError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _docsLoading = true;
                    _docsError = null;
                  });
                  _loadDocuments();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final count = _documents.length;
    final approved =
        _documents.where((d) => isDocumentApproved(d.status)).length;
    final outstanding =
        _documents.where((d) => isDocumentOutstanding(d.status)).length;
    return ListView(
      key: const PageStorageKey('client-documents'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count ${count == 1 ? 'document' : 'documents'} on file',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$outstanding outstanding · $approved approved',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color:
                          outstanding > 0
                              ? documentStatusColor(
                                context,
                                'Needs replacement',
                              )
                              : documentStatusColor(context, 'Approved'),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _openDocuments,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Upload'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_documents.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            radius: 22,
            child: Column(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 42,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 10),
                const Text(
                  'No documents uploaded for this client yet.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _openDocuments,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Open Documents to upload'),
                ),
              ],
            ),
          )
        else
          for (final doc in _documents) ...[
            GlassPanel(
              padding: EdgeInsets.zero,
              radius: 18,
              onTap: _openDocuments,
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    _fileIcon(doc.name),
                    size: 20,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  doc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _documentSubtitle(doc),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    DocumentStatusBadge(status: doc.status),
                    if (doc.adminNotes.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Admin notes: ${doc.adminNotes.trim()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _tasksTab() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      key: const PageStorageKey('client-tasks'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      children: [
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
          radius: 22,
          child: Column(
            children: [
              Icon(
                Icons.task_alt_outlined,
                size: 42,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 10),
              Text(
                'No tasks for this client',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tasks in VasFlow are workspace reminders and are not linked '
                'to a client yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TasksScreen()),
                    ),
                icon: const Icon(Icons.task_alt_outlined, size: 18),
                label: const Text('Open Tasks & reminders'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timelineRow(IconData icon, String label, String value, String note) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineTab() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final updated = DateFormat('d MMM y, HH:mm').format(_client.updatedAt);
    return ListView(
      key: const PageStorageKey('client-timeline'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      children: [
        Text(
          'Basic timeline',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Created and updated dates only.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 10),
        GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          radius: 22,
          child: Column(
            children: [
              _timelineRow(
                Icons.add_circle_outline,
                'Created',
                '—',
                'Not recorded in the client record.',
              ),
              Divider(color: scheme.outlineVariant, height: 1),
              _timelineRow(
                Icons.update_rounded,
                'Updated',
                updated,
                timeAgo(_client.updatedAt, DateTime.now()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabs() {
    final scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.all(4),
      radius: 18,
      child: TabBar(
        labelColor: Brand.onGreen,
        unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.65),
        indicator: BoxDecoration(
          color: Brand.green,
          borderRadius: BorderRadius.circular(14),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Documents'),
          Tab(text: 'Tasks'),
          Tab(text: 'Timeline'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder:
                (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: Column(
                        children: [
                          _header(),
                          const SizedBox(height: 10),
                          _actionRow(),
                        ],
                      ),
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _ProfileTabsDelegate(
                      child: ColoredBox(
                        color:
                            isGlass(context)
                                ? Colors.transparent
                                : theme.scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                          child: _tabs(),
                        ),
                      ),
                    ),
                  ),
                ],
            body: TabBarView(
              children: [
                _overviewTab(),
                _documentsTab(),
                _tasksTab(),
                _timelineTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityEntry {
  final DateTime at;
  final IconData icon;
  final String title;
  final String detail;

  const _ActivityEntry({
    required this.at,
    required this.icon,
    required this.title,
    required this.detail,
  });
}

class _ClientExportChoice {
  final ClientExportFormat format;
  final bool includeDocuments;

  const _ClientExportChoice({
    required this.format,
    required this.includeDocuments,
  });
}

class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _ProfileTabsDelegate({required this.child});

  @override
  double get minExtent => 72;

  @override
  double get maxExtent => 72;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) =>
      child != oldDelegate.child;
}
