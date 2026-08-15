import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

/// Fetches Agora RTC tokens from the token server (`token_server/` in the
/// repo root — a Cloudflare Worker holding the App Certificate).
///
/// Only used when [AppConfig.useTokenServer] is true (secured mode).
/// In testing mode (no token server configured) calls join token-less.
class TokenService {
  TokenService._();

  /// Fetches a token for [channelName]. Returns the token string.
  ///
  /// [uid] must match the uid used in `joinChannel` (0 = any uid).
  /// [expireSeconds] is the token lifetime (default 1 hour).
  static Future<String> fetchRtcToken(
    String channelName, {
    int uid = 0,
    int expireSeconds = 3600,
  }) async {
    final uri = Uri.parse(AppConfig.tokenServerUrl).replace(
      path: '/rtc-token',
      queryParameters: {
        'channel': channelName,
        'uid': '$uid',
        'expire': '$expireSeconds',
      },
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw HttpException(
          'Token server returned ${response.statusCode}: $body',
          uri: uri,
        );
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        throw const FormatException('Token server response missing "token".');
      }
      return token;
    } finally {
      client.close();
    }
  }
}
