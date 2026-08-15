import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background/terminated message handling. For a full incoming-call
  // experience (ring while the app is killed) add a full-screen-intent
  // notification here — see README ("Background incoming calls").
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android-only: Firebase reads its config from android/app/google-services.json,
  // so no firebase_options.dart is required. Add that file (see README) before building.
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const ProviderScope(child: HangoutApp()));
}
