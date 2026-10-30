import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'auth_service.dart';
import 'backup_models.dart';
import 'backup_repository.dart';
import '../models/task_record.dart';
import 'local_store.dart';

/// Validates a backup archive, shows exactly what would change, then restores
/// it idempotently. All writes run through the normal, RLS-checked tables:
///
///   * the target workspace id must come from an authoritative source (the
///     signed-in membership row or the create_workspace RPC). Even if a raw
///     workspace id were passed to the service, the server policies would
///     refuse every write, so nothing here trusts client-side claims;
///   * nothing is deleted during restore - every write is an upsert keyed on
///     the original record id, so retries repair rather than duplicate;
///   * parents are written before children so foreign keys stay satisfied;
///   * the manifest checksum is compared against the history row before the
///     preview, and every file checksum inside the archive is verified; any
///     mismatch blocks the restore.
/// Pure archive verification, separated from RestoreService so focused tests
/// can exercise corrupt archives, checksum failures and missing files without
/// a Supabase connection. [prepareBytes] uses the same logic.
class RestoreVerifier {
  /// What one archive verification found. No network and no Supabase involved
  /// anywhere in here.
  const RestoreVerifier({
    required this.manifestFound,
    required this.manifestVerified,
    required this.manifest,
    required this.fileProblems,
    required this.fatalError,
  });

  final bool manifestFound;

  /// True only when the manifest sha matched the history row (or the row had
  /// no stored sha) and the manifest decoded. A stored-sha mismatch is fatal.
  final bool manifestVerified;
  final BackupManifest? manifest;

  /// Per-file problems: missing files or checksum mismatches. A restore must
  /// never start while this list is non-empty.
  final List<String> fileProblems;

  /// Why preparation could not continue at all (missing manifest, replaced
  /// archive, undecodable manifest). Empty when the archive is usable.
  final String? fatalError;

  /// convenience for callers: safe to show a strategy picker.
  bool get usable => manifestFound && manifestVerified && fatalError == null;

  /// Verifies an in-memory archive: zip integrity, manifest presence,
  /// manifest sha against the history row, and every listed file checksum.
  /// Pure and side-effect-free.
  static RestoreVerifier verifyArchive(
    Uint8List zipBytes, {
    required String? expectedSha,
  }) {
    final error = <String>[];
    try {
      final zip = ZipDecoder().decodeBytes(zipBytes);
      final manifestFile = zip.findFile('manifest.json');
      if (manifestFile == null) {
        return const RestoreVerifier(
          manifestFound: false,
          manifestVerified: false,
          manifest: null,
          fileProblems: [],
          fatalError: 'manifest.json is missing from the backup.',
        );
      }
      final manifestBytes = Uint8List.fromList(
        List<int>.from(manifestFile.content as List<int>),
      );
      if (expectedSha != null &&
          expectedSha != BackupManifest.checksumOf(manifestBytes)) {
        return const RestoreVerifier(
          manifestFound: true,
          manifestVerified: false,
          manifest: null,
          fileProblems: [],
          fatalError:
              'This backup is damaged or was replaced after creation. Restore refused.',
        );
      }
      BackupManifest manifest;
      try {
        manifest = BackupManifest.decode(utf8.decode(manifestBytes));
      } on FormatException catch (e) {
        return RestoreVerifier(
          manifestFound: true,
          manifestVerified: false,
          manifest: null,
          fileProblems: const [],
          fatalError: 'Could not read the backup manifest: ${e.message}',
        );
      }
      final problems = <String>[];
      for (final doc in manifest.documents) {
        final clientId = '${doc['client_id']}';
        final docId = '${doc['id']}';
        final filePath = '${doc['file_path'] ?? ''}';
        final key = BackupManifest.documentKeyForPath(
          clientId,
          docId,
          filePath,
        );
        final expected = manifest.fileChecksums[key];
        if (expected == null) continue; // bytes were missing at backup time
        final fileData = zip.findFile(key);
        if (fileData == null) {
          problems.add('Missing from archive: $key');
          continue;
        }
        final actual = BackupManifest.fileChecksum(
          Uint8List.fromList(List<int>.from(fileData.content as List<int>)),
        );
        if (actual != expected) problems.add('Checksum mismatch: $key');
      }
      return RestoreVerifier(
        manifestFound: true,
        manifestVerified: true,
        manifest: manifest,
        fileProblems: problems,
        fatalError: null,
      );
    } on Exception catch (e) {
      error.add(e.toString());
      return RestoreVerifier(
        manifestFound: false,
        manifestVerified: false,
        manifest: null,
        fileProblems: const [],
        fatalError: error.first,
      );
    }
  }
}

class RestoreService {
  static const _docBucket = 'client-documents';
  static const _batch = 40;

  final BackupRepository repo;
  final AuthService auth;
  final LocalStore local;

  SupabaseClient get _client => Supabase.instance.client;

  RestoreService({required this.repo, required this.auth, required this.local});

  /// Downloads and fully validates the archive of one history row. Throws on
  /// manifest damage and collects file checksum problems into the preview so
  /// the caller can show them *before* any restore write happens.
  Future<RestorePreview> prepare(BackupEntry entry) async {
    if (!AppConfig.supabaseReady) {
      throw Exception('Restore needs a Supabase connection.');
    }
    final path = entry.storagePath;
    if (path == null || path.isEmpty) {
      throw Exception('This backup row has no archive attached.');
    }
    final zipBytes = await repo.downloadZip(path);
    if (zipBytes == null || zipBytes.isEmpty) {
      throw Exception('The backup archive could not be downloaded.');
    }
    return prepareBytes(entry, zipBytes);
  }

  /// Same validation, but for an archive the person restored from a device
  /// file after losing their workspace access.
  Future<RestorePreview> prepareBytes(
    BackupEntry entry,
    Uint8List zipBytes,
  ) async {
    final verification = RestoreVerifier.verifyArchive(
      zipBytes,
      expectedSha: entry.manifestSha256,
    );
    if (verification.fatalError != null) {
      throw Exception(verification.fatalError);
    }
    final manifest = verification.manifest!;
    final current = await _currentCounts();
    return RestorePreview(
      manifest: manifest,
      backupId: entry.id,
      manifestVerified: verification.manifestVerified,
      fileProblems: verification.fileProblems,
      currentCounts: current,
    );
  }

  /// Writes the restore. [targetWorkspaceId] must be the workspace the person
  /// actually owns: for fresh-device recovery the caller has just created it
  /// through the create_workspace RPC; otherwise it is the signed-in
  /// workspace id.
  Future<RestoreResult> performRestore({
    required RestorePreview preview,
    required Uint8List archiveBytes,
    required String targetWorkspaceId,
    required bool intoNewWorkspace,
  }) async {
    if (!preview.ready) {
      throw Exception('Restore blocked: archive validation found problems.');
    }
    final manifest = preview.manifest;
    final written = <String, int>{};
    final failures = <String>[];
    final fileFailures = <String>[];

    final zip = ZipDecoder().decodeBytes(archiveBytes);

    written['workspace'] = 0; // the workspace row itself is never rewritten

    await _upsertTable(
      table: 'clients',
      rows: BackupPlanner.retargetAll(manifest.clients, targetWorkspaceId),
      countKey: 'clients',
      label: 'client',
      written: written,
      failures: failures,
    );
    await _upsertTable(
      table: 'client_applications',
      rows: BackupPlanner.retargetAll(manifest.applications, targetWorkspaceId),
      countKey: 'applications',
      label: 'application',
      written: written,
      failures: failures,
    );
    await _upsertTable(
      table: 'client_payments',
      rows: BackupPlanner.retargetAll(manifest.payments, targetWorkspaceId),
      countKey: 'payments',
      label: 'payment',
      written: written,
      failures: failures,
    );

    // Documents: retarget the row, rewrite the file path, upload the bytes
    // into the target folder, then upsert the metadata row.
    var docOk = 0;
    final docRows = <Map<String, dynamic>>[];
    for (final doc in manifest.documents) {
      final clientId = '${doc['client_id']}';
      final docId = '${doc['id']}';
      final originalPath = '${doc['file_path'] ?? ''}';
      final targetPath = BackupPlanner.targetDocumentPath(
        workspaceId: targetWorkspaceId,
        clientId: clientId,
        rowFilePath: originalPath,
        documentRowIdFallback: docId,
      );
      final payload = BackupPlanner.retarget(doc, targetWorkspaceId);
      payload['file_path'] = targetPath;
      docRows.add(payload);

      var bytes = Uint8List(0);
      final key = BackupManifest.documentKeyForPath(
        clientId,
        docId,
        originalPath,
      );
      final fileData = zip.findFile(key);
      if (fileData != null) {
        bytes = Uint8List.fromList(
          List<int>.from(fileData.content as List<int>),
        );
      }
      if (bytes.isNotEmpty) {
        try {
          await _ensureDocumentFile(
            path: targetPath,
            bytes: bytes,
            mimeType: '${doc['mime_type'] ?? ''}',
            clientId: clientId,
          );
        } catch (e) {
          fileFailures.add('$docId: ${BackupRepository.errorText(e)}');
        }
      } else if (!manifest.missingFiles.contains(key)) {
        // Should not happen after prepare(); record it for completeness.
        fileFailures.add('$docId: missing in archive');
      }
    }
    for (var start = 0; start < docRows.length; start += _batch) {
      final end = (start + _batch).clamp(0, docRows.length);
      final chunk = docRows.sublist(start, end);
      final ok = await _upsertChunk(
        table: 'client_documents',
        chunk: chunk,
        label: 'document',
        failures: failures,
      );
      if (ok) docOk += chunk.length;
    }
    for (final fileFailure in fileFailures) {
      if (fileFailure.isNotEmpty) failures.add('file $fileFailure');
    }
    written['documents'] = docOk;

    // LocalStore tasks: device rows always win, restored rows fill gaps, and
    // nothing is deleted.
    final existingRows =
        (await local.getTasks()).map((t) => t.toJson()).toList();
    final mergedRows = BackupPlanner.mergeTasks(existingRows, manifest.tasks);
    await local.saveTasks([
      for (final row in mergedRows) TaskRecord.fromJson(row),
    ]);
    written['tasks'] = manifest.tasks.length;

    return RestoreResult(
      targetWorkspaceId: targetWorkspaceId,
      intoNewWorkspace: intoNewWorkspace,
      written: written,
      failures: failures,
      fileFailures: fileFailures,
    );
  }

  Future<Map<String, int>> _currentCounts() async {
    final counts = <String, int>{};
    Future<void> count(String table, String key) async {
      try {
        final rows = await _client.from(table).select('id');
        counts[key] = (rows as List).length;
      } catch (_) {
        counts[key] = -1; // unknown (offline, or tables not migrated yet)
      }
    }

    await count('clients', 'clients');
    await count('client_applications', 'applications');
    await count('client_payments', 'payments');
    await count('client_documents', 'documents');
    counts['workspace'] = auth.workspaceId == null ? 0 : 1;
    counts['tasks'] = -1;
    return counts;
  }

  Future<void> _upsertTable({
    required String table,
    required List<Map<String, dynamic>> rows,
    required String countKey,
    required String label,
    required Map<String, int> written,
    required List<String> failures,
  }) async {
    var okCount = 0;
    for (var start = 0; start < rows.length; start += _batch) {
      final end = (start + _batch).clamp(0, rows.length);
      final chunk = rows.sublist(start, end);
      var ok = await _upsertChunk(
        table: table,
        chunk: chunk,
        label: label,
        failures: failures,
      );
      if (ok) okCount += chunk.length;
    }
    written[countKey] = okCount;
  }

  /// Chunked upsert; when the chunk fails on a foreign key (some user that
  /// the rows reference no longer exists), it falls back to row-by-row
  /// upserts that drop optional user references and retry.
  Future<bool> _upsertChunk({
    required String table,
    required List<Map<String, dynamic>> chunk,
    required String label,
    required List<String> failures,
  }) async {
    try {
      await _client.from(table).upsert(chunk, onConflict: 'id');
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        var allOk = true;
        for (final row in chunk) {
          final ok = await _upsertSingleTolerant(
            table: table,
            row: row,
            failures: failures,
            label: label,
          );
          if (!ok) allOk = false;
        }
        return allOk;
      }
      failures.add('$label chunk: ${BackupRepository.errorText(e)}');
      return false;
    } catch (e) {
      failures.add('$label chunk: ${BackupRepository.errorText(e)}');
      return false;
    }
  }

  Future<bool> _upsertSingleTolerant({
    required String table,
    required Map<String, dynamic> row,
    required List<String> failures,
    required String label,
  }) async {
    final id = '${row['id']}';
    try {
      await _client.from(table).upsert(row, onConflict: 'id');
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        final relaxed = BackupPlanner.stripSoftForeignKeys(row);
        try {
          await _client.from(table).upsert(relaxed, onConflict: 'id');
          return true;
        } catch (e2) {
          failures.add('$label $id: ${BackupRepository.errorText(e2)}');
          return false;
        }
      }
      failures.add('$label $id: ${BackupRepository.errorText(e)}');
      return false;
    } catch (e) {
      failures.add('$label $id: ${BackupRepository.errorText(e)}');
      return false;
    }
  }

  /// Uploads document bytes unless the server already holds that exact file
  /// (same size at the target path) - retries skip the double upload.
  Future<void> _ensureDocumentFile({
    required String path,
    required Uint8List bytes,
    required String mimeType,
    required String clientId,
  }) async {
    final folderPath = path.substring(0, path.lastIndexOf('/'));
    try {
      final objects = await _client.storage
          .from(_docBucket)
          .list(path: folderPath);
      for (final object in objects) {
        final size = object.metadata?['size'];
        if (object.name == path.split('/').last &&
            size is num &&
            size == bytes.length) {
          return;
        }
      }
    } catch (_) {
      // Listing can fail; fall through to a plain upsert upload, which the
      // server revalidates against the same policies regardless.
    }
    await _client.storage
        .from(_docBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType.isEmpty ? null : mimeType,
            upsert: true,
          ),
        );
  }
}
