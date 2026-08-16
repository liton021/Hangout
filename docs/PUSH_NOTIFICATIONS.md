# Push notifications without Firebase/FCM — free options & what Hangout uses

**Context:** the Hangout app needs push for messages and incoming calls, for
free, without Firebase Cloud Messaging. In this project's Firebase console the
"Cloud Messaging API (Legacy)" toggle is broken (enable shows an error), and
the suggested workaround — Cloud Run / Cloud Functions — asks for billing,
which is off the table.

**This doc answers two things:**
1. What free, FCM-free options exist (and which ones look free but aren't).
2. What was implemented in this repo (WebSocket signaling on the existing
   Cloudflare Worker + local notifications), and its honest trade-offs.

---

## 1. First: a quick note about your FCM console problem

For future reference (not needed anymore): the "Cloud Messaging API (Legacy)"
toggle error is a known Firebase console bug. More importantly, the modern
**FCM HTTP v1 API does not use the legacy API at all** — it only needs a
service account key, and sending can be done from *any* server (including this
repo's Cloudflare Worker) with **no Cloud Run, no Cloud Functions, and no
billing**. So even within Firebase, the specific blockers you hit were
avoidable. That said, the requirement here is *no Firebase for push*, and the
solution below honors that.

---

## 2. The options (Android, as of Aug 2026)

| Option | Free? | Real FCM-free? | Delivery while app killed | Notes |
|---|---|---|---|---|
| **Persistent WebSocket + foreground service** (Telegram/WhatsApp-style) | ✅ $0 (Cloudflare Workers free tier, no billing) | ✅ yes | ✅ while the service runs | **Implemented here.** Battery cost + OEM battery-killer caveats. |
| **UnifiedPush + self-hosted distributor** (ntfy / Gotify / NextPush) | ✅ $0 self-hosted | ✅ yes | ✅ excellent | Open protocol, zero Google. But **every user must install a distributor app** (or you embed one) — bad UX for end users. |
| **OneSignal** | ✅ free tier (10k subscribers) | ❌ no | ✅ | On Android it still **delivers through FCM** — you'd need Firebase/Google anyway. |
| **Pusher Beams** | ✅ free tier (1k devices) | ❌ no | ✅ | Also rides FCM on Android. |
| **Pushy / WonderPush / Airship** | ❌ paid (or tiny free tier) | ⚠️ Pushy runs its own socket | ✅ | Pushy is the classic "no FCM" commercial answer — but it costs real money. |
| **Web Push (VAPID)** | ✅ $0 | ✅ yes (browser) | ✅ (browser only) | Only works for **browsers/PWAs**, not a native Flutter Android app. |
| **Periodic polling** (WorkManager) | ✅ $0 | ✅ yes | ⚠️ delayed | Not real-time; battery-hostile if polled often. Rejected. |

**Bottom line:** every "free push SaaS" for Android (OneSignal, Pusher Beams,
etc.) secretly uses FCM under the hood. The only genuinely FCM-free routes are
(a) a persistent connection you run yourself, or (b) UnifiedPush with a
self-hosted distributor. For a consumer app, (a) is the practical choice —
and this repo already had the perfect free home for it: the Cloudflare
Worker.

---

## 3. What was implemented: WebSocket mailbox on the Cloudflare Worker

### Architecture

```
 [Device A]  ──POST /send──▶  Cloudflare Worker (free)         [Device B]
  caller /                     │  ┌─ Durable Object per uid    callee /
  sender                       │  │  ("PushRoom" mailbox)      recipient
                               │  │   · holds live WebSockets  ◀──WSS /ws?uid=B──
                               │  │   · buffers events ~10 min
                               │  └────────────────────────────
                               └─ also still serves /rtc-token
```

1. **Every signed-in device** connects `wss://<worker>/ws?uid=<uid>` with its
   Firebase **ID token** (`Authorization: Bearer …`). The Worker verifies the
   token against Google's public signing certs — pure JWT verification, **no
   service account, no console changes, no billing**. The app reconnects
   automatically with backoff and heartbeats.
2. **Sending a message / placing a call** POSTs the event to `/send` (same
   token auth, rate-limited). The Worker routes it to the recipient's
   Durable Object, which forwards it to every connected device of that user
   (and buffers it ~10 min if all devices are offline).
3. **The receiving device raises a local notification** via
   `flutter_local_notifications`:
   - **Messages** → heads-up notification; tapping opens the conversation.
   - **Calls** → full-screen-intent ringing alert with **Accept/Decline**
     actions; Accept joins the Agora channel, Decline rejects the call doc.
   - **`call_cancelled` / `call_rejected` / `call_ended`** → the ringing
     alert is dismissed automatically.
4. **A foreground service** (`flutter_foreground_task`,
   `dataSync|remoteMessaging`) keeps the Flutter engine — and the socket —
   alive while the app is backgrounded, restarts on boot, and hides its
   quiet "Connected" notification while the app is in the foreground.
   While the app is visible, no system notifications are shown (the UI
   already updates live via Firestore).

### Cost

$0. Cloudflare Workers free plan: 100k requests/day (WebSocket messages
included), Durable Objects free tier — orders of magnitude above what a small
messaging app consumes. No billing account required, no credit card.

### Code map

| Piece | Where |
|---|---|
| Worker: `/ws`, `/send`, `PushRoom` DO, ID-token verification | `token_server/worker.js` |
| DO binding + `FIREBASE_PROJECT_ID` var | `token_server/wrangler.toml` |
| Client socket, reconnect, notifications, taps | `hangout_app/lib/services/push_service.dart` |
| Foreground service | `hangout_app/lib/services/background_connection.dart` |
| Call invite/cancel push + remote accept/reject | `hangout_app/lib/providers/call_controller.dart` |
| Message push | `hangout_app/lib/services/chat_service.dart` |
| Notification-tap routing (accept → call screen, message → chat) | `hangout_app/lib/app.dart` |
| Server URLs | `hangout_app/lib/config/app_config.dart` |
| Manifest (service, FGS types, full-screen attrs) | `hangout_app/android/.../AndroidManifest.xml` |

`firebase_messaging` was removed from `pubspec.yaml`; Firebase Auth and
Firestore remain (they were never the problem).

---

## 4. Honest trade-offs (read before shipping)

- **Battery** — a persistent socket costs a little battery (Telegram/WhatsApp
  accept the same cost). The foreground service notification is quiet and
  hides itself while the app is open.
- **OEM battery killers** (Xiaomi, Huawei, Samsung, OnePlus…) may kill the
  service when the app is swiped away. Mitigation: ask users to allow
  background activity for Hangout (the README's troubleshooting covers it).
  FCM survives this because it's a Google system service — this is the one
  genuine advantage FCM keeps on Android.
- **Android 15**: `dataSync` foreground services are capped at 6 h/day in the
  background; the service is also declared as `remoteMessaging` (the type
  designed for messaging apps) which is not capped and can start on boot.
- **Full-screen intents** on Android 14+ are restricted to calling/alarm
  apps — Hangout qualifies, but if the user denies it the call alert falls
  back to a loud heads-up notification.
- **Force-stopped app** receives nothing until next open (same as every
  non-FCM approach).

## 5. If you ever want UnifiedPush too

The WebSocket implementation above is self-contained. Adding UnifiedPush
later (via `unifiedpush` packages + a self-hosted ntfy server) is a drop-in
complement for users who install a distributor — the push events are the
same JSON, just an extra delivery path.
