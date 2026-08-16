import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Sends FCM push notifications via the Cloudflare Worker (free).
///
/// The worker proxies requests to Firebase Cloud Messaging's free legacy API
/// using a server key stored as a Worker secret — no Blaze plan needed,
/// no credit card required.
///
/// Call [sendCallPush] after creating a Firestore call doc, and
/// [sendMessagePush] after writing a new message to Firestore.
class PushSender {
  PushSender._();

  static final String _baseUrl = _normaliseUrl(AppConfig.tokenServerUrl);

  /// Strips trailing slash/path so we always call `<worker>/push/call`.
  static String _normaliseUrl(String url) {
    url = url.trim();
    if (url.isEmpty) return '';
    // Strip trailing slash, then strip /rtc-token or any path.
    while (url.endsWith('/')) url = url.substring(0, url.length - 1);
    // If the URL has a path, keep it — the worker handles routing.
    return url;
  }

  /// True when the worker URL is configured (reuses the same token server).
  static bool get isAvailable => _baseUrl.isNotEmpty;

  /// Sends an incoming-call push to [calleeFcmToken].
  ///
  /// Should be called by the **caller** immediately after creating the call
  /// doc in Firestore (so the callee gets a push even if their app is killed).
  static Future<bool> sendCallPush({
    required String calleeFcmToken,
    required String callId,
    required String channelName,
    required String callerId,
    required String callerName,
    required bool isVideo,
  }) async {
    if (!isAvailable) return false;
    return _post('/push/call', {
      'token': calleeFcmToken,
      'callId': callId,
      'channelName': channelName,
      'callerId': callerId,
      'callerName': callerName,
      'isVideo': isVideo,
    });
  }

  /// Sends a new-message push to [recipientFcmToken].
  ///
  /// Should be called by the **sender** immediately after writing the message.
  static Future<bool> sendMessagePush({
    required String recipientFcmToken,
    required String chatId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    if (!isAvailable) return false;
    return _post('/push/message', {
      'token': recipientFcmToken,
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
    });
  }

  static Future<bool> _post(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      // Fail silently — the message/call works without the push.
      return false;
    }
  }
}