# Agora Deep‑Dive + Chat Layer Decision

**Date:** 15 August 2026
**Decision summary:** Calls = **Agora RTC** (confirmed, free 10,000 min/mo). Chat = **Firebase Firestore + FCM** (primary) or **Agora Chat** (single‑vendor alternative). Full reasoning below.

---

## 1. Agora — why it's a strong (and confirmed free) choice

Your instinct is correct. Agora is the most battle‑tested RTC provider for Android/Flutter and its free tier is genuinely recurring, not a one‑time credit.

### 1.1 Free tier & pricing (verified)

| Item | Cost |
|---|---|
| **Free minutes** | **First 10,000 combined RTC minutes every month, free** (recurring) |
| Base RTC after free | from ~$0.59 / 1,000 min (audio ~$0.99; video SD ~$3.99, HD ~$8.99 per 1,000 min) |
| **Built-in noise suppression / AEC / AGC** | **Free — bundled with the SDK, on by default** |
| AI Noise Suppression (AINS) | ⚠️ **Paid extension** — must be activated in the console (asks for a credit card). Not used in this project. |
| 3D Spatial Audio | $0.99 / 1,000 min (included in free 10k) |
| Beauty / virtual background / video denoise | Bundled in the SDK (no per‑feature fee) |

> **Bottom line:** a solo developer or small app can run entirely on the free
> 10,000 min/month (≈ 166 hours of call time / month) using the **free built-in
> noise suppression** — no paid AI extension required.

### 1.2 Flutter SDK (verified current)

- Package: **`agora_rtc_engine`** — version **6.6.3**, published by **verified publisher `agora.io`**.
- Supports Android, iOS, macOS, Windows, Web (web is alpha — irrelevant for your Android‑only app).
- Built on Agora Native SDK 4.x.

### 1.3 Noise filtering in Agora (the key requirement)

Agora gives you two tiers of audio cleanup:

1. **Built‑in DSP (free, always on)** — Acoustic Echo Cancellation (AEC),
   Noise Suppression (NS) and Automatic Gain Control (AGC). These ship with the
   SDK, are enabled by default, and cost nothing. **This is what the app uses.**
2. **AI Noise Suppression (AINS)** — a deep‑learning model that removes 100+
   noise types. **⚠️ This is a paid extension**: you must activate it in the
   Agora console, which requires entering a credit card. The project does
   **not** use it.

You can control the free built-in processing with `setParameters` (no
extension, no credit card):

```dart
final engine = createAgoraRtcEngine();
await engine.initialize(RtcEngineContext(appId: appId));

// Free built-in noise suppression + echo cancellation + auto gain control.
await engine.setParameters('{"che.audio.ns.enable": true}');
await engine.setParameters('{"che.audio.aec.enable": true}');
await engine.setParameters('{"che.audio.agc.enable": true}');
```

### 1.4 Video filters & effects (free, bundled)

| Feature | Flutter API | Notes |
|---|---|---|
| **Beauty / skin smoothing** | `setBeautyEffectOptions()` | lightening, smoothness, redness, sharpness |
| **Face shaping** | `setFaceShapeBeautyOptions()` | slimmer face, bigger eyes, etc. |
| **Virtual background** | `enableVirtualBackground()` | blur / solid color / image / video |
| **Video denoise** | `setVideoDenoiserOptions()` | cleans grainy camera output |
| **Low‑light enhancement** | `setLowlightEnhanceOptions()` | brightens dark rooms |
| **Color enhancement** | `setColorEnhanceOptions()` | richer colors |
| Voice changer / reverb / EQ | `setVoiceBeautifierPreset`, `setAudioEffectPreset` | fun audio effects |

Flutter example:

```dart
await engine.setBeautyEffectOptions(
  enabled: true,
  options: BeautyOptions(
    lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
    lighteningLevel: 0.7,
    smoothnessLevel: 0.5,
    rednessLevel: 0.1,
  ),
);
```

> Note: advanced "AR mask"‑style filters still need a paid extension (e.g. Banuba). But **beauty, smoothing, face shaping, virtual background, denoise, low‑light and color** are all free and built in — more than enough for a modern consumer call app.

### 1.5 What you give up with Agora

- Not open source (proprietary SDK + managed cloud — vendor lock‑in).
- Per‑minute pricing grows linearly at scale (fine for free/dev, becomes expensive at huge scale).
- Web support is alpha (irrelevant for Android‑only).

---

## 2. The CHAT layer — the decision I owe you

This is the part you rightly flagged. For a messaging + calling app you need a chat backend that gives you: **1‑on‑1 & group text, image/file messages, offline sync, read receipts, presence, and — critically — push notifications** (so a message or an incoming call wakes the app on Android).

### 2.1 The two realistic free options

| | **Firebase (Firestore + FCM)** | **Agora Chat (agora_chat_sdk)** |
|---|---|---|
| Flutter package | `cloud_firestore` + `firebase_messaging` | `agora_chat_sdk` (v1.4.0) |
| Free tier | 1 GB storage, 5 GB files, 50k auth MAU, **FCM push unlimited** | **500 MAU, 50 concurrent connections, 7‑day message history**, 100 contacts/user, 100 groups |
| Push notifications | ✅ **bundled & free (FCM)** | ❌ **not available on free tier** |
| Offline / sync | ✅ | ✅ (but only 7‑day retention free) |
| Modern UI widgets | use `flutter_chat_ui` (free, backend‑agnostic) | build custom or limited widgets |
| Vendor lock‑in | Google | Agora (already using it for calls) |
| Data model | NoSQL (flexible) | Chat‑specific (rooms/contacts) |

### 2.2 ✅ Recommendation: **Firebase for chat + push**, Agora for calls

**Why Firebase for chat:**

1. **Push is non‑negotiable on Android.** For an incoming call to ring the device (full‑screen intent + foreground service) *and* for new‑message notifications, you need FCM (Firebase Cloud Messaging). Firebase gives it to you bundled and free — Agora Chat does **not** include push on its free tier.
2. **Its free tier is far more generous** than Agora Chat (500 MAU + 50 concurrent connections is very easy to hit; and Agora Chat's free tier drops message history after 7 days).
3. **Most mature Flutter integration on the market** — the `flutter_chat_ui` package pairs with it cleanly for a modern look.
4. You can still use FCM to deliver **Agora call invitations** (the standard pattern: send a high‑priority FCM data message → app auto‑joins/rings the Agora channel). So Firebase naturally bridges chat *and* call signaling.

**When to pick Agora Chat instead:** only if you want a *single vendor* (one bill, one dashboard) and are okay paying for the Starter/Pro tier from day one — its free tier is too restrictive for anything beyond a prototype, especially the missing push.

### 2.3 (Optional) third path — Supabase

Open‑source, no Google lock‑in, predictable pricing. But realtime connection limits (~200 free concurrent) and no built‑in mobile push (you'd still wire FCM yourself). Choose Supabase if "open source / no vendor" matters more to you than speed. For this app I recommend Firebase.

---

## 3. Final architecture (locked in)

| Layer | Choice | Package / service |
|---|---|---|
| Auth | Firebase Auth | `firebase_auth` |
| **Chat / messaging** | **Firestore (realtime) + FCM push** | `cloud_firestore`, `firebase_messaging` |
| **Audio/Video calls** | **Agora RTC** | `agora_rtc_engine` ^6.6.3 |
| **Noise filter** | Agora **built-in NS + AEC + AGC (free)** | `setParameters('{"che.audio.ns.enable": …}')` |
| **Video filters** | Agora beauty + virtual background + denoise | `setBeautyEffectOptions()`, `enableVirtualBackground()` |
| Call invites / ringing | FCM high‑priority + full‑screen intent + foreground service | `firebase_messaging` + Android manifest |
| UI | `flutter_chat_ui` (chat) + custom Material 3 (calls, contacts, shell) | `flutter_chat_ui`, `flutter_animate` |
| State mgmt | Riverpod | `flutter_riverpod` |

### `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Calls + noise filtering + video filters
  agora_rtc_engine: ^6.6.3

  # Auth + chat + push
  firebase_core: ^3.x
  firebase_auth: ^5.x
  cloud_firestore: ^5.x
  firebase_messaging: ^15.x

  # Modern UI
  flutter_chat_ui: ^1.x
  flutter_riverpod: ^2.x
  flutter_animate: ^4.x

  # utilities
  permission_handler: ^11.x
```

---

## 4. How the pieces fit (call flow)

1. **Caller taps call** → app publishes to Firestore `calls/{id}` and sends a high‑priority **FCM** data message to the callee.
2. **Callee's device** receives FCM → Android **full‑screen intent** launches the incoming‑call UI and starts a **foreground service** (`FOREGROUND_SERVICE_PHONE_CALL`), even if the app is killed.
3. **Both join the same Agora channel** (channel name = call id) → `joinChannel()`.
4. **Filters applied**: built-in `setParameters('{"che.audio.ns.enable": true}')` (plus AEC/AGC) for noise-free audio; `setBeautyEffectOptions(...)` + `enableVirtualBackground(...)` for video filters.
5. On end call, both `leaveChannel()` and the Firestore call doc is marked ended.

---

## 5. Sources

- Agora Pricing (10,000 free min + AI NS $0.59/1k): https://www.agora.io/en/pricing/
- Agora AI Noise Suppression docs (`setAINSMode`): https://docs.agora.io/en/video-calling/advanced-features/ai-noise-suppression
- Agora Flutter API — beauty/virtual background/denoise/lowlight: https://api-ref.agora.io/en/voice-sdk/flutter/5.x/API/rtc_api_overview.html
- Agora Flutter SDK (v6.6.3): https://pub.dev/packages/agora_rtc_engine
- Agora Chat Flutter SDK (v1.4.0): https://pub.dev/packages/agora_chat_sdk
- Agora Chat free‑tier limits (500 MAU, 50 concurrent, 7‑day retention, no free push): https://trtc.io/blog/details/agora-chat-alternative-better-free-tiers
- Agora Chat product page: https://www.agora.io/en/products/chat/
- Supabase vs Firebase free tiers: https://anotherwrapper.com/blog/supabase-vs-firebase
