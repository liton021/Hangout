# Hangout - Flutter Chat, Audio & Video Call App

A Flutter person-to-person chat, audio call, and video call application built with **Agora.io** for real-time communication and **Firebase** for authentication and messaging.

## Features

- **User Authentication**: Email/password sign up and sign in via Firebase Auth
- **Contacts**: Every signed-up user appears in everyone else's contact list (stored in Firestore)
- **Real-time Chat**: Person-to-person messaging using Firebase Firestore
- **Audio Calls**: 1-to-1 audio calling via Agora RTC SDK
- **Video Calls**: 1-to-1 video calling via Agora RTC SDK
- **Cross-platform**: Works on Android and iOS

## Tech Stack

| Feature | Technology |
|---------|-----------|
| UI Framework | Flutter |
| Real-time Calls | Agora RTC Engine (`agora_rtc_engine`) |
| Chat / Auth | Firebase (Firestore + Auth) |
| State Management | Provider |

## Prerequisites

1. **Flutter SDK** (>= 3.24 recommended)
2. **Firebase Project** with:
   - Authentication enabled (Email/Password)
   - Firestore Database created (test mode is fine for development)
3. **Agora Account** with an App ID (the App Certificate can stay disabled for local testing)

## Setup Instructions

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd hangout_app
flutter pub get
```

### 2. Firebase Setup

The Firebase credentials are **not committed** to this repository. If you run
the app without them, it shows a setup screen explaining what is missing
instead of crashing.

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Create a new project
3. Add an Android app (package: `com.example.hangout_app`) and an iOS app to it
4. Download the config files:
   - Android: `google-services.json` → place in `android/app/`
   - iOS: `GoogleService-Info.plist` → place in `ios/Runner/`
5. Re-enable the Google Services Gradle plugin:
   - In `android/app/build.gradle`, uncomment
     `id "com.google.gms.google-services"`
   - In `android/build.gradle`, uncomment
     `id "com.google.gms.google-services" version "4.3.15" apply false`
6. Enable **Authentication** > **Email/Password** sign-in method
7. Create a **Firestore Database** (test mode is fine for development)

> The contact list is built from the `users` collection: each account that
> signs up is automatically published there, so use two devices (or two
> accounts) to see each other.

### 3. Agora Setup

1. Go to the [Agora Console](https://console.agora.io/)
2. Create a new project
3. Copy your **App ID** into `lib/services/call_service.dart`:

```dart
static const String appId = '<YOUR_AGORA_APP_ID>';
```

4. **Tokens**: by default the project keeps the Agora *App Certificate
   disabled*, so the empty token in `call_service.dart` works for local
   testing. If you enable the App Certificate you **must** serve tokens from
   your own backend and pass them into `joinChannel` — temporary tokens from
   the console expire within 24h and must never be hardcoded.

### 4. Run the App

```bash
# For Android
flutter run

# For iOS
flutter run -d ios
```

## Project Structure

```
lib/
├── main.dart                       # App entry point
├── services/
│   ├── auth_service.dart           # Firebase authentication + user profiles
│   ├── chat_service.dart           # Firestore chat + contact list
│   └── call_service.dart           # Agora RTC engine wrapper
└── screens/
    ├── home_screen.dart            # Main screen after login
    ├── login_screen.dart           # Login / Sign up screen
    ├── chat_list_screen.dart       # List of contacts
    ├── chat_screen.dart            # 1-to-1 chat view
    ├── firebase_setup_screen.dart  # Shown when Firebase isn't configured
    └── call/
        ├── audio_call_screen.dart
        └── video_call_screen.dart
```

## Agora Free Tier

Agora offers a free tier of **10,000 Standard minutes per month**. Pricing:

- Audio: ~$0.99 per 1,000 minutes
- Video (720p): ~$3.99 per 1,000 user-minutes
- Video (1080p): ~$8.99 per 1,000 user-minutes

> Note: Since August 2025, new Agora accounts use prepaid packages instead of raw per-minute billing.

## TODO / Roadmap

- [ ] Add push notifications for new messages
- [ ] Implement online/offline status
- [ ] Add profile pictures
- [ ] Add call history
- [ ] Implement group calls
- [ ] Add screen sharing
- [ ] Add end-to-end encryption

## License

MIT
