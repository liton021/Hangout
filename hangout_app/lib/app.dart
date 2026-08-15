import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/call_controller.dart';
import 'providers/providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/call/incoming_call_screen.dart';
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
  }

  Future<void> _setupPush() async {
    final push = ref.read(pushServiceProvider);
    await push.requestPermission();
    push.listen();
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
        // Ensure the profile doc exists and keep the FCM token fresh.
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
