import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/background_connection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android-only: Firebase reads its config from android/app/google-services.json,
  // so no firebase_options.dart is required. Add that file (see README) before building.
  //
  // Push is FCM-free: no firebase_messaging here. Notifications ride a
  // WebSocket to the Cloudflare Worker (see services/push_service.dart),
  // kept alive by a foreground service (services/background_connection.dart).
  await Firebase.initializeApp();

  initBackgroundConnection();

  runApp(const ProviderScope(child: HangoutApp()));
}
