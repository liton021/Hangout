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
  static const String _tokenServerUrl = 'https://hangout-token-server.onelitonbd.workers.dev';

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

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  PUSH / SIGNALING SERVER (FCM-free notifications)  ▼▼▼
  //  Same Cloudflare Worker as the token server. The app keeps a
  //  WebSocket open to it and receives message/call events; it raises
  //  local notifications itself. See `docs/PUSH_NOTIFICATIONS.md`.
  // ────────────────────────────────────────────────────────────────────
  static const String _pushServerUrl =
      'https://hangout-token-server.onelitonbd.workers.dev';

  /// Effective push server URL. `--dart-define=PUSH_SERVER_URL=...`
  /// overrides the hard-coded value above.
  static const String pushServerUrl = String.fromEnvironment(
    'PUSH_SERVER_URL',
    defaultValue: _pushServerUrl,
  );

  /// True when a push/signaling server is configured.
  static bool get usePushServer => pushServerUrl.isNotEmpty;

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  AVATAR / PROFILE PICTURE HOSTING  ▼▼▼
  //  Same Cloudflare Worker again: it exposes POST/DELETE /avatar and
  //  serves the images back publicly from /avatar/<uid>/<hash>.<ext>.
  //  Storage is Workers KV by default (no credit card) and switches to
  //  R2 automatically if you bind a bucket. See token_server/README.md.
  // ────────────────────────────────────────────────────────────────────
  static const String _avatarServerUrl =
      'https://hangout-token-server.onelitonbd.workers.dev';

  /// Effective avatar server URL. `--dart-define=AVATAR_SERVER_URL=...`
  /// overrides the hard-coded value above.
  static const String avatarServerUrl = String.fromEnvironment(
    'AVATAR_SERVER_URL',
    defaultValue: _avatarServerUrl,
  );

  /// True when profile-picture uploads are available.
  static bool get useAvatarServer => avatarServerUrl.isNotEmpty;

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  VOICE NOTE HOSTING  ▼▼▼
  //  The same Cloudflare Worker and the same KV namespace / R2 bucket as
  //  avatars — voice notes just live under a different key prefix and
  //  expire automatically after 30 days, which is what keeps the
  //  card-free 1 GB KV tier viable. See token_server/README.md.
  // ────────────────────────────────────────────────────────────────────
  static const String _voiceServerUrl =
      'https://hangout-token-server.onelitonbd.workers.dev';

  /// Effective voice server URL. `--dart-define=VOICE_SERVER_URL=...`
  /// overrides the hard-coded value above.
  static const String voiceServerUrl = String.fromEnvironment(
    'VOICE_SERVER_URL',
    defaultValue: _voiceServerUrl,
  );

  /// True when voice messages are available. When false the composer falls
  /// back to text only — no dead mic button.
  static bool get useVoiceServer => voiceServerUrl.isNotEmpty;

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  CHAT PHOTO HOSTING  ▼▼▼
  //  Same Cloudflare Worker and KV namespace again. Photos are stored like
  //  voice notes and also expire automatically — after 10 days — while
  //  profile pictures never expire. See token_server/README.md.
  // ────────────────────────────────────────────────────────────────────
  static const String _imageServerUrl =
      'https://hangout-token-server.onelitonbd.workers.dev';

  /// Effective image server URL. `--dart-define=IMAGE_SERVER_URL=...`
  /// overrides the hard-coded value above.
  static const String imageServerUrl = String.fromEnvironment(
    'IMAGE_SERVER_URL',
    defaultValue: _imageServerUrl,
  );

  /// True when chat photos are available (hides the gallery button when
  /// the server is not configured).
  static bool get useImageServer => imageServerUrl.isNotEmpty;

  /// True when a token server is configured (secured mode).
  static bool get useTokenServer => tokenServerUrl.isNotEmpty;

  /// True once a real App ID has been configured (either in code or via
  /// --dart-define). Used to show a helpful error instead of a dead call
  /// screen when the ID is still the placeholder.
  static bool get isConfigured =>
      agoraAppId.isNotEmpty &&
      agoraAppId != 'PASTE_YOUR_AGORA_APP_ID_HERE' &&
      agoraAppId != 'YOUR_AGORA_APP_ID';

  // ────────────────────────────────────────────────────────────────────
  //  ▼▼▼  AUTO-UPDATE (GitHub Releases — no Cloudflare needed)  ▼▼▼
  //  On launch the app checks the latest GitHub release; when its tag is
  //  newer than [appVersion] it offers to download & install the APK.
  //
  //  HOW TO SHIP AN UPDATE:
  //   1. Bump [appVersion] below to the new version (e.g. '1.0.1').
  //   2. Commit & push (CI builds the APK for the release).
  //   3. Create a tag named  v<appVersion>  (e.g. `v1.0.1`) on GitHub —
  //      the release workflow builds a universal APK and attaches it.
  //   4. Users who open the app see the update prompt automatically.
  // ────────────────────────────────────────────────────────────────────

  /// Installed app version. Must match the version tag of the *previous*
  /// release until you bump it for the next one.
  static const String appVersion = '1.0.0';

  /// GitHub repository hosting the release APKs ('owner/name').
  static const String githubRepo = 'liton021/Hangout';

  /// Master switch for the in-app updater.
  static bool get useAutoUpdate => githubRepo.isNotEmpty;
}
