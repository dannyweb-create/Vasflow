/// Supabase connection values are supplied at build time with --dart-define
/// (the GitHub Actions workflow does this from repository secrets).
/// Use ONLY the project URL and the public "anon" / "publishable" key here.
/// Never put a service_role key in a Flutter app.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get supabaseReady =>
      supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;
}
