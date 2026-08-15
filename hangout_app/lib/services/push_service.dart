import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

/// Firebase Cloud Messaging — device token + incoming message stream.
///
/// Used both for message notifications and for in-app call signaling
/// (waking the callee when the app is in the background).
class PushService {
  PushService(this._messaging);

  final FirebaseMessaging _messaging;

  final _dataController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of incoming FCM data payloads (call invites, etc.).
  Stream<Map<String, dynamic>> get onDataMessage => _dataController.stream;

  Future<void> requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<String?> getToken() => _messaging.getToken();

  Stream<String> onTokenRefresh() => _messaging.onTokenRefresh;

  /// Starts listening for foreground messages.
  void listen() {
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data.isNotEmpty) {
        _dataController.add(message.data);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data.isNotEmpty) {
        _dataController.add(message.data);
      }
    });
  }

  void dispose() {
    _dataController.close();
  }
}
