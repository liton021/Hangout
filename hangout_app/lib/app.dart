import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/call_data.dart';
import 'providers/call_controller.dart';
import 'providers/providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/call/audio_call_screen.dart';
import 'screens/call/incoming_call_screen.dart';
import 'screens/call/video_call_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

class HangoutApp extends ConsumerStatefulWidget {
  const HangoutApp({super.key});

  @override
  ConsumerState<HangoutApp> createState() => _HangoutAppState();
}

class _HangoutAppState extends ConsumerState<HangoutApp> {
  final _navKey = GlobalKey<NavigatorState>();
  String? _handledIncomingCallId;

  @override
  void initState() {
    super.initState();
    _setupPush();
    _listenCallKitEvents();
  }

  Future<void> _setupPush() async {
    final push = ref.read(pushServiceProvider);
    await push.requestPermission();
    push.listen();

    // Store the current FCM token on startup.
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      final token = await push.getToken();
      if (token != null) {
        await ref.read(userServiceProvider).updateFcmToken(user.uid, token);
      }
    }
  }

  /// Listens for CallKit / ConnectionService events (accept, decline, end)
  /// triggered from the native incoming call UI.
  void _listenCallKitEvents() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (!mounted) return;

      switch (event.event) {
        case Event.actionCallAccept:
          await _onCallAccepted(event.body);
          break;
        case Event.actionCallDecline:
          await _onCallDeclined(event.body);
          break;
        default:
          break;
      }
    });
  }

  Future<void> _onCallAccepted(Map<String, dynamic>? body) async {
    final extra = body?['extra'] as Map<String, dynamic>?;
    final channelName = extra?['channelName'] as String?;
    final callId = extra?['callId'] as String?;
    if (callId == null || channelName == null) return;

    // Fetch the call data from Firestore.
    final doc = await ref
        .read(firestoreProvider)
        .collection('calls')
        .doc(callId)
        .get();
    if (!doc.exists) return;

    final call = CallData.fromSnapshot(doc);
    final updated = call.copyWith(status: CallStatus.ongoing);

    // Update Firestore status to ongoing.
    await ref
        .read(firestoreProvider)
        .collection('calls')
        .doc(callId)
        .set({'status': CallStatus.ongoing.name}, SetOptions(merge: true));

    // Navigate to the call screen.
    if (mounted) {
      _navKey.currentState?.pushReplacement(
        MaterialPageRoute(
          builder: (_) => call.type == CallType.video
              ? VideoCallScreen(call: updated, isCaller: false)
              : AudioCallScreen(call: updated, isCaller: false),
        ),
      );
    }
  }

  Future<void> _onCallDeclined(Map<String, dynamic>? body) async {
    final extra = body?['extra'] as Map<String, dynamic>?;
    final callId = extra?['callId'] as String?;
    if (callId == null) return;

    await ref
        .read(firestoreProvider)
        .collection('calls')
        .doc(callId)
        .set({'status': CallStatus.rejected.name}, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Once signed in, start call signaling + register the device token.
    ref.listen(authStateProvider, (prev, next) async {
      final user = next.value;
      if (user != null) {
        ref.read(callControllerProvider.notifier).init(user.uid);
        final push = ref.read(pushServiceProvider);
        final token = await push.getToken();
        await ref.read(userServiceProvider).upsert(user, fcmToken: token);
      } else {
        _handledIncomingCallId = null;
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