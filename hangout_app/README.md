# Hangout - Flutter Chat, Audio & Video Call App

A Flutter person-to-person chat, audio call, and video call application built with **Agora.io** for real-time communication and **Firebase** for chat messaging.

## Features

- **User Authentication**: Email/password sign up and sign in via Firebase Auth
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

1. **Flutter SDK** (>= 3.0.0)
2. **Firebase Project** with:
   - Authentication enabled (Email/Password)
   - Firestore Database created
3. **Agora Account** with:
   - App ID
   - Temporary token (for testing)

## Setup Instructions

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd hangout_app
flutter pub get
```

### 2. Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project
3. Add Android and iOS apps to your Firebase project
4. Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
5. Place them in the respective directories:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`
6. Enable **Authentication** > **Email/Password** sign-in method
7. Create a **Firestore Database** in test mode

### 3. Agora Setup

1. Go to [Agora Console](https://console.agora.io/)
2. Create a new project
3. Copy your **App ID**
4. Generate a **Temporary Token** for testing

Update the Agora credentials in `lib/services/call_service.dart`:

```dart
static const String appId = '<YOUR_AGORA_APP_ID>';
static const String tempToken = '<YOUR_AGORA_TEMP_TOKEN>';
```

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
├── main.dart                 # App entry point
├── services/
│   ├── auth_service.dart     # Firebase authentication
│   ├── chat_service.dart     # Firebase Firestore chat
│   └── call_service.dart     # Agora RTC engine wrapper
└── screens/
    ├── home_screen.dart      # Main screen after login
    ├── login_screen.dart     # Login / Sign up screen
    ├── chat_list_screen.dart # List of contacts
    ├── chat_screen.dart      # 1-to-1 chat view
    ├── call/
    │   ├── audio_call_screen.dart
    │   └── video_call_screen.dart
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
