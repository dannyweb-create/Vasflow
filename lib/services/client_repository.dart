import '../models/client_record.dart';
import 'app_config.dart';
import 'local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClientRepository {
  final LocalStore local;
  ClientRepository(this.local);

  Future<List<ClientRecord>> all() async {
    if (!AppConfig.supabaseReady) return local.getClients();
    try {
      final rows = await Supabase.instance.client.from('clients').select().order('updated_at', ascending: false);
      final records = (rows as List).map((e) => ClientRecord.fromJson(Map<String,dynamic>.from(e))).toList();
      await local.saveClients(records);
      return records;
    } catch (_) {
      return local.getClients();
    }
  }

  Future<void> upsert(ClientRecord record) async {
    final cached = await local.getClients();
    final i = cached.indexWhere((c) => c.id == record.id);
    if (i < 0) { cached.insert(0, record); } else { cached[i] = record; }
    await local.saveClients(cached);
    if (AppConfig.supabaseReady) {
      await Supabase.instance.client.from('clients').upsert(record.toJson());
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
