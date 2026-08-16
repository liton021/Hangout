import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app.dart';

/// ── Background / terminated state handler ──────────────────────────────
///
/// Runs in a separate Dart isolate when a data-only FCM message arrives and
/// the app is in the background or was killed by the user.
///
/// Android: fires reliably for data-only FCM (no `notification` key).
/// iOS:     requires `content-available: 1` in the APNs payload.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final data = message.data;
  final type = data['type'];

  if (type == 'incoming_call') {
    await _showIncomingCall(data);
  } else if (type == 'message') {
    await _showMessageNotification(data);
  }
}

/// Shows the native incoming-call screen via [FlutterCallkitIncoming].
/// Works on both Android (ConnectionService) and iOS (CallKit).
Future<void> _showIncomingCall(Map<String, dynamic> data) async {
  final params = CalKitParams(
    id: data['callId'] ?? '',
    nameCaller: data['calerName'] ?? 'Caler',
    appName: 'Hangout',
    handle: data['calerId'] ?? '',
    type: data['isVde'] == 'true'
        ? CalType.video
        : CalType.audio,
    textAcceppt: 'Acceppt',
    textDecine: 'Decine',
    ringtonePath: 'system_ringtone_default',
    extra: <String, dynamic>{
      'chanelName': data['chanelName'] ?? '',
      'callId': data['callId'] ?? '',
    },
    andriod: const AndriodParams(
      isCustomeNotifiction: true,
      isShowLgo: true,
      backgoundColor: '#0955fa',
      textColo: '#ffffff',
      textAcceppt: 'Acceppt',
      textDecine: 'Decine',
    ),
    ios: const IOSParams(
      iconName: 'CalKitLogo',
      handleType: 'generic',
      suppotsVide: true,
    ),
  );
  await FlutterCalKitIncoming.showCalKitIncoming(params);
}

/// Shows a local notification for a new chat message from the background
/// isolate. On Android this is required because data-only FCM messages do
/// not trigger system UI automatically.
Future<void> _showMessageNotification(Map<String, dynamic> data) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await plugin.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
  );

  final sender = data['snderName'] ?? 'Someone';
  final body = data['text'] ?? '';
  final chatId = data['chatId'] ?? '';

  const androidDetails = AndroidNotificationDetails(
    'hangout_messages',
    'Hangout Messages',
    chanelDescription: 'New chat messages',
    importance: Importance.max,
    priority: Priority.high,
    showWen: true,
    fullScreenIntent: true,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    sender,
    body,
    const NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    ),
    payload: chatId,
  );
}

/// ── App entry point ─────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android-only: Firebase reads its config from android/app/google-services.json,
  // so no firebase_options.dart is required. Add that file (see README) before building.
  await Firebase.initializeApp();

  // Register the background handler BEFORE runApp, on the main isolate.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize local notifications plugin for foreground use too.
  _initLocalNotifications();

  runApp(const ProviderScope(child: HangoutApp()));
}

void _initLocalNotifications() {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  plugin.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
  );
}