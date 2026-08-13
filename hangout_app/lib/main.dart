import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'screens/firebase_setup_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/call_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase credentials are deliberately not committed to this repo, so
  // initialization fails on a fresh clone until they are added. Show a
  // helpful setup screen instead of crashing with an opaque error.
  String? firebaseSetupError;
  try {
    await Firebase.initializeApp();
  } catch (e) {
    firebaseSetupError = e.toString();
  }

  runApp(HangoutApp(firebaseSetupError: firebaseSetupError));
}

class HangoutApp extends StatelessWidget {
  const HangoutApp({super.key, this.firebaseSetupError});

  final String? firebaseSetupError;

  @override
  Widget build(BuildContext context) {
    // The services talk to Firebase, so they can only be created once
    // Firebase is initialized.
    final providers = firebaseSetupError == null
        ? <SingleChildWidget>[
            ChangeNotifierProvider(create: (_) => AuthService()),
            ChangeNotifierProvider(create: (_) => ChatService()),
            ChangeNotifierProvider(create: (_) => CallService()),
          ]
        : <SingleChildWidget>[];

    return MultiProvider(
      providers: providers,
      child: MaterialApp(
        title: 'Hangout',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: firebaseSetupError != null
            ? FirebaseSetupScreen(error: firebaseSetupError!)
            : const HomeScreen(),
      ),
    );
  }
}
