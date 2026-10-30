import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'local_store.dart';

class AuthService {
  bool get online => AppConfig.supabaseReady;

  String _role = 'staff';
  String? _workspaceId;
  String _workspaceName = '';

  bool get hasSession =>
      online && Supabase.instance.client.auth.currentSession != null;

  String get currentEmail =>
      online ? (Supabase.instance.client.auth.currentUser?.email ?? '') : '';

  /// Used only to show or hide buttons. Real permissions are enforced by
  /// Supabase Row Level Security on the server, never by this value.
  String get role => _role;
  bool get isAdmin => _role == 'admin';
  String? get workspaceId => _workspaceId;
  String get workspaceName => _workspaceName;
  bool get hasWorkspace => _workspaceId != null;

  void _requireOnline() {
    if (!online) {
      throw Exception(
        'This build is not connected to a Supabase project. '
        'Add the SUPABASE_URL and SUPABASE_ANON_KEY secrets and rebuild.',
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<dynamic> _rpc(String function, [Map<String, dynamic>? params]) {
    return _guard<dynamic>(
      () async => await Supabase.instance.client.rpc(function, params: params),
    );
  }

  Future<void> signIn(String identifier, String password) async {
    _requireOnline();
    final id = identifier.trim();
    final auth = Supabase.instance.client.auth;
    await _guard(
      () =>
          id.contains('@')
              ? auth.signInWithPassword(email: id, password: password)
              : auth.signInWithPassword(phone: id, password: password),
    );
    await loadMembership();
  }

  /// Reads which workspace this person belongs to and their role in it.
  Future<void> loadMembership() async {
    _requireOnline();
    _role = 'staff';
    _workspaceId = null;
    _workspaceName = '';
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final row =
          await Supabase.instance.client
              .from('workspace_members')
              .select('workspace_id, role, workspaces(name)')
              .eq('user_id', user.id)
              .maybeSingle();
      if (row == null) return;
      _workspaceId = row['workspace_id'] as String?;
      _role = row['role'] == 'admin' ? 'admin' : 'staff';
      final ws = row['workspaces'];
      if (ws is Map) _workspaceName = '${ws['name'] ?? ''}';
    } on PostgrestException catch (e) {
      throw Exception(
        'Could not load your workspace: ${e.message}. '
        'If you have not run phase3_workspaces.sql in Supabase yet, run it first.',
      );
    }
  }

  Future<void> createWorkspace(String name) async {
    _requireOnline();
    await _rpc('create_workspace', {'p_name': name.trim()});
    await loadMembership();
  }

  Future<void> joinWorkspace(String code) async {
    _requireOnline();
    await _rpc('redeem_invite', {'p_code': code.trim()});
    await loadMembership();
  }

  /// Admin only (the server refuses anyone else). Returns the code once.
  Future<String> createInvite() async {
    _requireOnline();
    final code = await _rpc('create_invite');
    return '$code';
  }

  Future<List<Map<String, dynamic>>> listTeam() async {
    _requireOnline();
    final rows = await _rpc('list_team');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> signUp({
    String? email,
    String? phone,
    required String password,
  }) async {
    _requireOnline();
    final cleanEmail = (email ?? '').trim();
    final cleanPhone = (phone ?? '').trim();
    await _guard(
      () => Supabase.instance.client.auth.signUp(
        email: cleanEmail.isEmpty ? null : cleanEmail,
        phone: cleanPhone.isEmpty ? null : cleanPhone,
        password: password,
      ),
    );
  }

  Future<void> resetPassword(String email) async {
    _requireOnline();
    await _guard(
      () => Supabase.instance.client.auth.resetPasswordForEmail(email.trim()),
    );
  }

  Future<void> signOut() async {
    _role = 'staff';
    _workspaceId = null;
    _workspaceName = '';
    await LocalStore().clear();
    if (online) await Supabase.instance.client.auth.signOut();
  }
}
