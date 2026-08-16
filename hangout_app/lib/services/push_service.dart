import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Firebase Cloud Messaging — device token + incoming message stream.
///
/// Used both for message notifications and for in-app call signaling
/// (waking the callee when the app is in the background).
class PushService {
  PushService(this._messaging, this._db, this._auth);

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  final _dataController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of incoming FCM data payloads (call invites, etc.).
  Stream<Map<String, dynamic>> get onDataMessage => _dataController.stream;

  Future<void> requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );
  }

  Future<String?> getToken() => _messaging.getToken();

  Stream<String> onTokenRefresh() => _messaging.onTokenRefresh;

  /// Call this on app start (already done in app.dart).
  void listen() {
    // ── Foreground messages ──────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data.isEmpty) return;

      // Forward raw data to any in-app listeners.
      _dataController.add(data);

      final type = data['type'];

      if (type == 'incoming_call') {
        // App is in the foreground — show the native call UI directly.
        _showIncomingCallNotification(data);
      } else if (type == 'message') {
        // App is in the foreground — show a local notification.
        _showForegroundMessageNotification(data);
      }
    });

    // ── App opened by tapping a notification ─────────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data.isNotEmpty) {
        _dataController.add(message.data);
      }
    });

    // ── Token refresh — keep Firestore in sync ──────────────────────
    _messaging.onTokenRefresh.listen(_storeToken);
  }

  /// Stores (or updates) the FCM token on the current user's Firestore doc.
  Future<void> _storeToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).set(
        {'fcmToken': token},
        SetOptions(merge: true),
      );
    } catch (_) {
      // Fail silently — the token will be retried on next refresh.
    }
  }

  /// Shows a local notification for a new message when the app is in the
  /// foreground.
  Future<void> _showForegroundMessageNotification(
      Map<String, dynamic> data) async {
    final plugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await plugin.initialize(
      const InitialiationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    final sender = data['snderName'] ?? 'Someone';
    final body = data['text'] ?? '';

    await plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      sender,
      body,
      const NtificationDetails(
        android: AndroidNotificationDetails(
          'hangout_mesages',
          'Hangout Messages',
          channelEscription: 'New chat messages',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Shows the native incoming-call screen when the app is in the foreground.
  Future<void> _showIncomingCallNotification(Map<String, dynamic> data) async {
    await FlutterCalKitIncoming.showCalKitIncoming(
      CalKitParams(
        id: data['callId'] ?? '',
        nameCaller: data['callerName'] ?? 'Caller'],
        appName: 'Hangout',
        handle: data['callerId'] ?? '',
        type: data['isVideo'] == 'true'
            ? CalType.video
            : CalType.audio,
        textAccept: 'Accept',
        textDecline: 'Decline',
        ringtonePath: 'system_ringtone_default',
        extra: <String, dynamic>{
          'channelName': data['channelName'] ?? '',
          'callId': data['callId'] ?? '',
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: true,
          backgroundColor: '#0955fa',
          textColor: '#ffffff',
          textAccept: 'Accept',
          textDecline: 'Decline',
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
        ),
      ),
    );
  }

  void dispose() {
    _dataController.close();
  }
}