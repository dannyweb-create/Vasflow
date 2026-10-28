import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'local_store.dart';

class AuthService {
  bool get online => AppConfig.supabaseReady;

  String _role = 'staff';

  String get currentEmail =>
      online ? (Supabase.instance.client.auth.currentUser?.email ?? '') : '';

  /// Used only to show or hide buttons. Real permissions are enforced by
  /// Supabase Row Level Security on the server, never by this value.
  String get role => _role;

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
    }
  }

  Future<void> signIn(String identifier, String password) async {
    _requireOnline();
    final id = identifier.trim();
    final auth = Supabase.instance.client.auth;
    await _guard(
      () => id.contains('@')
          ? auth.signInWithPassword(email: id, password: password)
          : auth.signInWithPassword(phone: id, password: password),
    );
    await _loadRole();
  }

  /// Reads this user's role from the `profiles` table. Defaults to 'staff'.
  Future<void> _loadRole() async {
    _role = 'staff';
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (row != null && row['role'] == 'admin') _role = 'admin';
    } catch (_) {
      // Keep the safe default ('staff') if the profile cannot be read.
    }
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
    await LocalStore().clear();
    if (online) await Supabase.instance.client.auth.signOut();
  }
}
