/// Central configuration.
///
/// Secrets are injected at build time via `--dart-define` so they never live
/// in source control:
///
///   flutter run --dart-define=AGORA_APP_ID=YOUR_ID
///   flutter run --dart-define=AGORA_TOKEN=          (optional, dev only)
///
/// If you prefer, you can also hard-code the Agora App ID below for quick
/// local testing (not recommended for production).
class AppConfig {
  AppConfig._();

  /// Agora App ID from https://console.agora.io
  static const String agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: 'YOUR_AGORA_APP_ID',
  );

  /// Optional token. For development you can leave this empty and enable
  /// "App ID" (no-token) authentication in the Agora console. For production
  /// you must run a token server.
  static const String agoraToken = String.fromEnvironment(
    'AGORA_TOKEN',
    defaultValue: '',
  );

  static bool get isConfigured => agoraAppId != 'YOUR_AGORA_APP_ID';
}
