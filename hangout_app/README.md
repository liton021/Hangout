# Hangout 📱

A modern **Android** messaging + voice/video calling app built with **Flutter**,
featuring:

- 💬 1-on-1 real-time messaging (Firestore)
- 📞 Audio & video calls (Agora RTC)
- 🎙️ **AI noise suppression** (Agora AINS — removes 100+ noise types)
- ✨ **Video filters** — beauty/skin smoothing, background blur, camera flip
- 🎨 Modern Material 3 UI (light + dark), Riverpod state management

Stack (see `../RESEARCH_REPORT.md` and `../AGORA_AND_CHAT_DECISION.md`):

| Layer | Technology |
|---|---|
| Calls + noise filtering + filters | **Agora** `agora_rtc_engine` |
| Auth | Firebase Auth |
| Chat + call signaling | Cloud Firestore |
| Push | Firebase Cloud Messaging |
| State | flutter_riverpod |

---

## Prerequisites

- Flutter SDK (stable) — `flutter doctor` should pass for Android
- Android Studio + a device/emulator (min SDK 24)
- A [Firebase](https://console.firebase.google.com) project
- An [Agora](https://console.agora.io) project

## 1. Configure Firebase (required)

1. Create a Firebase project and add an **Android app** with package name
   **`com.example.hangout`**.
2. Download **`google-services.json`** and place it at:

   ```
   android/app/google-services.json
   ```

3. In Firebase Console enable **Authentication → Email/Password** and
   **Cloud Firestore** (start in test mode for development).

> The app calls `Firebase.initializeApp()` (Android reads config from
> `google-services.json`), so no `firebase_options.dart` is needed for Android.

## 2. Configure Agora (required)

1. Create a project at [console.agora.io](https://console.agora.io), copy the
   **App ID**.
2. For **development**, in **Project → Authentication**, enable
   "App ID + App Certificate" and use *App ID only* (no token) — the app
   already passes an empty token. For production, run an Agora token server and
   pass the token via `--dart-define=AGORA_TOKEN=...`.
3. In **Project → Extensions**, activate **AI Noise Suppression** so the
   `setAINSMode` call takes effect (the app falls back gracefully if it's off).

## 3. Run

```bash
flutter pub get

# pass your Agora App ID at build/run time:
flutter run --dart-define=AGORA_APP_ID=YOUR_AGORA_APP_ID
```

Build a release APK:

```bash
flutter build apk --release --dart-define=AGORA_APP_ID=YOUR_AGORA_APP_ID
```

---

## How to test a call

1. Run the app on **two devices/emulators** (or device + emulator).
2. Create **two accounts** (register on each device).
3. On device A open **Contacts**, tap the person from device B, then tap
   **video** or **audio**.
4. Device B shows the **incoming call** screen → Accept.
5. During a video call use **Beauty**, **Blur**, and **Flip**; during an audio
   call toggle **Noise AI**.

---

## Project structure

```
lib/
├── main.dart                  # Firebase init + entry point
├── app.dart                   # root widget, auth routing, incoming-call listener
├── config/app_config.dart     # Agora App ID / token (--dart-define)
├── theme/app_theme.dart       # Material 3 theme + brand colors
├── models/                    # AppUser, ChatMessage, ChatSummary, CallData
├── services/
│   ├── auth_service.dart
│   ├── user_service.dart
│   ├── chat_service.dart      # Firestore messaging
│   ├── push_service.dart      # FCM
│   └── call_service.dart      # Agora engine wrapper (AINS, beauty, blur)
├── providers/                 # Riverpod providers + call controller
├── screens/
│   ├── auth/                  # login, register
│   ├── home/                  # chats + contacts tabs
│   ├── chat/                  # chat screen
│   └── call/                  # video / audio / incoming call
└── widgets/                   # avatar, call buttons
```

---

## Firestore schema

```
users/{uid}            -> { name, email, avatarUrl, fcmToken, createdAt }
chats/{chatId}         -> { participants: [a,b], lastMessage, lastMessageAt, lastSenderId }
chats/{chatId}/messages/{id} -> { chatId, authorId, text, sentAt, read }
calls/{id}             -> { callerId, callerName, calleeId, channelName, type, status, createdAt }
```

`chatId` = the two user ids, sorted and joined with `_` (order-independent).

---

## Known limitations / roadmap

- **Background incoming calls** — currently an incoming call rings only while
  the app is open (Firestore signaling). To ring a *closed* app you need a
  full-screen-intent notification + foreground service. Recommended:
  `flutter_callkit_incoming`, or send an FCM data message from a Cloud Function
  and launch a full-screen intent (`USE_FULL_SCREEN_INTENT` is already declared
  in the manifest).
- **Push for new messages** — FCM tokens are captured and stored; add a
  Cloud Function to fan out message notifications, or use Firestore triggers.
- **Group chats / image & file messages / read receipts / typing** — not yet
  implemented (1-on-1 text only).
- **Agora token** — production requires a token server; dev uses App ID only.

---

## Troubleshooting

- **`google-services.json` missing** → the Gradle build fails with a clear
  message. Add the file from Firebase (step 1).
- **Call fails to connect** → confirm both devices have network access and the
  Agora App ID is correct (and passed via `--dart-define`).
- **AINS/beauty has no effect** → activate the corresponding Agora Console
  extensions; the app logs nothing but silently falls back.
- **No incoming call UI** → both apps must be in the foreground (see roadmap
  for background calls).
