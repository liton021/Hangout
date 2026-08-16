import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'models/app_user.dart';
import 'models/call_data.dart';
import 'models/push_event.dart';
import 'providers/call_controller.dart';
import 'providers/providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/call/audio_call_screen.dart';
import 'screens/call/incoming_call_screen.dart';
import 'screens/call/video_call_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/background_connection.dart';
import 'services/permission_service.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

class HangoutApp extends ConsumerStatefulWidget {
  const HangoutApp({super.key});

  @override
  ConsumerState<HangoutApp> createState() => _HangoutAppState();
}

class _HangoutAppState extends ConsumerState<HangoutApp> {
  final _navKey = GlobalKey<NavigatorState>();
  String? _handledIncomingCallId;

  /// The notification tap that launched a terminated app (handled once
  /// auth has restored). Null when the app was launched normally.
  NotificationAction? _pendingLaunchTap;

  @override
  void initState() {
    super.initState();
    _setupPush();
  }

  /// Initializes FCM-free push: local notifications + the WebSocket to the
  /// Cloudflare Worker, and routes incoming events/taps.
  Future<void> _setupPush() async {
    final push = ref.read(pushServiceProvider);
    await push.init();
    _pendingLaunchTap = push.consumeLaunchTap();

    push.onEvent.listen(_onPushEvent);
    push.onNotificationTap.listen(_onNotificationTap);
  }

  void _onPushEvent(PushEvent event) {
    switch (event.type) {
      case PushEventType.callInvite:
        // Fast path for a ringing call while we're running — the Firestore
        // watch in CallController usually follows a moment later (the UI
        // dedupes by call id).
        ref.read(callControllerProvider.notifier).handleRemoteInvite(event);
      case PushEventType.newMessage:
      case PushEventType.callCancelled:
      case PushEventType.callRejected:
      case PushEventType.unknown:
        break; // Notifications were already raised by PushService.
    }
  }

  void _onNotificationTap(NotificationAction action) {
    _pendingLaunchTap = null;
    _handleTap(action);
  }

  /// Handles a notification tap/action. Runs when the app is live, or right
  /// after auth restores for taps that launched a terminated app.
  Future<void> _handleTap(NotificationAction action) async {
    final payload = action.event.payload;
    final callId = payload['callId'] as String?;

    switch (action.event.type) {
      case PushEventType.callInvite:
        if (action.actionId == 'decline') {
          if (callId != null) {
            await ref
                .read(callControllerProvider.notifier)
                .rejectRemote(callId);
          }
          return;
        }
        if (action.actionId == 'accept' && callId != null) {
          await _joinCallFromNotification(callId, action.event);
          return;
        }
        // Plain body tap: the Firestore watch surfaces the ringing call and
        // the listener below opens IncomingCallScreen automatically.
        break;
      case PushEventType.newMessage:
        _openChatFromNotification(payload);
      case PushEventType.callCancelled:
      case PushEventType.callRejected:
      case PushEventType.unknown:
        break;
    }
  }

  /// Accept flow for the notification's "Accept" action.
  Future<void> _joinCallFromNotification(
    String callId,
    PushEvent event,
  ) async {
    final nav = _navKey.currentState;
    final context = nav?.context;
    final isVideo = event.payload['type'] == 'video';
    if (context != null) {
      final ok = await PermissionService.ensureForCall(context, video: isVideo);
      if (!ok) return;
    }
    final call = await ref
        .read(callControllerProvider.notifier)
        .acceptRemote(callId);
    if (call == null || nav == null) return;
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => call.type == CallType.video
            ? VideoCallScreen(call: call, isCaller: false)
            : AudioCallScreen(call: call, isCaller: false),
      ),
    );
  }

  /// Opens the conversation a message notification points at.
  void _openChatFromNotification(Map<String, dynamic> payload) {
    final chatId = payload['chatId'] as String?;
    final senderId = payload['senderId'] as String?;
    final nav = _navKey.currentState;
    if (chatId == null || senderId == null || nav == null) return;
    final peer = AppUser(
      uid: senderId,
      name: (payload['senderName'] as String?) ?? 'User',
      email: '',
    );
    nav.push(
      MaterialPageRoute(builder: (_) => ChatScreen(peer: peer, chatId: chatId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Once signed in: start call signaling, connect the push WebSocket,
    // keep the background-connection service running, and replay any
    // notification tap that launched the app. On sign-out: tear it all down.
    ref.listen(authStateProvider, (prev, next) async {
      final user = next.value;
      final push = ref.read(pushServiceProvider);
      if (user != null) {
        ref.read(callControllerProvider.notifier).init(user.uid);
        await push.connect(uid: user.uid);
        // Ensure the profile doc exists (device tokens are no longer
        // needed — push is addressed by uid).
        await ref.read(userServiceProvider).upsert(user);
        if (AppConfig.usePushServer) {
          await startBackgroundConnection();
        }
        final tap = _pendingLaunchTap;
        if (tap != null) {
          _pendingLaunchTap = null;
          await _handleTap(tap);
        }
      } else {
        _handledIncomingCallId = null;
        await push.disconnect();
        await stopBackgroundConnection();
      }
    });

    // Show the incoming-call screen whenever a ringing call arrives.
    ref.listen<CallControllerState>(callControllerProvider, (prev, next) {
      final call = next.incomingCall;
      if (call != null && call.id != _handledIncomingCallId) {
        _handledIncomingCallId = call.id;
        _navKey.currentState?.push(
          MaterialPageRoute(builder: (_) => IncomingCallScreen(call: call)),
        );
      } else if (call == null) {
        _handledIncomingCallId = null;
      }
    });

    return MaterialApp(
      navigatorKey: _navKey,
      debugShowCheckedModeBanner: false,
      title: 'Hangout',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: auth.when(
        loading: () => const SplashScreen(),
        error: (_, __) => const SplashScreen(),
        data: (user) => user == null ? const LoginScreen() : const HomeScreen(),
      ),
    );
  }
}
