import '../models/client_record_extensions.dart';
import '../models/client_record.dart';
import 'app_config.dart';
import 'local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClientRepository {
  final LocalStore local;
  final String? workspaceId;
  ClientRepository(this.local, {this.workspaceId});

  /// Columns that may be missing until the updated schema.sql has been run in
  /// Supabase. Saving still works without them; they are stripped from the
  /// payload and retried once if the server rejects them.
  static const _optionalColumns = {'archived', 'profile'};

  Future<List<ClientRecord>> all() async {
    if (!AppConfig.supabaseReady) return local.getClients();
    try {
      final rows = await Supabase.instance.client
          .from('clients')
          .select()
          .order('updated_at', ascending: false);
      final records =
          (rows as List)
              .map((e) => ClientRecord.fromJson(Map<String, dynamic>.from(e)))
              .toList();
      await local.saveClients(records);
      return records;
    } catch (_) {
      return local.getClients();
    }
  }

  Future<void> upsert(ClientRecord record) async {
    final cached = await local.getClients();
    final i = cached.indexWhere((c) => c.id == record.id);
    if (i < 0) {
      cached.insert(0, record);
    } else {
      cached[i] = record;
    }
    await local.saveClients(cached);
    if (AppConfig.supabaseReady) {
      if (workspaceId == null) {
        throw Exception('Join or create a workspace before saving clients.');
      }
      final payload = record.toJson();
      payload['workspace_id'] = workspaceId;
      while (payload.isNotEmpty) {
        try {
          await Supabase.instance.client.from('clients').upsert(payload);
          return;
        } on PostgrestException catch (e) {
          final missing =
              _optionalColumns
                  .where(payload.containsKey)
                  .where((col) => e.message.contains(col))
                  .toList();
          if (missing.isEmpty) rethrow;
          for (final col in missing) {
            payload.remove(col);
          }
        }
      }
    }
  }

  /// Marks a client archived (shown in the Archived filter) or active again.
  /// Kept out of the normal save path so plain edits never fail on a database
  /// that has not run the schema update yet.
  Future<void> setArchived(String id, bool archived) async {
    final cached = await local.getClients();
    final i = cached.indexWhere((c) => c.id == id);
    if (i >= 0) {
      cached[i] = cached[i].copyWith(archived: archived);
      await local.saveClients(cached);
    }
    if (AppConfig.supabaseReady) {
      try {
        final updated = await Supabase.instance.client
            .from('clients')
            .update({'archived': archived})
            .eq('id', id)
            .select('id');
        if (updated.isEmpty) {
          throw Exception(
            'The server did not archive this client. You may not have permission.',
          );
        }
      } on PostgrestException catch (e) {
        if (e.message.contains('archived')) {
          throw Exception(
            'Archiving needs the updated schema.sql in Supabase.',
          );
        }
        rethrow;
      }
    }
  }

  Future<void> delete(String id) async {
    if (AppConfig.supabaseReady) {
      // Ask the server to return the deleted rows. If Row Level Security
      // refuses the delete, zero rows come back and we must not pretend it worked.
      final deleted = await Supabase.instance.client
          .from('clients')
          .delete()
          .eq('id', id)
          .select('id');
      if (deleted.isEmpty) {
        throw Exception(
          'The server did not delete this client. You may not have permission.',
        );
      }
    }
    final cached = await local.getClients();
    await local.saveClients(cached.where((c) => c.id != id).toList());
  }
}
