import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'backup_models.dart';

/// Row + storage management for workspace backups. Every call here runs with
/// the signed-in user's permissions only - the same authorization the server
/// applies:
///   * read/list rows            -> workspace members (RLS select)
///   * create/update/delete rows -> workspace admins only (RLS policies)
///   * upload/read/delete ZIPs   -> admins via storage policies
class BackupRepository {
  static const table = 'workspace_backups';
  static const bucket = 'workspace-backups';

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<BackupEntry>> list(String workspaceId) async {
    final rows = await _client
        .from(table)
        .select()
        .eq('workspace_id', workspaceId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => BackupEntry.fromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Creates the history row first so a backup run is always accountable:
  /// pending -> running -> completed | failed. Any crash therefore leaves a
  /// visible row that is never silently "completed".
  Future<BackupEntry> createPending({
    required String workspaceId,
    required String kind,
  }) async {
    final row =
        await _client
            .from(table)
            .insert({
              'workspace_id': workspaceId,
              'kind': kind,
              'status': 'pending',
            })
            .select()
            .single();
    return BackupEntry.fromRow(Map<String, dynamic>.from(row));
  }

  Future<void> updateStatus(
    String id, {
    required String status,
    String? storagePath,
    int? sizeBytes,
    int? recordCount,
    int? fileCount,
    String? manifestSha256,
    String? error,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    final payload = <String, dynamic>{'status': status};
    void put(String column, Object? value) {
      if (value != null) payload[column] = value;
    }

    put('storage_path', storagePath);
    put('size_bytes', sizeBytes);
    put('record_count', recordCount);
    put('file_count', fileCount);
    put('manifest_sha256', manifestSha256);
    put('error', error);
    put('started_at', startedAt?.toUtc().toIso8601String());
    put('finished_at', finishedAt?.toUtc().toIso8601String());
    await _client.from(table).update(payload).eq('id', id);
  }

  /// Database error messages could be long or contain names; the column allows
  /// 2000 chars, so this keeps the write inside the constraint.
  static String errorText(Object rawError) {
    var text = '$rawError';
    text = text.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    const messageMarker = 'RpcException: message: ';
    final at = text.indexOf(messageMarker);
    if (at >= 0) text = text.substring(at + messageMarker.length);
    if (text.length > 2000) text = text.substring(0, 2000);
    return text;
  }

  Future<int> countCompleted(String workspaceId) async {
    final rows = await _client
        .from(table)
        .select('id')
        .eq('workspace_id', workspaceId)
        .eq('status', 'completed');
    return (rows as List).length;
  }

  Future<BackupEntry?> oldestCompleted(String workspaceId) async {
    final rows = await _client
        .from(table)
        .select()
        .eq('workspace_id', workspaceId)
        .eq('status', 'completed')
        .order('created_at', ascending: true)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return BackupEntry.fromRow(Map<String, dynamic>.from(list.first as Map));
  }

  String pathFor({required String workspaceId, required String backupId}) =>
      '$workspaceId/$backupId.zip';

  /// Storage write happens with the admin's own permissions; the policy keeps
  /// the exact `<workspace>/<uuid>.zip` shape (2 folders), which pathFor obeys.
  Future<void> uploadZip(String path, Uint8List bytes) async {
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'application/zip',
            upsert: true,
          ),
        );
  }

  Future<Uint8List?> downloadZip(String path) async {
    if (!AppConfig.supabaseReady) return null;
    return _client.storage.from(bucket).download(path);
  }

  /// Storage delete is attempted first so a row never survives while its file
  /// is gone in the other direction. Missing objects are tolerated.
  Future<void> deleteFileThenRow(BackupEntry entry) async {
    final path = entry.storagePath;
    if (path != null && path.isNotEmpty) {
      try {
        await _client.storage.from(bucket).remove([path]);
      } catch (_) {
        // The object may already be gone; row deletion still proceeds so no
        // history entry points at a file nobody can read.
      }
    }
    await _client.from(table).delete().eq('id', entry.id);
  }

  /// Short-lived private link for one archive; only admins can mint it.
  Future<String> createSignedUrl(String path, {int seconds = 600}) async {
    return _client.storage.from(bucket).createSignedUrl(path, seconds);
  }
}
