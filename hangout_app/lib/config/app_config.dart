/// Central configuration for Hangout.
///
/// ══════════════════════════════════════════════════════════════════════
///  HOW TO CONFIGURE AGORA (App ID + Token / secured mode)
/// ══════════════════════════════════════════════════════════════════════
///  1. https://console.agora.io → Projects → your project → copy App ID.
///     Paste it into [_agoraAppId] below.
///  2. Deploy the token server in `token_server/` (see its README) and
///     paste its URL into [_tokenServerUrl] below.
///  3. Rebuild the app. Calls now use per-channel tokens automatically.
///
///  TESTING-MODE FALLBACK: if your Agora project uses "App ID" (testing)
///  auth instead, just leave [_tokenServerUrl] EMPTY — the app will join
///  channels without a token.
/// ══════════════════════════════════════════════════════════════════════
class AppConfig {
  AppConfig._();

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  PASTE YOUR AGORA APP ID BETWEEN THE QUOTES BELOW  ▼▼▼
  // ────────────────────────────────────────────────────────────────────
  static const String _agoraAppId = 'd69f6bb5d518410e9f3dea44f6967fbb';

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  PASTE YOUR TOKEN SERVER URL BELOW (secured mode only)  ▼▼▼
  //  e.g. 'https://hangout-token-server.yourname.workers.dev'
  //  Leave EMPTY ('') for testing-mode (App ID only) projects.
  // ────────────────────────────────────────────────────────────────────
  static const String _tokenServerUrl = 'https://hangout-token-server.onelitonbd.workers.dev/';

  /// Optional static token (dev only). Normally leave empty — when
  /// [_tokenServerUrl] is set, tokens are fetched per call automatically.
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

  /// Effective static token (see [_agoraToken]).
  static const String agoraToken = String.fromEnvironment(
    'AGORA_TOKEN',
    defaultValue: _agoraToken,
  );

  /// Effective token server URL. `--dart-define=TOKEN_SERVER_URL=...`
  /// overrides the hard-coded value above.
  static const String tokenServerUrl = String.fromEnvironment(
    'TOKEN_SERVER_URL',
    defaultValue: _tokenServerUrl,
  );

  /// True when a token server is configured (secured mode).
  static bool get useTokenServer => tokenServerUrl.isNotEmpty;

  /// True once a real App ID has been configured (either in code or via
  /// --dart-define). Used to show a helpful error instead of a dead call
  /// screen when the ID is still the placeholder.
  static bool get isConfigured =>
      agoraAppId.isNotEmpty &&
      agoraAppId != 'PASTE_YOUR_AGORA_APP_ID_HERE' &&
      agoraAppId != 'YOUR_AGORA_APP_ID';
}
