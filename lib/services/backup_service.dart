import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'auth_service.dart';
import 'backup_models.dart';
import 'backup_repository.dart';
import 'local_store.dart';

/// What one finished backup run reports back.
class BackupResult {
  final BackupEntry entry;
  final Map<String, int> counts;
  final int fileCount;
  final int sizeBytes;
  final List<String> missingFiles;

  const BackupResult({
    required this.entry,
    required this.counts,
    required this.fileCount,
    required this.sizeBytes,
    required this.missingFiles,
  });
}

/// Internal shape of one workspace snapshot: the manifest plus the bytes of
/// every document that could be downloaded.
class WorkspaceSnapshot {
  const WorkspaceSnapshot(this.manifest, this.fileBytes);
  final BackupManifest manifest;
  final Map<String, Uint8List> fileBytes;
}

/// Cloud backup of a whole workspace. Runs entirely with the signed-in
/// admin's permissions (Supabase RLS + storage policies); no privileged keys.
/// The server keeps enforcing everything no matter what this class does.
class BackupService {
  static const _docBucket = 'client-documents';
  static const maxCompletedBackups = 50;

  final BackupRepository repo;
  final AuthService auth;
  final LocalStore local;

  SupabaseClient get _client => Supabase.instance.client;

  BackupService({required this.repo, required this.auth, required this.local});

  bool get isAdmin => auth.isAdmin;
  String? get workspaceId => auth.workspaceId;

  /// Overridable connection guard; lets focused tests run the orchestration
  /// against a fake repository without touching Supabase.
  bool get ready => AppConfig.supabaseReady;

  /// Full run. Throws after recording the failure on the history row, so a
  /// crash can never leave a half-important state behind and nothing gets
  /// silently marked completed. [onStep] receives short human progress labels
  /// and is purely informational - the run logic never depends on it.
  Future<BackupResult> run({
    bool automatic = false,
    void Function(String step)? onStep,
  }) async {
    if (!ready) {
      throw Exception('Backups need a Supabase connection.');
    }
    final wsId = workspaceId;
    if (wsId == null || wsId.isEmpty) {
      throw Exception('Join or create a workspace before backing up.');
    }
    if (!isAdmin) {
      throw Exception('Only an Admin can create backups.');
    }
    void step(String text) => onStep?.call(text);
    final kind = automatic ? 'auto' : 'manual';
    final entry = await repo.createPending(workspaceId: wsId, kind: kind);
    try {
      await _ensureCapacity(wsId);
      await repo.updateStatus(
        entry.id,
        status: 'running',
        startedAt: DateTime.now(),
      );

      step('Collecting workspace data...');
      final snapshot = await snapshotFor(wsId);
      final manifest = snapshot.manifest;
      step('Archiving ${manifest.fileCount} document(s) in the archive...');
      final fileBytes = snapshot.fileBytes;

      final manifestBytes = Uint8List.fromList(utf8.encode(manifest.encode()));
      final manifestSha = BackupManifest.checksumOf(manifestBytes);

      final archive = Archive();
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );
      for (final item in fileBytes.entries) {
        final bytes = item.value;
        archive.addFile(ArchiveFile(item.key, bytes.length, bytes));
      }
      final zipBytes = Uint8List.fromList(
        ZipEncoder().encode(archive) ?? <int>[],
      );
      if (zipBytes.isEmpty) {
        throw Exception('The backup archive could not be created.');
      }

      step('Uploading archive...');
      final path = repo.pathFor(workspaceId: wsId, backupId: entry.id);
      await repo.uploadZip(path, zipBytes);

      final counts = {...manifest.counts, 'files': manifest.fileCount};
      Future<void> finalize() => repo.updateStatus(
        entry.id,
        status: 'completed',
        storagePath: path,
        sizeBytes: zipBytes.length,
        recordCount: counts.values.fold<int>(0, (a, b) => a + b),
        fileCount: manifest.fileCount,
        manifestSha256: manifestSha,
        finishedAt: DateTime.now(),
      );
      step('Finishing...');
      try {
        await finalize();
      } on PostgrestException catch (e) {
        // Two admins finishing backups at the same moment can race the
        // server-side 50-cap. Prune the oldest completed row (with its file)
        // once and finalize again.
        if (!e.message.contains('50 completed backups')) rethrow;
        await _pruneOne(wsId);
        await finalize();
      }

      final rows = await repo.list(wsId);
      final finalRow = rows.firstWhere(
        (r) => r.id == entry.id,
        orElse: () => entry,
      );
      return BackupResult(
        entry: finalRow,
        counts: counts,
        fileCount: manifest.fileCount,
        sizeBytes: zipBytes.length,
        missingFiles: manifest.missingFiles,
      );
    } catch (e) {
      // Never mark an incomplete run complete; keep the reason short.
      try {
        await repo.updateStatus(
          entry.id,
          status: 'failed',
          error: BackupRepository.errorText(e),
          finishedAt: DateTime.now(),
        );
      } catch (_) {
        // A failing history update must not hide the original problem.
      }
      rethrow;
    }
  }

  /// Frees history room before a new run: deletes the oldest completed row
  /// *and* its storage object together, so files are never left orphaned.
  Future<void> _ensureCapacity(String wsId) async {
    while (true) {
      final count = await repo.countCompleted(wsId);
      if (count < maxCompletedBackups) return;
      final oldest = await repo.oldestCompleted(wsId);
      if (oldest == null) return; // RLS hid it; the server trigger will talk.
      await repo.deleteFileThenRow(oldest);
    }
  }

  Future<void> _pruneOne(String wsId) async {
    final oldest = await repo.oldestCompleted(wsId);
    if (oldest != null) await repo.deleteFileThenRow(oldest);
  }

  /// Overridable snapshot step (defaults to the real Supabase snapshot).
  Future<WorkspaceSnapshot> snapshotFor(String wsId) => _snapshot(wsId);

  /// Reads every workspace-scoped row through the normal RLS-authorized
  /// selects (raw maps preserve all columns, incl. profile JSONB), pulls the
  /// actual document bytes, and builds the versioned manifest.
  Future<WorkspaceSnapshot> _snapshot(String wsId) async {
    final client = _client;
    final user = client.auth.currentUser;
    final email = user?.email ?? auth.currentEmail;

    final workspaceRow =
        await client.from('workspaces').select().eq('id', wsId).single();

    List<Map<String, dynamic>> members;
    try {
      // Admin-only helper; returns every member of this workspace.
      final team = await client.rpc('list_team');
      members =
          (team as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
    } catch (_) {
      // Fallback: just this person's own membership row (the only one that
      // is directly readable for members).
      members = [];
      if (user?.id != null) {
        try {
          final own = await client
              .from('workspace_members')
              .select('workspace_id, user_id, role, created_at')
              .eq('user_id', user!.id);
          members =
              (own as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
        } catch (_) {
          members = [];
        }
      }
    }

    final clients = _rows(await client.from('clients').select());
    final applications = _rows(
      await client.from('client_applications').select(),
    );
    final payments = _rows(await client.from('client_payments').select());
    final documents = _rows(await client.from('client_documents').select());

    final taskRows = await local.getTasks();

    final fileBytes = <String, Uint8List>{};
    final missing = <String>[];
    final checksums = <String, String>{};
    for (final doc in documents) {
      final clientId = '${doc['client_id']}';
      final docId = '${doc['id']}';
      final filePath = '${doc['file_path'] ?? ''}';
      final key = BackupManifest.documentKeyForPath(clientId, docId, filePath);
      try {
        final bytes = await client.storage.from(_docBucket).download(filePath);
        fileBytes[key] = bytes;
        checksums[key] = BackupManifest.fileChecksum(bytes);
      } catch (_) {
        // The row says the document exists but storage cannot serve it; back
        // up the metadata anyway and report the gap in the manifest.
        missing.add(key);
      }
    }

    final manifest = BackupManifest(
      workspace: workspaceRow,
      members: members,
      clients: clients,
      applications: applications,
      payments: payments,
      documents: documents,
      tasks: taskRows.map((t) => t.toJson()).toList(),
      fileChecksums: checksums,
      missingFiles: missing,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      createdByEmail: email,
    );
    return WorkspaceSnapshot(manifest, fileBytes);
  }

  static List<Map<String, dynamic>> _rows(Object raw) =>
      (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
