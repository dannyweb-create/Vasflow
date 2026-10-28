import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/client_record.dart';

/// Cross-platform lightweight offline cache. For multi-user production use,
/// replace/extend with encrypted SQLite and a sync queue.
class LocalStore {
  static const _key = 'vasflow_clients_v1';
  static const _uuid = Uuid();

  Future<List<ClientRecord>> getClients() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ClientRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) { return []; }
  }

  Future<void> saveClients(List<ClientRecord> clients) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(clients.map((e) => e.toJson()).toList()));
  }

  /// Removes cached client data (called on logout so the next person who signs
  /// in on this device cannot see the previous person's cached records).
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }

  String newId() => _uuid.v4();
}
