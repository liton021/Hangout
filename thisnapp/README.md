# thisnapp

A free Flutter app for chat, audio calls, and video calls with noise filtering.

## Features

- User authentication (email/password)
- One-on-one text chat
- Audio calling with noise suppression
- Video calling with noise suppression
- Real-time messaging using Firebase Firestore
- WebRTC peer-to-peer calling

## Prerequisites

- Flutter SDK (>=3.0.0 <4.0.0)
- Android Studio
- Firebase project

## Setup Instructions

### 1. Clone or create the project

```bash
flutter create thisnapp
cd thisnapp
```

### 2. Add dependencies

Update `pubspec.yaml` with the dependencies listed in this project.

```bash
flutter pub get
```

### 3. Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project
3. Add Android app:
   - Package name: `com.thisnapp`
   - Download `google-services.json`
   - Place it in `android/app/`
4. Enable Firestore Database in Firebase Console
5. Enable Authentication (Email/Password) in Firebase Console
6. Create Firestore rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    match /chats/{chatId}/messages/{messageId} {
      allow read, write: if request.auth != null;
    }
    match /calls/{callId} {
      allow read, write: if request.auth != null;
      match /iceCandidates/{candidateId} {
        allow read, write: if request.auth != null;
      }
    }
  }
}
```

### 4. Android Setup

Add to `android/build.gradle`:

```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.0'
}
```

Add to `android/app/build.gradle`:

```gradle
apply plugin: 'com.google.gms.google-services'
```

Add permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

### 5. Run the app

```bash
flutter run
```

## Project Structure

```
lib/
  main.dart                  # App entry point
  models/
    user_model.dart          # User data model
    chat_message.dart        # Chat message model
    call_model.dart          # Call data model
  services/
    auth_service.dart        # Firebase authentication
    firebase_service.dart    # Firestore operations for chat & calls
    webrtc_service.dart      # WebRTC calling with noise filtering
  screens/
    login_screen.dart        # Login / Sign up
    home_screen.dart         # Chat list & user list
    chat_screen.dart         # Chat messaging
    call_screen.dart         # Audio / Video call UI
```

## Noise Filtering

The app uses WebRTC's built-in audio processing capabilities for noise filtering:

- Echo cancellation
- Noise suppression
- Auto gain control
- High-pass filter

Configured in `WebRTCService.createLocalStream()`:

```dart
Map<String, dynamic> constraints = {
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
    'highpassFilter': true,
    'googEchoCancellation': true,
    'googNoiseSuppression': true,
    'googAutoGainControl': true,
    'googHighpassFilter': true,
  },
  'video': enableVideo ? {...} : false,
};
```

## License

MIT
