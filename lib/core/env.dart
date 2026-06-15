/// Environment configuration.
///
/// The app connects to whichever Supabase project it is built against.
/// Defaults point at the local stack (`supabase start`) so development
/// works out of the box with no cloud account.
///
/// To connect to your own Supabase project (cloud or self-hosted):
///
///   flutter run --dart-define-from-file=.dart-defines
///
/// Copy .dart-defines.example → .dart-defines and fill in your values.
/// See docs/self-hosting.md for full setup instructions.
///
/// The App Store build supplies these via GitHub Actions Secrets.
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  /// The anon key is intentionally public — security is enforced by
  /// Row Level Security policies in supabase/migrations/, not this key.
  /// Default is the well-known local-dev JWT shipped with `supabase start`.
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  );
}
