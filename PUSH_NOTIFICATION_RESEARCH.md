# Push Notification Research — Hangout

## How Top Apps Handle Notifications When the App Is Closed

Research conducted 2026-08-16 — covering WhatsApp, Telegram, Signal, and general
VoIP call best practices.

---

## 1. How WhatsApp / Telegram / Signal Work

### The Core Strategy: Push as Wake-Up Signal

None of these apps keep a persistent socket alive in the background — modern
Android (Oreo+) and iOS aggressively kill such sockets for battery reasons.
Instead they use **platform push services as a wake-up mechanism**:

```
Sender ──► Your Server ──► FCM / APNs ──► Device ──► OS wakes app
                                                       │
                                        ┌──────────────┴──────────────┐
                                        ▼                             ▼
                                   Android                     iOS
                              FCM data msg              APNs / PushKit
                              background isolate        VoIP push cert
                              runs onMessageReceived    report to CallKit
```

### 1a. Messaging (text notifications)

| App | Android | iOS |
|-----|---------|-----|
| **WhatsApp** | FCM **data-only** message → background handler decrypts → shows notification via local channel | APNs + Notification Service Extension (decrypts payload before display) |
| **Telegram** | FCM data message → background handler processes → shows notification | APNs + uses Notification Service Extension |
| **Signal** | FCM data message → background handler (they use a foreground service too) | APNs + Notification Service Extension for decryption |

All three use **end-to-end encryption**, so the push payload itself does **not**
contain the message plaintext — it's a "wake up, go fetch" signal. Once the app
wakes, it connects to the server, decrypts the message, and shows a local
notification.

**Key insight:** On Android, the FCM payload must be **data-only** (no
`notification` key) for the background handler to fire when the app is killed.
A `notification` key causes Android to display the notification through system
UI without waking the app's Dart code.

### 1b. Incoming calls

| App | Android | iOS |
|-----|---------|-----|
| **WhatsApp** | FCM high-priority data msg → foreground service → **ConnectionService** for native call UI | **PushKit** VoIP push → **CallKit** native full-screen incoming call |
| **Telegram** | FCM high-priority data msg → foreground service | PushKit VoIP push → CallKit |
| **Signal** | FCM high-priority data msg + foreground service | PushKit VoIP push → CallKit |

Calls require **two extra things** beyond regular notifications:

1. **Native call UI** — On iOS, CallKit shows the lock-screen incoming call
   (slide to answer). On Android, ConnectionService shows the native incoming
   call screen. Both are required by platform policies.

2. **VoIP-specific push** — On iOS, a regular APNs push cannot wake a killed
   app for a call. Only a **PushKit VoIP push** (with a special VoIP services
   certificate) can do this. Apple enforces this: every VoIP push **must**
   result in a `reportNewIncomingCall(to:)` within seconds, or future pushes
   are throttled.

---

## 2. How FCM Delivery Works by App State

### Android

| App State | FCM with `notification` key | FCM **data-only** (no `notification` key) |
|-----------|---------------------------|-------------------------------------------|
| **Foreground** | `onMessage` fires in Dart | `onMessage` fires in Dart |
| **Background** | System tray shows notification automatically; Dart **NOT** woken | `onBackgroundMessage` fires in background isolate |
| **Killed** | System tray shows notification; Dart **NOT** woken | `onBackgroundMessage` fires in background isolate ✅ |

### iOS

| App State | APNs with `alert` payload | APNs `content-available: 1` (silent) | PushKit VoIP push |
|-----------|--------------------------|--------------------------------------|-------------------|
| **Foreground** | `didReceiveRemoteNotification` | Background fetch callback | `didReceiveIncomingPushWith` |
| **Background** | System shows banner; app gets minimal callback | ~30s background execution | App woken + must report to CallKit |
| **Killed** | System shows banner; app not woken | Not reliable | **Wakes app even when killed** ✅ |

### Cross-platform summary

```
For MESSAGES (non-VoIP):
  Android: FCM data-only → onBackgroundMessage
  iOS:     APNs with content-available + Notification Service Extension

For CALLS (VoIP):
  Android: FCM data-only + high priority → foreground service → ConnectionService
  iOS:     PushKit VoIP push → CallKit (MANDATORY — Apple policy)
```

---

## 3. Current State of Hangout

### What already exists ✅

| Asset | Status |
|-------|--------|
| FCM setup (`google-services.json`) | ✅ Already present |
| `PushService` class | ✅ Token management + foreground listener |
| `firebaseMessagingBackgroundHandler` | ✅ **Empty placeholder** in `main.dart` |
| Android permissions | ✅ `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_PHONE_CALL`, `USE_FULL_SCREEN_INTENT`, `WAKE_LOCK` all declared |
| In-app call signaling (Firestore) | ✅ Works when app is in foreground |
| Flutter `firebase_messaging` package | ✅ In `pubspec.yaml` |

### What's missing ❌

| Gap | Impact |
|-----|--------|
| Background handler is **empty** | FCM data messages are received but no notification is shown when app is killed |
| No `flutter_callkit_incoming` package | No native incoming call UI on either platform |
| No iOS PushKit / VoIP certificate setup | iOS calls won't ring if app is background/killed |
| No foreground service on Android | Android 14+ kills FCM delivery for apps without a foreground service for calls |
| No Cloud Function for sending FCM | Currently no server-side push when a message or call is created |
| No iOS `Notification Service Extension` | Can't show decrypted message content in push notification on iOS |

---

## 4. Recommended Implementation Plan

### Phase 1 — Message Notifications (lower effort, high impact)

**Goal:** Show a push notification when a new chat message arrives, even if the
app is killed.

#### Server side (Cloud Function)

Deploy a Firebase Cloud Function that triggers on `chats/{chatId}/messages/{msgId}`
creations, looks up the recipient's `fcmToken` from their `users/{uid}` doc,
and sends an FCM message:

```javascript
// functions/src/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.onNewMessage = functions.firestore
  .document('chats/{chatId}/messages/{msgId}')
  .onCreate(async (snap, context) => {
    const msg = snap.data();
    const chatId = context.params.chatId;

    // Determine recipient
    const chatDoc = await admin.firestore()
      .collection('chats').doc(chatId).get();
    const participants = chatDoc.data().participants; // [uidA, uidB]

    const senderUid = msg.authorId;
    const recipientUid = participants.find(uid => uid !== senderUid);

    // Get recipient's FCM token
    const userDoc = await admin.firestore()
      .collection('users').doc(recipientUid).get();
    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) return;

    // Send data-only message (no 'notification' key!)
    await admin.messaging().send({
      token: fcmToken,
      data: {
        type: 'message',
        chatId: chatId,
        senderId: senderUid,
        senderName: msg.authorName || 'Someone',
        text: msg.text || '',
        sentAt: String(msg.sentAt?.toMillis() || Date.now()),
      },
      android: { priority: 'high' },
      apns: {
        payload: {
          aps: {
            alert: { title: msg.authorName, body: msg.text },
            sound: 'default',
            badge: 1,
          },
        },
      },
    });
  });
```

> **Why data-only on Android + alert payload on iOS?**  
> Android needs data-only for `onBackgroundMessage` to fire. iOS can use the
> `alert` payload directly since APNs shows it in the notification tray
> automatically even when the app is killed — and we don't need custom
> rendering for simple text messages yet.

#### Client side (Flutter — `main.dart`)

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final data = message.data;
  final type = data['type'];

  if (type == 'message') {
    // For Android: FCM data-only means we must show the notification
    // ourselves using flutter_local_notifications.
    await _showMessageNotification(data);
  } else if (type == 'incoming_call') {
    // For calls: wake the app and show native incoming call UI
    await _handleIncomingCallPush(data);
  }
}

Future<void> _showMessageNotification(Map<String, dynamic> data) async {
  // Use flutter_local_notifications to display a notification
  // with the message content, sender name, and a tap-to-open action.
  final plugin = FlutterLocalNotificationsPlugin();
  // ... initialization + show call
}
```

Add `flutter_local_notifications` to `pubspec.yaml` for showing notifications
from the background isolate.

### Phase 2 — Incoming Call Notifications (higher effort, critical for UX)

**Goal:** Show a native incoming call screen (full-screen, with ringtone) even
when the app is killed.

#### Add dependency
```yaml
dependencies:
  flutter_callkit_incoming: ^2.1.0
```

#### Android setup
Already done in `AndroidManifest.xml`:
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_PHONE_CALL` ✅
- `USE_FULL_SCREEN_INTENT` ✅
- `POST_NOTIFICATIONS` ✅

Need to add to `AndroidManifest.xml` inside `<application>`:
```xml
<!-- Required for ConnectionService (native call UI) -->
<service
    android:name="io.wazo.callkeep.VoiceConnectionService"
    android:foregroundServiceType="phoneCall"
    android:exported="false" />
<service
    android:name="io.wazo.callkeep.RingingService"
    android:foregroundServiceType="phoneCall"
    android:exported="false" />
```

#### iOS setup
1. In Apple Developer Portal, generate a **VoIP Services Certificate**
2. In Xcode, enable **Background Modes → Voice over IP**
3. Register for PushKit VoIP pushes on app launch:
```dart
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

// On app start
FlutterCallkitIncoming.instance.requestNotificationPermissions();
final token = await FlutterCallkitIncoming.instance.getVoIPToken();
// Send token to your server
```

#### Background handler for calls

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  if (message.data['type'] == 'incoming_call') {
    await FlutterCallkitIncoming.instance.showCallkitIncoming(
      CallKitParams(
        id: message.data['callId'],
        nameCaller: message.data['callerName'],
        handle: message.data['callerId'],
        type: message.data['isVideo'] == 'true'
            ? CallType.video
            : CallType.audio,
        textAccept: 'Accept',
        textDecline: 'Decline',
        ringtonePath: 'ringtone.mp3',
        // Android
        extra: <String, dynamic>{'channelName': message.data['channelName']},
      ),
    );
  }
}
```

#### Listen for accept/decline events

```dart
FlutterCallkitIncoming.instance.onEvent.listen((event) {
  switch (event.event) {
    case Event.actionCallAccept:
      // User accepted — navigate to VideoCallScreen / AudioCallScreen
      // and join the Agora channel
      break;
    case Event.actionCallDecline:
      // User declined — mark call as rejected in Firestore
      break;
    case Event.actionCallEnd:
      // Call ended
      break;
  }
});
```

### Phase 3 — iOS Notification Service Extension (for encrypted messages)

If Hangout implements end-to-end encryption for messages, messages won't be
readable in the push payload. On iOS, you need a **Notification Service
Extension** (a separate target in Xcode) that intercepts the push notification,
decrypts the content, and provides the plaintext to the notification UI.

This is what WhatsApp/Signal/Telegram all do on iOS.

---

## 5. Summary Comparison

| Feature | WhatsApp | Telegram | Signal | Hangout (now) | Hangout (planned) |
|---------|----------|----------|--------|---------------|-------------------|
| Android msg push | FCM data + bg handler | FCM data + bg handler | FCM data + fg service | ❌ None | FCM data + bg handler + local notif |
| iOS msg push | APNs + NSE | APNs + NSE | APNs + NSE | ❌ None | APNs alert payload (Phase 1) |
| Android call push | FCM high + ConnectionService | FCM high + ConnectionService | FCM high + ConnectionService | ❌ In-app only | FCM data + `flutter_callkit_incoming` |
| iOS call push | PushKit + CallKit | PushKit + CallKit | PushKit + CallKit | ❌ In-app only | PushKit + `flutter_callkit_incoming` |
| Background msg when killed | ✅ | ✅ | ✅ | ❌ | ✅ (Phase 1) |
| Background call when killed | ✅ | ✅ | ✅ | ❌ | ✅ (Phase 2) |

---

## 6. Key Takeaways

1. **Data-only FCM messages (no `notification` key)** are the only way to wake
   a killed Android app's Dart code. Always send `data` without `notification`
   for Android.

2. **For iOS calls, PushKit is non-negotiable.** Apple will throttle/cut off
   your VoIP pushes if you don't report them to CallKit within seconds.

3. **Agora + CallKit/ConnectionService** — When the user taps Accept on the
   native incoming call UI, the Flutter app joins the Agora channel (which the
   caller already created). The Firestore call doc (`calls/{id}`) bridges the
   two: caller sets status=ringing, callee's push arrives, callee accepts,
   both join Agora.

4. **Existing infrastructure is ready** — FCM package, permissions, and
   `google-services.json` are already in place. The main missing piece is:
   - A Cloud Function to send FCM messages
   - `flutter_callkit_incoming` for native call UI
   - Implementation of the background handler (currently empty)
   - iOS VoIP certificate provisioning