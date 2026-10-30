import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/client_record.dart';
import '../models/task_record.dart';

/// Cross-platform lightweight offline cache. For multi-user production use,
/// replace/extend with encrypted SQLite and a sync queue.
class LocalStore {
  static const _key = 'vasflow_clients_v1';
  static const _taskKey = 'vasflow_tasks_v1';
  static const _keyApplications = 'vasflow_applications_v1';
  static const _keyPayments = 'vasflow_payments_v1';
  static const _keyDocuments = 'vasflow_documents_v1';
  static const _uuid = Uuid();

  Future<List<ClientRecord>> getClients() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ClientRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveClients(List<ClientRecord> clients) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode(clients.map((e) => e.toJson()).toList()),
    );
  }

  /// Generic offline cache in JSON form for the applications, payments and
  /// documents repositories, mirroring the clients cache behaviour.
  Future<List<Map<String, dynamic>>> getRegistryJson(String cacheKey) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(cacheKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRegistryJson(
    String cacheKey,
    List<Map<String, dynamic>> rows,
  ) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(cacheKey, jsonEncode(rows));
  }

  Future<void> removeFromCache(String cacheKey) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(cacheKey);
  }

  Future<List<TaskRecord>> getTasks() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_taskKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => TaskRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTasks(List<TaskRecord> tasks) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _taskKey,
      jsonEncode(tasks.map((e) => e.toJson()).toList()),
    );
  }

  /// Removes cached client, task and application/payment/document data
  /// (called on logout so the next person who signs in on this device cannot
  /// see the previous person's records).
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    await p.remove(_taskKey);
    await p.remove(_keyApplications);
    await p.remove(_keyPayments);
    await p.remove(_keyDocuments);
  }

  String newId() => _uuid.v4();
}
