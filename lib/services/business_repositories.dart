import 'dart:typed_data';

import '../models/application_record.dart';
import '../models/client_record.dart';
import '../models/document_record.dart';
import '../models/payment_record.dart';
import 'app_config.dart';
import 'local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A generic workspace repository used by the applications, payments and
/// documents tables. It follows the same pattern as ClientRepository:
/// the local cache is written first, then the row goes to Supabase when the
/// app is connected; reads fall back to the cache when the network fails.
class WorkspaceTable<T> {
  final LocalStore local;
  final String? workspaceId;
  final String table;
  final String cacheKey;
  final T Function(Map<String, dynamic>) parse;
  final String Function(T) idOf;

  /// Deleting stored files is sensitive; documents require an Admin, so the
  /// error message matches the server policy.
  final bool adminDelete;

  WorkspaceTable({
    required this.local,
    required this.workspaceId,
    required this.table,
    required this.cacheKey,
    required this.parse,
    required this.idOf,
    this.adminDelete = false,
  });

  String get tableNotFoundHint =>
      'The "$table" table is missing in Supabase. '
      'Run supabase/phase4_features.sql in the SQL Editor.';

  List<T> _parseRows(List<Map<String, dynamic>> rows) =>
      rows.map(parse).toList();

  Map<String, dynamic> _jsonOf(T item) {
    if (item is ApplicationRecord) return item.toJson();
    if (item is PaymentRecord) return item.toJson();
    if (item is DocumentRecord) return item.toJson();
    if (item is ClientRecord) return item.toJson();
    throw UnsupportedError('Unsupported registry item type');
  }

  Future<List<T>> load() async {
    final cached = _parseRows(await local.getRegistryJson(cacheKey));
    if (!AppConfig.supabaseReady) return cached;
    try {
      final rows = await Supabase.instance.client
          .from(table)
          .select()
          .order('updated_at', ascending: false);
      final records =
          (rows as List)
              .map((e) => parse(Map<String, dynamic>.from(e)))
              .toList();
      await local.saveRegistryJson(cacheKey, records.map(_jsonOf).toList());
      return records;
    } catch (_) {
      return cached;
    }
  }

  Future<void> upsert(T item) async {
    if (workspaceId == null) {
      throw Exception('Join or create a workspace before saving records.');
    }
    final rowId = idOf(item);
    final payload = _jsonOf(item);
    payload['id'] = rowId;
    payload['workspace_id'] = workspaceId;

    final cached = await local.getRegistryJson(cacheKey);
    final i = cached.indexWhere((row) => '${row['id']}' == rowId);
    if (i < 0) {
      cached.insert(0, payload);
    } else {
      cached[i] = payload;
    }
    await local.saveRegistryJson(cacheKey, cached);

    if (AppConfig.supabaseReady) {
      try {
        await Supabase.instance.client.from(table).upsert(payload);
      } on PostgrestException catch (e) {
        if (e.code == '42P01') {
          // 42P01 = undefined_table: the phase 4 migration has not been run.
          throw Exception(tableNotFoundHint);
        }
        rethrow;
      }
    }
  }

  Future<void> delete(String id) async {
    if (AppConfig.supabaseReady) {
      final deleted = await Supabase.instance.client
          .from(table)
          .delete()
          .eq('id', id)
          .select('id');
      if (deleted.isEmpty) {
        throw Exception(
          adminDelete
              ? 'The server refused the delete. Only an Admin can delete records here.'
              : 'The server did not delete this record. You may not have permission.',
        );
      }
    }
    final cached = await local.getRegistryJson(cacheKey);
    await local.saveRegistryJson(
      cacheKey,
      cached.where((row) => '${row['id']}' != id).toList(),
    );
  }
}

/// Multiple university/visa applications per client.
class ApplicationRepository {
  final WorkspaceTable<ApplicationRecord> table;
  ApplicationRepository(LocalStore local, {String? workspaceId})
    : table = WorkspaceTable(
        local: local,
        workspaceId: workspaceId,
        table: 'client_applications',
        cacheKey: 'vasflow_applications_v1',
        parse: ApplicationRecord.fromJson,
        idOf: (app) => app.id,
      );

  Future<List<ApplicationRecord>> load() => table.load();

  Future<List<ApplicationRecord>> forClient(String clientId) async =>
      (await load()).where((a) => a.clientId == clientId).toList();

  Future<void> upsert(ApplicationRecord app) => table.upsert(app);

  Future<void> delete(String id) => table.delete(id);
}

/// Fees, amounts paid, balances and transaction references per client.
class PaymentRepository {
  final WorkspaceTable<PaymentRecord> table;
  PaymentRepository(LocalStore local, {String? workspaceId})
    : table = WorkspaceTable(
        local: local,
        workspaceId: workspaceId,
        table: 'client_payments',
        cacheKey: 'vasflow_payments_v1',
        parse: PaymentRecord.fromJson,
        idOf: (p) => p.id,
      );

  Future<List<PaymentRecord>> load() => table.load();

  Future<List<PaymentRecord>> forClient(String clientId) async =>
      (await load()).where((p) => p.clientId == clientId).toList();

  Future<void> upsert(PaymentRecord payment) => table.upsert(payment);

  Future<void> delete(String id) => table.delete(id);
}

/// Client documents backed by the private 'client-documents' storage bucket.
/// Deleting a document requires an Admin (files are sensitive evidence).
class DocumentRepository {
  final WorkspaceTable<DocumentRecord> table;
  DocumentRepository(LocalStore local, {String? workspaceId})
    : table = WorkspaceTable(
        local: local,
        workspaceId: workspaceId,
        table: 'client_documents',
        cacheKey: 'vasflow_documents_v1',
        parse: DocumentRecord.fromJson,
        idOf: (d) => d.id,
        adminDelete: true,
      );

  static const bucket = 'client-documents';

  Future<List<DocumentRecord>> load() => table.load();

  Future<List<DocumentRecord>> forClient(String clientId) async =>
      (await load()).where((d) => d.clientId == clientId).toList();

  Future<void> upsert(DocumentRecord doc) => table.upsert(doc);

  Future<void> delete(String id) => table.delete(id);

  /// Removes the physical file from storage. Admins only.
  bool get backendRequired => !AppConfig.supabaseReady;

  Future<void> removeFile(String filePath) async {
    if (AppConfig.supabaseReady) {
      await Supabase.instance.client.storage.from(bucket).remove([filePath]);
    }
  }

  /// Bytes for saving a copy on the device. Requires the backend.
  Future<Uint8List?> download(String filePath) async {
    if (!AppConfig.supabaseReady) return null;
    return Supabase.instance.client.storage.from(bucket).download(filePath);
  }

  /// Uploads bytes into the workspace/client folder and returns the path.
  Future<String> upload({
    required String workspaceFolder,
    required String clientFolder,
    required String fileName,
    required Uint8List bytes,
    String? contentType,
  }) async {
    if (!AppConfig.supabaseReady) {
      throw Exception('Documents need a Supabase connection to upload.');
    }
    final path = '$workspaceFolder/$clientFolder/$fileName';
    await Supabase.instance.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    return path;
  }
}
