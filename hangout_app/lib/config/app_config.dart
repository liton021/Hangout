/// Central configuration for Hangout.
///
/// ══════════════════════════════════════════════════════════════════════
///  HOW TO CONFIGURE AGORA (voice/video calls)
/// ══════════════════════════════════════════════════════════════════════
///  1. Go to https://console.agora.io  →  Projects  →  your project.
///  2. Copy the "App ID".
///  3. Paste it into [_agoraAppId] below, replacing the placeholder.
///  4. In the Agora console, make sure the project's authentication is set
///     to "App ID" (testing mode / no token) — otherwise you must also
///     supply a token in [_agoraToken].
///  5. Rebuild the app. Done — calls will work.
/// ══════════════════════════════════════════════════════════════════════
class AppConfig {
  AppConfig._();

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  PASTE YOUR AGORA APP ID BETWEEN THE QUOTES BELOW  ▼▼▼
  // ────────────────────────────────────────────────────────────────────
  static const String _agoraAppId = 'PASTE_YOUR_AGORA_APP_ID_HERE';

  /// Optional Agora token.
  ///
  /// Leave EMPTY ('') when the Agora project is in "App ID" (testing) auth
  /// mode. If your project uses "App ID + Token" mode, paste a temp token
  /// here for testing — for production you should run a token server.
  static const String _agoraToken = '';

  // ────────────────────────────────────────────────────────────────────
  //  Nothing below needs editing.
  // ────────────────────────────────────────────────────────────────────

  /// Effective App ID. A `--dart-define=AGORA_APP_ID=...` build flag, if
  /// provided, overrides the hard-coded value above (useful for CI).
  static const String agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: _agoraAppId,
  );

  /// Effective token. A `--dart-define=AGORA_TOKEN=...` build flag, if
  /// provided, overrides the hard-coded value above.
  static const String agoraToken = String.fromEnvironment(
    'AGORA_TOKEN',
    defaultValue: _agoraToken,
  );

  /// True once a real App ID has been configured (either in code or via
  /// --dart-define). Used to show a helpful error instead of a dead call
  /// screen when the ID is still the placeholder.
  static bool get isConfigured =>
      agoraAppId.isNotEmpty &&
      agoraAppId != 'PASTE_YOUR_AGORA_APP_ID_HERE' &&
      agoraAppId != 'YOUR_AGORA_APP_ID';
}
