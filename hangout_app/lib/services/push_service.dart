import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/io.dart';

import '../config/app_config.dart';
import '../models/push_event.dart';

/// A notification the user tapped (from the tray or a full-screen call
/// alert). [actionId] is `accept` / `decline` for call actions, or empty
/// when the notification body itself was tapped.
class NotificationAction {
  final String actionId;
  final PushEvent event;

  const NotificationAction({required this.actionId, required this.event});
}

/// Hangout push notifications — **without Firebase / FCM**.
///
/// How it works:
///  * The app keeps a persistent WebSocket open to the Cloudflare Worker in
///    `token_server/` (`/ws?uid=<uid>`, authenticated with the Firebase ID
///    token). A foreground service keeps the connection alive while the app
///    is in the background.
///  * When someone sends you a message or calls you, their app POSTs the
///    event to the Worker's `/send` endpoint and the Worker forwards it to
///    your device over the WebSocket.
///  * This service raises a **local** notification: a heads-up for
///    messages, a full-screen-intent ringing notification (Accept/Decline)
///    for calls. When the app is in the foreground, no notification is
///    shown — the UI already updates live via Firestore.
///
/// This is the same approach Telegram/WhatsApp-style persistent connections
/// use, and it costs $0 on Cloudflare's free Workers plan.
class PushService with WidgetsBindingObserver {
  PushService({required this.idTokenProvider});

  /// Supplies a fresh Firebase ID token for the Worker's auth check.
  final Future<String?> Function() idTokenProvider;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final _eventsController = StreamController<PushEvent>.broadcast();
  final _tapsController = StreamController<NotificationAction>.broadcast();

  /// Stream of events received over the WebSocket (call invites, messages).
  Stream<PushEvent> get onEvent => _eventsController.stream;

  /// Stream of notification taps/actions (fired both while running and for
  /// the tap that launched a terminated app — see [consumeLaunchTap]).
  Stream<NotificationAction> get onNotificationTap => _tapsController.stream;

  // ── Connection state ────────────────────────────────────────────────
  IOWebSocketChannel? _channel;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  String? _uid;
  bool _disposed = false;
  bool _foreground = true;
  int _attempt = 0;
  DateTime _lastData = DateTime.now();

  // ── Notification tap state ──────────────────────────────────────────
  NotificationAction? _launchTap;

  // ── Notification channels / ids ─────────────────────────────────────
  static const _callChannel = AndroidNotificationChannel(
    'hangout_calls',
    'Incoming calls',
    description: 'Full-screen alerts for incoming Hangout calls',
    importance: Importance.max,
  );
  static const _messageChannel = AndroidNotificationChannel(
    'hangout_messages',
    'Messages',
    description: 'New Hangout messages',
    importance: Importance.high,
  );

  int _callNotificationId(PushEvent e) =>
      0x40000000 | ((e.payload['callId']?.hashCode ?? 0) & 0x0fffffff);
  int _messageNotificationId(PushEvent e) =>
      0x20000000 | ((e.payload['chatId']?.hashCode ?? 0) & 0x0fffffff);

  /// Initializes local notifications and requests permission.
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);

    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_callChannel);
    await android?.createNotificationChannel(_messageChannel);
    await android?.requestNotificationsPermission();

    // If the app was launched by tapping a notification, capture it now so
    // the app can act on it once it's ready (e.g. after auth restores).
    final launch = await _notifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchTap = _actionFromResponse(launch?.notificationResponse);
    }
  }

  /// Returns (and clears) the notification tap that launched the app, if any.
  NotificationAction? consumeLaunchTap() {
    final tap = _launchTap;
    _launchTap = null;
    return tap;
  }

  /// Connects the device mailbox for [uid] and keeps reconnecting forever.
  Future<void> connect({required String uid}) async {
    _uid = uid;
    _attempt = 0;
    await _open();
  }

  /// Closes the connection (e.g. on sign-out).
  Future<void> disconnect() async {
    _uid = null;
    _attempt = 0;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> _open() async {
    if (_disposed || !AppConfig.usePushServer) return;
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

    final token = await idTokenProvider();
    if (token == null || token.isEmpty) {
      _scheduleReconnect();
      return;
    }

    try {
      final uri = Uri.parse(AppConfig.pushServerUrl).replace(
        path: '/ws',
        queryParameters: {'uid': uid},
      );
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 15),
      );
      _channel = channel;
      _lastData = DateTime.now();
      _attempt = 0;
      _startHeartbeat();

      channel.stream.listen(
        (raw) {
          _lastData = DateTime.now();
          _handleServerMessage(raw);
        },
        onDone: () {
          if (_channel != channel) return;
          _channel = null;
          _scheduleReconnect();
        },
        onError: (Object _) {
          if (_channel != channel) return;
          _channel = null;
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _channel = null;
      _scheduleReconnect();
    }
  }

  /// App-level heartbeat + stale-connection watchdog.
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _lastData = DateTime.now();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (DateTime.now().difference(_lastData) >
          const Duration(seconds: 75)) {
        // Nothing heard for a while — force a reconnect.
        try {
          _channel?.sink.close();
        } catch (_) {}
        return;
      }
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer?.isActive == true) return;
    final seconds = min(60, pow(2, min(_attempt, 6)).toInt());
    _attempt += 1;
    _reconnectTimer = Timer(Duration(seconds: seconds), _open);
  }

  void _handleServerMessage(dynamic raw) {
    if (raw is! String || raw.isEmpty) return;
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      json = decoded;
    } catch (_) {
      return;
    }
    if (json['type'] == 'hello') return; // server ack — nothing to do
    final event = PushEvent.fromServer(json);
    if (event.type == PushEventType.unknown) return;
    _onEvent(event);
  }

  void _onEvent(PushEvent event) {
    _eventsController.add(event);

    // While the app is visible, Firestore already updates the UI live —
    // no system notification needed (and it would be noisy).
    if (_foreground) return;

    switch (event.type) {
      case PushEventType.newMessage:
        _showMessageNotification(event);
      case PushEventType.callInvite:
        _showCallNotification(event);
      case PushEventType.callCancelled:
      case PushEventType.callRejected:
        // Caller cancelled / callee rejected — dismiss the ringing alert.
        _notifications.cancel(_callNotificationId(event));
      case PushEventType.unknown:
        break;
    }
  }

  Future<void> _showMessageNotification(PushEvent event) async {
    final senderName = (event.payload['senderName'] as String?) ?? 'New message';
    final text = (event.payload['text'] as String?) ?? '';
    await _notifications.show(
      _messageNotificationId(event),
      senderName,
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _messageChannel.id,
          _messageChannel.name,
          channelDescription: _messageChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(event.toJson()),
    );
  }

  Future<void> _showCallNotification(PushEvent event) async {
    final callerName = (event.payload['callerName'] as String?) ?? 'Hangout';
    final isVideo = event.payload['type'] == 'video';
    await _notifications.show(
      _callNotificationId(event),
      callerName,
      'Incoming ${isVideo ? 'video' : 'audio'} call…',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _callChannel.id,
          _callChannel.name,
          channelDescription: _callChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          autoCancel: true,
          actions: const [
            AndroidNotificationAction(
              'accept',
              'Accept',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'decline',
              'Decline',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: jsonEncode(event.toJson()),
    );
  }

  NotificationAction? _actionFromResponse(NotificationResponse? response) {
    if (response == null || response.payload == null) return null;
    PushEvent event;
    try {
      event = PushEvent.fromServer(
        Map<String, dynamic>.from(jsonDecode(response.payload!)),
      );
    } catch (_) {
      return null;
    }
    return NotificationAction(
      actionId: response.actionId ?? '',
      event: event,
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    final action = _actionFromResponse(response);
    if (action == null) return;
    _tapsController.add(action);
    _notifications.cancel(response.id ?? 0);
  }

  /// Sends an event to another user through the push server.
  /// Returns true when the server accepted it (best effort — never throws).
  Future<bool> send({
    required String toUid,
    required PushEventType type,
    required Map<String, dynamic> payload,
  }) async {
    if (!AppConfig.usePushServer) return false;
    final token = await idTokenProvider();
    if (token == null || token.isEmpty) return false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse(AppConfig.pushServerUrl).replace(path: '/send'),
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode({
        'to': toUid,
        'event': type.serverName,
        'payload': payload,
      }));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Called by Flutter when the app goes to/from the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    _channel?.sink.close();
    _eventsController.close();
    _tapsController.close();
  }
}
