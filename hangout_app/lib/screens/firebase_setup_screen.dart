import 'package:flutter/material.dart';

/// Shown when Firebase could not be initialized, instead of crashing with an
/// opaque error. Guides the developer through the missing configuration.
class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Firebase is not configured',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const Text(
                'This app needs a Firebase project for authentication and '
                'chat. The Firebase credentials are not committed to this '
                'repository, so you need to add your own (see README.md):\n\n'
                '1. Create a project at console.firebase.google.com\n'
                '2. Enable Authentication > Email/Password\n'
                '3. Create a Firestore database (start in test mode)\n'
                '4. Android: add android/app/google-services.json and '
                're-enable the google-services plugin (see '
                'android/app/build.gradle)\n'
                '5. iOS: add ios/Runner/GoogleService-Info.plist',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 24),
              Text(
                'Details: $error',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
