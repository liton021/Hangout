# Hangout 📱

A modern **Android** messaging + voice/video calling app built with **Flutter**,
featuring:

- 💬 1-on-1 real-time messaging (Firestore)
- 🎤 Voice messages — hold to record, slide to cancel, 30-day retention
- 📞 Audio & video calls (Agora RTC)
- 🎙️ **Built-in noise suppression** (free SDK DSP: noise suppression + echo
  cancellation + auto gain — no paid extension)
- ✨ **Video filters** — beauty/skin smoothing, background blur, camera flip
- 🎨 Modern Material 3 UI (light + dark), Riverpod state management

Stack (see `../RESEARCH_REPORT.md` and `../AGORA_AND_CHAT_DECISION.md`):

| Layer | Technology |
|---|---|
| Calls + noise filtering + filters | **Agora** `agora_rtc_engine` (built-in, free) |
| Auth | Firebase Auth |
| Chat + call signaling | Cloud Firestore |
| **Push** | **Cloudflare Worker WebSocket + local notifications (FCM-free)** |
| State | flutter_riverpod |

> **No FCM.** Push notifications for calls & messages are delivered over a
> persistent WebSocket to the Cloudflare Worker in `../token_server/` (free
> plan, no billing) and raised locally by the app — see
> `../docs/PUSH_NOTIFICATIONS.md` for why and how.

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

> **No paid extensions needed.** Noise suppression, echo cancellation and auto
> gain control use Agora's built-in (free) DSP — they are on by default. Do
> **not** activate the "AI Noise Suppression" extension: it is paid and asks
> for a credit card.

## 3. Configure push (FCM-free, required for background notifications)

Push rides on the **Cloudflare Worker** in `../token_server/` — no Firebase
Cloud Messaging, no billing:

1. Deploy the Worker (once):

   ```bash
   cd ../token_server
   npm i -g wrangler        # or: npx wrangler
   wrangler login
   wrangler secret put AGORA_APP_ID        # your Agora App ID
   wrangler secret put AGORA_APP_CERTIFICATE  # Agora Primary Certificate
   wrangler deploy          # FIREBASE_PROJECT_ID is already set in wrangler.toml
   ```

2. Point the app at it in `lib/config/app_config.dart` (`_pushServerUrl` and
   `_tokenServerUrl`) — or override per build:

   ```bash
   flutter run \
     --dart-define=AGORA_APP_ID=YOUR_AGORA_APP_ID \
     --dart-define=PUSH_SERVER_URL=https://hangout-token-server.<you>.workers.dev
   ```

That's it — messages and calls now reach the app while it's in the background
(via a foreground service that keeps the WebSocket alive, plus full-screen
intent notifications for incoming calls).

## 4. Configure profile pictures + voice messages (optional)

Avatars **and voice messages** are stored on the **same Cloudflare Worker**,
in the **same** KV namespace (different key prefixes). Workers KV is free and
— unlike R2 — needs **no credit card**:

```bash
cd ../token_server
npx wrangler kv namespace create AVATARS_KV
# paste the printed id into the [[kv_namespaces]] block in wrangler.toml
npx wrangler deploy
```

Then make sure `_avatarServerUrl` in `lib/config/app_config.dart` points at
your Worker (it defaults to the same URL as push/tokens), or override with
`--dart-define=AVATAR_SERVER_URL=...`.

Users change their photo by tapping their avatar on the **Settings** tab:
camera or gallery → pinch/drag to frame it → upload. The app crops to a
512×512 JPEG (~40–80 KB) before uploading, so a 1 GB KV namespace holds
roughly 15,000 avatars.

### Voice messages

The same binding enables voice notes in chat: **hold** the mic button in the
composer to record, slide left to cancel, release to send. Audio is mono AAC
at 32 kbps (~120 KB for 30 seconds) and capped at 2 minutes.

Voice notes **expire after 30 days**, which is what makes this work on a free
tier — storage reaches a steady state instead of growing forever. Roughly 145
one-minute notes per day are sustainable indefinitely on 1 GB. In practice the
free KV **write** limit (1,000/day) is the real ceiling, not storage. Tune the
window with `VOICE_TTL_SECONDS` in `token_server/worker.js`.

Skipping this step is safe — calls and text chat work exactly as before. The
app shows a clear "photo storage is not set up" message for avatars, and the
mic button is **hidden entirely** (the send button simply stays disabled on an
empty field) so there is no control that does nothing. To move to R2 (10 GB,
but Cloudflare requires a card) later, just bind a bucket; see
`../token_server/README.md`. **No app change needed.**

## 5. Run

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
   call toggle **Noise** (built-in noise suppression + echo cancellation).

To test **background push**: put device B in the background (or lock it) and
send a message / call from device A. Device B should raise a heads-up message
notification or a full-screen ringing call alert with **Accept/Decline** —
with no FCM involved.

---

## Project structure

```
lib/
├── main.dart                  # Firebase init + foreground-task init + entry point
├── app.dart                   # root widget, auth routing, push wiring, incoming-call listener
├── config/app_config.dart     # Agora App ID / token + push server URL (--dart-define)
├── theme/app_theme.dart       # Material 3 theme + brand colors
├── models/                    # AppUser, ChatMessage, ChatSummary, CallData, PushEvent
├── services/
│   ├── auth_service.dart
│   ├── user_service.dart
│   ├── chat_service.dart      # Firestore messaging + message push hook
│   ├── push_service.dart      # FCM-free push (WebSocket + local notifications)
│   ├── background_connection.dart  # foreground service keeping the socket alive
│   ├── call_service.dart      # Agora engine wrapper (noise NS/AEC/AGC, beauty, blur)
│   ├── avatar_service.dart    # profile pictures: crop/compress + upload to the Worker
│   └── voice_note_service.dart # voice notes: record AAC + upload to the Worker
├── providers/                 # Riverpod providers + call controller
├── screens/
│   ├── auth/                  # login, register
│   ├── home/                  # chats + contacts tabs
│   ├── settings/              # settings, profile photo picker + cropper
│   ├── chat/                  # chat screen
│   └── call/                  # video / audio / incoming call
└── widgets/                   # avatar, call buttons
```

---

## Firestore schema

```
users/{uid}            -> { name, email, avatarUrl, createdAt }
chats/{chatId}         -> { participants: [a,b], lastMessage, lastMessageAt, lastSenderId }
chats/{chatId}/messages/{id} -> { chatId, authorId, text, sentAt, read }
                          voice: + { kind: 'voice', audioUrl, audioSeconds }
calls/{id}             -> { callerId, callerName, calleeId, channelName, type, status, createdAt }
```

`chatId` = the two user ids, sorted and joined with `_` (order-independent).

---

## How background push works (FCM-free)

1. On sign-in the app opens a WebSocket to
   `wss://<push-server>/ws?uid=<uid>` (authenticated with the Firebase ID
   token, verified server-side against Google's public certs — no service
   account, no Cloud Messaging API, no billing).
2. A **foreground service** (`dataSync|remoteMessaging`) keeps the engine —
   and the socket — alive while the app is backgrounded/killed.
3. Sending a message or placing a call POSTs an event to the Worker's `/send`
   endpoint; the Worker (a Durable Object per user, free tier) forwards it to
   every connected device of that user. Events are buffered ~10 min if the
   device is offline.
4. The device raises a **local** notification: heads-up for messages,
   full-screen-intent ringing alert with Accept/Decline for calls.

Battery/lifecycle caveats: like all FCM-free approaches, delivery depends on
the foreground service surviving Doze/OEM battery killers — advise users to
allow background activity for Hangout. See `../docs/PUSH_NOTIFICATIONS.md`.

---

## Known limitations / roadmap

- **Group chats / image & file messages / read receipts / typing** — not yet
  implemented (1-on-1 text only). Profile *pictures* are supported (see
  step 4); sending images inside a chat is not.
- **Call ringing while the app is force-stopped** — works while the
  foreground service runs; if the user force-stops the app or an aggressive
  OEM battery manager kills the service, delivery resumes on next open.
- **Agora token** — production requires a token server; dev uses App ID only.

---

## Troubleshooting

- **`google-services.json` missing** → the Gradle build fails with a clear
  message. Add the file from Firebase (step 1).
- **Call fails to connect** → confirm both devices have network access and the
  Agora App ID is correct (and passed via `--dart-define`).
- **Noise/beauty has no effect** → noise reduction uses the free built-in
  processing (on by default, no console extension needed); for beauty/background
  blur, ensure the Agora "Virtual Background" extension is enabled in the
  console if you want those effects.
- **No incoming call UI / no background notifications** → check that the
  Worker was redeployed (`wrangler deploy`) and `_pushServerUrl` points at it;
  also grant notification permission and disable battery optimization for
  Hangout on the receiving device.
