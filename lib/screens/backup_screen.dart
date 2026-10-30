import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/app_config.dart';
import '../services/auth_service.dart';
import '../services/backup_models.dart';
import '../services/backup_repository.dart';
import '../services/backup_scheduler.dart';
import '../services/backup_service.dart';
import '../services/local_store.dart';
import '../services/restore_service.dart';
import '../theme/brand.dart';
import '../utils/file_export.dart';

/// Pure display helpers for the Backup & Recovery screen. Kept static and
/// side-effect-free so focused tests can pin the exact wording.
class BackupUi {
  static const typedConfirmWord = 'RESTORE';
  static const offlineNote = 'Backups need a Supabase connection.';

  static String statusLabel(BackupEntry entry) {
    if (entry.completed) return 'Completed';
    if (entry.failed) return 'Failed';
    if (entry.running) return 'Running';
    return 'Pending';
  }

  static String kindLabel(BackupEntry entry) =>
      entry.kind == 'auto' ? 'Automatic' : 'Manual';

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String timestampLabel(DateTime utc) =>
      DateFormat('d MMM yyyy · HH:mm').format(utc.toLocal());

  static String createdLabel(BackupEntry entry) =>
      entry.createdAt == null
          ? 'Unknown time'
          : timestampLabel(entry.createdAt!);

  /// Restoring into a new workspace is only possible while the signed-in
  /// account does not belong to any workspace yet (the server RPC enforces
  /// one workspace per user, so the UI must not offer it otherwise).
  static bool canRestoreToNewWorkspace(bool belongsToWorkspace) =>
      !belongsToWorkspace;

  static String historyFileName(BackupEntry entry) {
    final stamp =
        entry.createdAt == null
            ? 'unknown'
            : DateFormat('yyyyMMdd-HHmm').format(entry.createdAt!.toLocal());
    return 'vasflow-backup-$stamp-${entry.id.substring(0, 8)}.zip';
  }
}

enum _RestoreTarget { newWorkspace, thisWorkspace }

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupRepository _repo;
  late final BackupService _service;
  late final RestoreService _restore;

  Future<List<BackupEntry>> _history = Future.value(const []);
  String? _busyEntryId;

  bool _backingUp = false;
  String _backupStep = '';

  @override
  void initState() {
    super.initState();
    _repo = BackupRepository();
    _service = BackupService(
      auth: widget.auth,
      repo: _repo,
      local: LocalStore(),
    );
    _restore = RestoreService(
      auth: widget.auth,
      repo: _repo,
      local: LocalStore(),
    );
    _reload();
  }

  void _reload() {
    final wsId = widget.auth.workspaceId;
    if (wsId == null || !AppConfig.supabaseReady) {
      _history = Future.value(const []);
      return;
    }
    _history = _repo.list(wsId);
    setState(() {});
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _runBackup() async {
    if (_backingUp) return;
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    setState(() {
      _backingUp = true;
      _backupStep = 'Starting...';
    });
    try {
      final result = await _service.run(
        onStep: (s) {
          if (mounted) setState(() => _backupStep = s);
        },
      );
      final parts = result.counts.entries
          .where((e) => e.value > 0)
          .map((e) => '${e.key} ${e.value}')
          .join(', ');
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Backup saved · $parts · ${BackupUi.formatBytes(result.sizeBytes)}',
          ),
        ),
      );
      if (result.missingFiles.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: scheme.error,
            content: Text(
              '${result.missingFiles.length} document file(s) could not be '
              'downloaded and are listed as missing in the backup.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.error,
          content: Text(_clean(e)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _backingUp = false;
          _backupStep = '';
        });
      }
      _reload();
    }
  }

  Future<void> _download(BackupEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _repo.downloadZip(entry.storagePath!);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('The stored archive could not be downloaded.');
      }
      if (!mounted) return;
      await saveBytes(
        context,
        bytes,
        fileName: BackupUi.historyFileName(entry),
        dialogTitle: 'Backup archive',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(_clean(e))),
      );
    }
  }

  Future<void> _delete(BackupEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete backup?'),
            content: Text(
              'This permanently removes the archive file and its history entry '
              '(from ${BackupUi.createdLabel(entry)}). It cannot be undone and does '
              'not touch your data or documents.',
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
    if (confirmed != true) return;
    try {
      await _repo.deleteFileThenRow(entry);
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Backup deleted.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(_clean(e))),
      );
    }
    _reload();
  }

  Future<void> _startRestore(BackupEntry entry) async {
    if (entry.storagePath == null) {
      _snack('This run never produced an archive file.', error: true);
      return;
    }
    setState(() => _busyEntryId = entry.id);
    Uint8List? bytes;
    RestorePreview? preview;
    try {
      bytes = await _repo.downloadZip(entry.storagePath!);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('The stored archive could not be downloaded.');
      }
      preview = await _restore.prepareBytes(entry, bytes);
    } catch (e) {
      _snack(_clean(e), error: true);
      return;
    } finally {
      if (mounted) setState(() => _busyEntryId = null);
    }
    if (!mounted) return;
    final fileProblems = preview.fileProblems.take(8).join('\n');
    if (!preview.ready) {
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Archive failed verification'),
              content: Text(
                'This archive does not match its checksum, so it may be damaged or '
                'has been replaced. Nothing was written.\n\n'
                '$fileProblems',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
      return;
    }
    await _chooseRestoreStrategy(entry, preview, bytes);
  }

  Future<void> _chooseRestoreStrategy(
    BackupEntry entry,
    RestorePreview preview,
    Uint8List archiveBytes,
  ) async {
    final belongs = (widget.auth.workspaceId ?? '').isNotEmpty;
    var strategy =
        belongs ? _RestoreTarget.thisWorkspace : _RestoreTarget.newWorkspace;
    final nameController = TextEditingController(text: 'Restored workspace');
    var proceed = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (sheetContext, setSheetState) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Restore from ${BackupUi.createdLabel(entry)}',
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Every record and document in the archive is written back '
                        'exactly as it was. Existing records with the same ID are '
                        'overwritten (updated) in place — nothing is ever deleted.',
                      ),
                      const SizedBox(height: 12),
                      RadioGroup<_RestoreTarget>(
                        groupValue: strategy,
                        onChanged: (v) {
                          if (v == null) return;
                          if (v == _RestoreTarget.newWorkspace &&
                              !BackupUi.canRestoreToNewWorkspace(belongs)) {
                            return;
                          }
                          setSheetState(() => strategy = v);
                        },
                        child: Column(
                          children: [
                            RadioListTile<_RestoreTarget>(
                              value: _RestoreTarget.newWorkspace,
                              title: const Text('Restore into a NEW workspace'),
                              subtitle:
                                  belongs
                                      ? const Text(
                                        'Not available: this account already belongs to '
                                        'a workspace. Log out on a fresh device and sign '
                                        'in with the same account before restoring.',
                                      )
                                      : const Text(
                                        'Recreates the records, documents and tasks in a '
                                        'brand-new workspace. There is nothing here to '
                                        'overwrite.',
                                      ),
                            ),
                            RadioListTile<_RestoreTarget>(
                              value: _RestoreTarget.thisWorkspace,
                              title: Text(
                                widget.auth.workspaceName.isEmpty
                                    ? 'Restore into THIS workspace'
                                    : 'Restore into THIS workspace '
                                        '(${widget.auth.workspaceName})',
                              ),
                              subtitle: const Text(
                                'Overwrites records in the current workspace when '
                                'their IDs match. Requires a typed confirmation next.',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (strategy == _RestoreTarget.newWorkspace &&
                          BackupUi.canRestoreToNewWorkspace(belongs))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'New workspace name',
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          proceed = true;
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                ),
          ),
    );
    if (!proceed || !mounted) return;
    if (strategy == _RestoreTarget.newWorkspace &&
        BackupUi.canRestoreToNewWorkspace(belongs)) {
      await _restoreToNewWorkspace(
        preview,
        archiveBytes,
        nameController.text.trim(),
      );
    } else {
      await _restoreToThisWorkspace(preview, archiveBytes);
    }
  }

  String? _missingFilesWarning(RestorePreview preview) {
    final fromArchive = preview.manifest.missingFiles;
    if (fromArchive.isEmpty) return null;
    return '${fromArchive.length} document file(s) were already missing when '
        'this backup was made and cannot be restored; their record rows are '
        'restored anyway.';
  }

  /// The shared pre-write confirmation. Shows the incoming counts against the
  /// live server counts so the person can compare before anything is written.
  Future<bool?> _confirmRestore({
    required RestorePreview preview,
    required String headline,
    required List<String> bullets,
    String? extraWarning,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(headline),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final bullet in bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $bullet'),
                    ),
                  Text(
                    'Incoming: ${preview.manifest.clients.length} clients, '
                    '${preview.manifest.applications.length} applications, '
                    '${preview.manifest.payments.length} payments, '
                    '${preview.manifest.documents.length} document records, '
                    '${preview.manifest.tasks.length} tasks.',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'On this server now: '
                    '${preview.currentCounts.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
                  ),
                  if (extraWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        extraWarning,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
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
                child: Text(confirmLabel),
              ),
            ],
          ),
    );
  }

  Future<void> _restoreToNewWorkspace(
    RestorePreview preview,
    Uint8List archiveBytes,
    String name,
  ) async {
    if (name.isEmpty) {
      _snack('Choose a name for the new workspace.', error: true);
      return;
    }
    final go = await _confirmRestore(
      preview: preview,
      headline: 'Create "$name" and restore?',
      bullets: [
        'A brand-new workspace "$name" is created and every record and '
            'document from the archive is written into it.',
        'You become its Admin. Other people are not restored; invite them '
            'again afterwards.',
        'Records keep their IDs; if the archive is restored repeatedly into '
            'the same new workspace they are overwritten, never duplicated.',
      ],
      extraWarning: _missingFilesWarning(preview),
      confirmLabel: 'Create & restore',
    );
    if (go != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.auth.createWorkspace(name);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(_clean(e))),
      );
      return;
    }
    await _performRestore(
      preview,
      archiveBytes,
      intoNewWorkspace: true,
      targetWorkspaceId: widget.auth.workspaceId!,
    );
  }

  Future<void> _restoreToThisWorkspace(
    RestorePreview preview,
    Uint8List archiveBytes,
  ) async {
    var typed = false;
    final go = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => AlertDialog(
                  title: const Text('Type RESTORE to confirm'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This writes every archived record into the current '
                        'workspace. Records and documents whose IDs match are '
                        'overwritten in place. Nothing is deleted. This cannot be '
                        'undone with one click.',
                      ),
                      if (_missingFilesWarning(preview) != null) ...[
                        const SizedBox(height: 8),
                        Text(_missingFilesWarning(preview)!),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Type RESTORE here',
                        ),
                        onChanged:
                            (v) => setDialogState(
                              () =>
                                  typed = v.trim() == BackupUi.typedConfirmWord,
                            ),
                        onSubmitted:
                            (v) => Navigator.pop(
                              dialogContext,
                              v.trim() == BackupUi.typedConfirmWord,
                            ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          typed
                              ? () => Navigator.pop(dialogContext, true)
                              : null,
                      child: const Text('Restore now'),
                    ),
                  ],
                ),
          ),
    );
    if (go != true || !mounted) return;
    await _performRestore(
      preview,
      archiveBytes,
      intoNewWorkspace: false,
      targetWorkspaceId: widget.auth.workspaceId!,
    );
  }

  Future<void> _performRestore(
    RestorePreview preview,
    Uint8List archiveBytes, {
    required bool intoNewWorkspace,
    required String targetWorkspaceId,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final overwriting = !intoNewWorkspace;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => const AlertDialog(
            title: Text('Restoring...'),
            content: LinearProgressIndicator(),
          ),
    );
    try {
      final result = await _restore.performRestore(
        preview: preview,
        archiveBytes: archiveBytes,
        intoNewWorkspace: intoNewWorkspace,
        targetWorkspaceId: targetWorkspaceId,
      );
      navigator.pop();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: Text(
                result.allGood
                    ? 'Restore complete'
                    : 'Restore finished with problems',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (overwriting)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Matching IDs in this workspace were overwritten in '
                          'place; nothing was deleted.',
                        ),
                      ),
                    for (final e in result.written.entries)
                      if (e.value > 0) Text('Written · ${e.key}: ${e.value}'),
                    if (result.failures.isNotEmpty)
                      Text(
                        'Rows that failed (retries are safe):\n'
                        '${result.failures.take(8).join('\n')}',
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    if (result.fileFailures.isNotEmpty)
                      Text(
                        'Document files that failed to upload:\n'
                        '${result.fileFailures.take(8).join('\n')}',
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              ],
            ),
      );
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(_clean(e))),
      );
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.supabaseReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('Backups & recovery')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 44),
              SizedBox(height: 12),
              Text(BackupUi.offlineNote, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final isAdmin = widget.auth.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('Backups & recovery')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'New backup',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Snapshots the whole workspace — clients, applications, '
                      'payments, document records with their file bytes, and '
                      'the tasks stored on this device — into one ZIP kept in '
                      'a private, admin-only storage bucket. Up to 50 backups '
                      'are kept.',
                    ),
                    const SizedBox(height: 12),
                    if (_backingUp) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        _backupStep,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: isAdmin ? _runBackup : null,
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(isAdmin ? 'Back up now' : 'Admins only'),
                      ),
                  ],
                ),
              ),
            ),
            FutureBuilder<BackupCadence>(
              future: BackupScheduler.schedulerInstance.readCadence(),
              builder: (context, snapshot) {
                final cadence = snapshot.data ?? BackupCadence.off;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Automatic backups (app-open scheduling)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Runs once per day or week when the app is opened '
                          'and overdue. It needs the app open — nothing runs '
                          'while the app is closed. A real server-side '
                          'scheduler is separate future infrastructure, not '
                          'part of this app.',
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<BackupCadence>(
                          segments: const [
                            ButtonSegment(
                              value: BackupCadence.off,
                              label: Text('Off'),
                              icon: Icon(Icons.block_outlined),
                            ),
                            ButtonSegment(
                              value: BackupCadence.daily,
                              label: Text('Daily'),
                              icon: Icon(Icons.calendar_today_outlined),
                            ),
                            ButtonSegment(
                              value: BackupCadence.weekly,
                              label: Text('Weekly'),
                              icon: Icon(Icons.date_range_outlined),
                            ),
                          ],
                          selected: {cadence},
                          onSelectionChanged: (selection) {
                            final next = selection.first;
                            BackupScheduler.schedulerInstance.setCadence(next);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (!isAdmin)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Read-only for staff'),
                  subtitle: Text(
                    'You can browse history and download archives, but only '
                    'Admins can create backups, restore or delete.',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Backup history',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            FutureBuilder<List<BackupEntry>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Could not load the backup history.'),
                  );
                }
                final entries = snapshot.data ?? const <BackupEntry>[];
                if (entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('No backups yet.'),
                  );
                }
                return Column(
                  children: [for (final entry in entries) _historyCard(entry)],
                );
              },
            ),
            const SizedBox(height: 8),
            const ListTile(
              leading: Icon(Icons.schedule_outlined),
              title: Text('Automatic backups'),
              subtitle: Text(
                'Daily or weekly automatic backups arrive in a later update.',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Data safety notes'),
              subtitle: Text(
                'Only Admins can restore. Restores are verified first with a '
                'checksum; matching record IDs are overwritten in place and '
                'records are never deleted. Team members are not restored; '
                'invite them again in the new workspace.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(BackupEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor =
        entry.failed
            ? scheme.error
            : entry.completed
            ? Brand.green
            : scheme.outline;
    final icon =
        entry.failed
            ? Icons.error_outline
            : entry.running
            ? Icons.autorenew
            : entry.completed
            ? Icons.verified_outlined
            : Icons.hourglass_empty;
    final isAdmin = widget.auth.isAdmin;
    final canRestore = entry.completed && entry.storagePath != null;
    final busy = _busyEntryId == entry.id;
    final error = entry.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading:
                  busy
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : Icon(icon, color: statusColor),
              title: Text(
                '${BackupUi.statusLabel(entry)} · ${BackupUi.kindLabel(entry)}',
              ),
              subtitle: Text(
                '${BackupUi.createdLabel(entry)}'
                '${entry.completed || entry.failed ? '' : ' — in progress'}',
              ),
            ),
            if (entry.sizeBytes != null || entry.recordCount != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (entry.recordCount != null)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${entry.recordCount} records'),
                      ),
                    if (entry.fileCount != null)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${entry.fileCount} files'),
                      ),
                    if (entry.sizeBytes != null)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(BackupUi.formatBytes(entry.sizeBytes!)),
                      ),
                  ],
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(error, style: TextStyle(color: scheme.error)),
              ),
            if (canRestore)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _download(entry),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Archive'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: isAdmin ? () => _startRestore(entry) : null,
                      icon: const Icon(Icons.restore_outlined, size: 18),
                      label: const Text('Restore...'),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'delete') _delete(entry);
                      },
                      itemBuilder:
                          (context) => const [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
