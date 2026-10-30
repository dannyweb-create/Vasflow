import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'dart:typed_data';

/// Model layer for the workspace cloud backup feature (Phase B). Raw Supabase
/// rows are carried as-is in maps so that every field survives, including the
/// clients `profile` JSONB blob, the `archived` flag and date strings, without
/// round-tripping through the app-facing models.
class BackupManifest {
  static const format = 'vasflow-backup';
  static const version = 1;

  static const _encode = JsonEncoder.withIndent(null);

  /// The workspace row, exactly as the RLS-authorized select returned it. The
  /// workspace name is recorded for reference; restores never write it back
  /// (see RestoreService).
  final Map<String, dynamic> workspace;

  /// Team snapshot; server-side only the caller's own membership is directly
  /// readable, admins also get the team through the list_team() function.
  final List<Map<String, dynamic>> members;

  /// Raw rows of clients, applications, payments and document metadata.
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> applications;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> documents;

  /// Device-registered tasks (LocalStore), included verbatim with their ids so
  /// a restore can merge them without duplicates.
  final List<Map<String, dynamic>> tasks;

  /// sha256 of every file carried inside the backup, keyed by its ZIP path:
  /// `files/<client id>/<document row id>-<file name>`
  final Map<String, String> fileChecksums;

  /// Document rows whose bytes were missing from storage while backing up.
  final List<String> missingFiles;

  final String createdAt;
  final String createdByEmail;

  const BackupManifest({
    required this.workspace,
    required this.members,
    required this.clients,
    required this.applications,
    required this.payments,
    required this.documents,
    required this.tasks,
    required this.fileChecksums,
    required this.missingFiles,
    required this.createdAt,
    required this.createdByEmail,
  });

  Map<String, dynamic> toMap() => {
    'format': format,
    'version': version,
    'created_at': createdAt,
    'created_by_email': createdByEmail,
    'workspace': workspace,
    'members': members,
    'clients': clients,
    'applications': applications,
    'payments': payments,
    'documents': documents,
    'tasks': tasks,
    'file_checksums': fileChecksums,
    'missing_files': missingFiles,
  };

  String encode() => json.encode(toMap());

  factory BackupManifest.decode(String raw) {
    final map = Map<String, dynamic>.from(json.decode(raw) as Map);
    if (map['format'] != format) {
      throw const FormatException('Not a VasFlow backup manifest.');
    }
    final parsedVersion =
        (map['version'] is int)
            ? map['version'] as int
            : int.tryParse('${map['version']}');
    if (parsedVersion == null || parsedVersion > version) {
      throw const FormatException(
        'This manifest needs a newer VasFlow version.',
      );
    }
    return BackupManifest(
      workspace: _stringKeyed(map['workspace']),
      members: _rowList(map['members']),
      clients: _rowList(map['clients']),
      applications: _rowList(map['applications']),
      payments: _rowList(map['payments']),
      documents: _rowList(map['documents']),
      tasks: _rowList(map['tasks']),
      fileChecksums: (map['file_checksums'] as Map? ?? {}).map(
        (k, v) => MapEntry('$k', '$v'),
      ),
      missingFiles:
          (map['missing_files'] as List? ?? []).map((e) => '$e').toList(),
      createdAt: '${map['created_at'] ?? ''}',
      createdByEmail: '${map['created_by_email'] ?? ''}',
    );
  }

  static Map<String, dynamic> _stringKeyed(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _rowList(Object? value) =>
      (value as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ??
      <Map<String, dynamic>>[];

  Map<String, int> get counts => {
    'workspace': workspace.isEmpty ? 0 : 1,
    'members': members.length,
    'clients': clients.length,
    'applications': applications.length,
    'payments': payments.length,
    'documents': documents.length,
    'tasks': tasks.length,
  };

  int get fileCount => fileChecksums.length;

  /// sha256 over the manifest JSON itself. Stored in the backup row, so the
  /// restore path can prove the manifest was not swapped or truncated.
  static String checksumOf(Uint8List bytes) => sha256.convert(bytes).toString();

  /// sha256 hex of any payload, used for document files inside the ZIP.
  static String fileChecksum(Uint8List bytes) =>
      sha256.convert(bytes).toString();

  /// ZIP-internal key for one document, built from stable ids (no filename
  /// collisions). Used identically by BackupService and RestoreService.
  static String documentKey(
    String clientId,
    String documentId,
    String fileName,
  ) => 'files/$clientId/$documentId-${sanitizeFileName(fileName)}';

  /// The single key builder both sides must agree on: derives the ZIP-internal
  /// name straight from the document row's file_path.
  static String documentKeyForPath(
    String clientId,
    String documentId,
    String rowFilePath,
  ) => documentKey(clientId, documentId, rowFilePath.split('/').last);

  /// Keeps ZIP paths flat and predictable; never lets a filename escape.
  static String sanitizeFileName(String name) =>
      name.replaceAll('/', '_').replaceAll('\\\\', '_').trim();

  static String prettyJson(Map<String, dynamic> map) => _encode.convert(map);
}

/// One workspace_backups row (the backup history entry).
class BackupEntry {
  final String id;
  final String workspaceId;
  final String? createdBy;
  final String kind;
  final String status;
  final String? manifestSha256;
  final int? sizeBytes;
  final int? recordCount;
  final int? fileCount;
  final String? storagePath;
  final String? error;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? createdAt;

  const BackupEntry({
    required this.id,
    required this.workspaceId,
    this.createdBy,
    required this.kind,
    required this.status,
    this.manifestSha256,
    this.sizeBytes,
    this.recordCount,
    this.fileCount,
    this.storagePath,
    this.error,
    this.startedAt,
    this.finishedAt,
    this.createdAt,
  });

  factory BackupEntry.fromRow(Map<String, dynamic> row) {
    return BackupEntry(
      id: '${row['id']}',
      workspaceId: '${row['workspace_id']}',
      createdBy: row['created_by'] == null ? null : '${row['created_by']}',
      kind: '${row['kind'] ?? 'manual'}',
      status: '${row['status'] ?? 'pending'}',
      manifestSha256: row['manifest_sha256']?.toString(),
      sizeBytes: _int(row['size_bytes']),
      recordCount: _int(row['record_count']),
      fileCount: _int(row['file_count']),
      storagePath: row['storage_path']?.toString(),
      error: row['error']?.toString(),
      startedAt: _date(row['started_at']),
      finishedAt: _date(row['finished_at']),
      createdAt: _date(row['created_at']),
    );
  }

  bool get completed => status == 'completed';
  bool get failed => status == 'failed';
  bool get running => status == 'running';

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

/// What the restore shows BEFORE any write happens.
class RestorePreview {
  final BackupManifest manifest;
  final String backupId;
  final bool manifestVerified;

  /// Checksum mismatches and extract failures caught before the preview.
  final List<String> fileProblems;

  /// Server-side counts, so the person can compare before restoring. Empty
  /// map when offline / the tables could not be read.
  final Map<String, int> currentCounts;

  const RestorePreview({
    required this.manifest,
    required this.backupId,
    required this.manifestVerified,
    required this.fileProblems,
    required this.currentCounts,
  });

  /// True only when the manifest checksum matched AND every included file
  /// verified - a restore must never start on a damaged archive.
  bool get ready => manifestVerified && fileProblems.isEmpty;
}

/// Outcome of a completed-or-failed restore run.
class RestoreResult {
  final String targetWorkspaceId;
  final bool intoNewWorkspace;
  final Map<String, int> written;

  /// Records that could not be written, with a short reason.
  final List<String> failures;
  final List<String> fileFailures;

  const RestoreResult({
    required this.targetWorkspaceId,
    required this.intoNewWorkspace,
    required this.written,
    required this.failures,
    required this.fileFailures,
  });

  bool get allGood => failures.isEmpty && fileFailures.isEmpty;
}

/// Helpers shared by both services so the two sides always agree on payload
/// shapes. Pure functions make the rules unit-testable.
class BackupPlanner {
  /// Restores point rows at a workspace id that was created or fetched through
  /// authoritative, server-derived means (create_workspace or the signed-in
  /// membership row). This function only sets the column; the server RLS is
  /// still the real authorization.
  static Map<String, dynamic> retarget(
    Map<String, dynamic> row,
    String workspaceId,
  ) => <String, dynamic>{...row, 'workspace_id': workspaceId};

  static List<Map<String, dynamic>> retargetAll(
    List<Map<String, dynamic>> rows,
    String workspaceId,
  ) => [for (final row in rows) retarget(row, workspaceId)];

  /// Reduced columns whose foreign keys may legitimately point at users that
  /// could disappear between backup and restore. Stripped only after the
  /// original write failed on a foreign-key violation, so everything else
  /// survives verbatim.
  static const softForeignKeys = ['owner_id', 'created_by', 'uploaded_by'];

  static Map<String, dynamic> stripSoftForeignKeys(Map<String, dynamic> row) =>
      <String, dynamic>{
        for (final entry in row.entries)
          if (!softForeignKeys.contains(entry.key)) entry.key: entry.value,
      };

  /// Builds the storage path a document gets after a restore: it must match
  /// the shape the client-documents policies expect
  /// `<workspace>/<client>/<uuid>-name.ext`, exactly 3 folders).
  static String targetDocumentPath({
    required String workspaceId,
    required String clientId,
    required String rowFilePath,
    required String documentRowIdFallback,
  }) {
    var base = rowFilePath.split('/').last;
    if (base.isEmpty) base = '$documentRowIdFallback-document';
    return '$workspaceId/$clientId/$base';
  }

  /// Merges manifest tasks into local tasks: existing device rows always win,
  /// restored rows only fill in the gaps (never delete anything).
  static List<Map<String, dynamic>> mergeTasks(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> restored,
  ) {
    final result = [...existing.map((e) => Map<String, dynamic>.from(e))];
    final ids = {for (final row in result) '${row['id']}'};
    for (final row in restored) {
      final id = '${row['id']}';
      if (id.isEmpty || ids.contains(id)) continue;
      result.add(Map<String, dynamic>.from(row));
    }
    return result;
  }
}
