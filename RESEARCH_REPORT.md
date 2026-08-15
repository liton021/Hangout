# Hangout — Research Report

## Free, Noise‑Filtered Video & Audio Calling + Messaging for a Flutter Android App

**Date:** 15 August 2026
**Scope:** Android‑only Flutter app with (1) messaging, (2) 1‑on‑1 and group audio/video calls, (3) best‑in‑class **noise filtering**, (4) **video filters / effects**, and (5) a **modern UI** — while staying **free** (open‑source or free‑tier).

---

## 1. Executive Summary

Two genuinely "free" paths exist, and the right one depends on how much infrastructure you want to run yourself:

| | **Path A — Fully open‑source / self‑hosted** | **Path B — Free‑tier managed SDK** |
|---|---|---|
| **Cost** | $0 (only your own server, e.g. a $5–10 VPS) | $0 to start (free minutes/tiers) |
| **Best for** | Maximum control, no vendor lock‑in, learning | Shipping a polished app fast |
| **Noise filter** | WebRTC AEC/NS/AGC + DeepFilterNet‑3 (free) | Built into the SDK (ZEGO ANS / Stream‑Krisp) |
| **Video filters** | ML Kit segmentation + custom shaders | Built in (beauty, virtual background) |
| **Effort** | High | Low–medium |

**Top recommendation (chosen):** **Agora RTC for calls** (`agora_rtc_engine`, free 10,000 min/month, free built‑in noise suppression/AEC/AGC + beauty/virtual‑background filters) **+ Firebase for messaging/auth/push** (Firestore + FCM, free Spark tier). Full justification and the chat‑layer decision are in `AGORA_AND_CHAT_DECISION.md`.

> ⚠️ **Correction (Aug 2026):** Agora's *AI* Noise Suppression (AINS) is a **paid
> extension** (requires console activation + credit card) and is **not** used.
> The app uses Agora's free built-in noise suppression / echo cancellation /
> auto gain control instead.

If "free" must mean *no vendor, ever*, the best stack is **`flutter_webrtc` + LiveKit (self‑hosted, Apache‑2.0) + DeepFilterNet‑3 / RNNoise (audio noise) + Google ML Kit (video background blur) + Supabase or Firebase (chat) + `flutter_chat_ui` (modern UI)**.

The rest of this report justifies these choices with comparisons and pricing.

---

## 2. Constraints & Assumptions

- **Platform:** Android only (you can safely ignore iOS plumbing).
- **Language:** Flutter (Dart).
- **Budget:** $0 recurring — open‑source or free‑tier only.
- **Features required:** text messaging, audio call, video call, **audio noise filtering**, **video filters/effects**, modern UI.

---

## 3. Part 1 — Free Audio Noise Filtering (the "best noise‑filtered call")

Audio noise suppression for real‑time calls is a solved problem with excellent free options.

### 3.1 The three production‑grade options

| Engine | Cost / License | Latency | Quality | Runs on Android? |
|---|---|---|---|---|
| **RNNoise** | Free, BSD‑style | ~10 ms | Good on steady noise (fans, hum, traffic) | Yes (C, ported to Android/ARM) |
| **DeepFilterNet 3** | Free, MIT / Apache‑2.0 | ~40 ms | **Best open‑source quality** (2M params, deep filtering) | Yes — official Android JNI binding exists |
| **WebRTC Audio Processing (APM)** | Free, built into WebRTC | ~5–10 ms | Solid AEC + NS + AGC, already in every WebRTC call | Yes — ships with `flutter_webrtc` |
| Krisp SDK | Commercial (paid) | ~25 ms | Production‑grade, "cleanest" | Yes, but paid (or via Stream's SDK) |

**Key takeaways:**

- **RNNoise** is the de‑facto standard free suppressor — used by OBS Studio, EasyEffects, Mumble and Discord. It is lightweight and ideal when CPU/battery matters.
- **DeepFilterNet 3** is the quality leader among *free* options (slightly higher CPU and latency, but clearly cleaner on variable noise like crowds/TV). There is a ready‑made Android JNI library: [`KaleyraVideo/AndroidDeepFilterNet`](https://github.com/KaleyraVideo/AndroidDeepFilterNet).
- **WebRTC's built‑in audio processing module (APM)** gives you Acoustic Echo Cancellation (AEC/AEC3), Noise Suppression (NS), Automatic Gain Control (AGC), Voice Activity Detection (VAD) and a high‑pass filter **for free, on‑device, with no extra library** — this is the baseline every call already has.

### 3.2 How you actually enable it in Flutter

`flutter_webrtc` exposes WebRTC's APM directly on a `RTCPeerConnection`:

```dart
final pc = await createPeerConnection(config);
await pc.enableNoiseSuppression(true);      // NS  — background noise removal
await pc.enableEchoCancellation(true);      // AEC — stops your own voice echoing back
await pc.enableAutoGainControl(true);       // AGC — evens out loud/quiet speech
await pc.enableHighpassFilter(true);        // removes low-frequency rumble/hum
await pc.enableAEC3(true);                  // newer, better echo cancellation
```

For *higher‑quality* suppression than WebRTC's built‑in NS, drop DeepFilterNet‑3 in as a native (JNI) audio processor in front of the mic track — still $0.

### 3.3 Managed SDKs that bundle noise filtering for free

If you don't want to build the audio pipeline yourself:

- **ZEGOCLOUD Express SDK** — `enableANS()` (active noise suppression), AI noise‑reduction modes (`ZegoANSModeAIBalanced`), `enableAEC`, `enableAGC`, transient‑noise suppression, speech enhancement, and even **video denoise** (`setVideoDenoiseParams`). All built in, free with the 10,000 free minutes.
- **Stream Video SDK (Flutter)** — ships **Krisp‑powered noise cancellation** via the `stream_video_noise_cancellation` package. Krisp is the gold standard; Stream exposes it in their SDK with a free/dev tier.

> **Desktop‑only options to be aware of (not usable in an Android app):** NVIDIA Broadcast (RTX GPU), AMD Noise Suppression, Windows Voice Focus. These are irrelevant here but worth knowing so you don't chase them for mobile.

---

## 4. Part 2 — Video Filters & Effects (beauty, background, AR)

| Option | Cost | What it gives you | Notes |
|---|---|---|---|
| **ZEGOCLOUD Effects** | Free (with SDK) | Beauty (smoothing, whitening, face‑shape), **virtual background**, color enhancement, voice changer, reverb | `enableEffectsBeauty()`, `setEffectsBeautyParam()`, `startEffectsEnv()` |
| **Google ML Kit Selfie Segmentation** | Free, on‑device | Real‑time person segmentation → **background blur / replace** | Build your own; no per‑user cost, private |
| **Banuba Face AR SDK** | Commercial (trial) | High‑end beauty, makeup, AR masks, virtual background | Integrates with Agora; paid after trial |
| **DeepAR** | Commercial | AR filters, 3D masks, Snapchat‑style lenses | Has a Flutter plugin; paid |
| **Stream Video** | Free/dev tier | Virtual background & background blur | Simpler but fewer "beauty" options |
| **Custom GLSL/Shader filters** | Free | Color grading, LUTs, overlays | Full control, more work |

**Recommendation:**
- Want **beauty filters + virtual background out of the box for free** → **ZEGOCLOUD**.
- Want **free, private, no‑vendor background blur/replacement** → **ML Kit Selfie Segmentation** (runs fully on‑device, no data leaves the phone).
- Want **highest‑end AR/beauty** later → Banuba or DeepAR (budget for it; both are commercial).

---

## 5. Part 3 — Call SDK / WebRTC Stack Comparison (Flutter, Android)

### 5.1 Managed (hosted) SDKs

| SDK | Free tier | Per‑min cost (after free) | Noise filter | Video filters | Flutter SDK |
|---|---|---|---|---|---|
| **ZEGOCLOUD** | **10,000 free min** | from ~$0.39–$3.99/1k min (tier/resolution) | ✅ ANS + AI NS + video denoise | ✅ Beauty + virtual bg + voice changer | ✅ official |
| **Agora** | 10,000 free min/mo | $0.99/1k audio, $3.99 SD / $8.99 HD per 1k video | ✅ NS/AI‑NS | ⚠️ beauty via paid Banuba ext. | ✅ official |
| **Stream (GetStream)** | Free/dev tier | usage‑based after | ✅ **Krisp** noise cancellation | ✅ virtual bg / blur | ✅ official |
| **100ms** | 10,000 free min/mo | ~$4/1k video min | ✅ | partial | ✅ official |
| **Daily** | 10,000 free min/mo | ~$0.004–$4/min | ✅ | partial | ✅ official |
| **VideoSDK** | limited free | $0.004 speaker‑min | ✅ | ✅ virtual background | ✅ official |
| **Twilio Video** | trial only | ~$4/1k min | — | — | ⚠️ Programmable Video EOL (group rooms discontinued) — avoid for new builds |

### 5.2 Open‑source / self‑hosted

| Stack | Cost | What it is | Notes |
|---|---|---|---|
| **`flutter_webrtc`** | Free | Full WebRTC in Flutter (P2P calls) | Needs signaling + TURN for NAT traversal |
| **LiveKit** | **Apache‑2.0, self‑host free** | SFU server + official Flutter client | Best open‑source option; group calls, recordings, E2EE |
| **coturn** | Free | TURN/STUN server (NAT traversal) | The "secret sauce" for reliable P2P calls |
| **Janus / mediasoup / ion‑sfu** | Free | Alternative SFUs | More plumbing |

**How the free path works for 1‑on‑1 calls:** two phones connect peer‑to‑peer via `flutter_webrtc`; signaling is exchanged over Firestore/Firebase or a tiny WebSocket; a self‑hosted **coturn** handles the ~15–20% of calls where NAT blocks direct P2P. For group calls, run **LiveKit** (free) on a small VPS.

---

## 6. Part 4 — Messaging & Backend (free)

| Backend | Free tier | Strengths | Weaknesses |
|---|---|---|---|
| **Firebase** (Firestore + Auth + FCM) | Spark: 1 GB Firestore, 5 GB storage, 50k auth MAU, FCM unlimited | Most mature Flutter integration, **push notifications built in (critical for call invites)**, realtime listeners | Proprietary, costs can spike at scale |
| **Supabase** | 2 projects, 500 MB Postgres, 1 GB storage, 50k MAU, realtime | Open source, SQL, **no vendor lock‑in**, predictable pricing, realtime | Realtime connection limits (~200 free concurrent) |
| **Appwrite** | Open source / self‑host | Fully self‑hostable, auth + DB + realtime | Smaller ecosystem |
| **Stream Chat** | Free/dev tier | Batteries‑included chat + modern widgets | Ties you to Stream for chat |

**Recommendation:** **Firebase** for an Android messaging app, because FCM (Firebase Cloud Messaging) is effectively required for **incoming‑call push notifications** on Android (full‑screen intents + foreground service). **Supabase** is the better choice if you want open source / no vendor lock‑in.

---

## 7. Part 5 — Modern UI Options (Flutter)

| Option | Cost | What it gives you |
|---|---|---|
| **`flutter_chat_ui`** (open source) | Free | Polished, modern chat bubbles/threads you wire to *any* backend |
| **`stream_chat_flutter`** | Free/dev | Very modern chat UI, but coupled to Stream backend |
| **`chatview` / `flyer_chat`** | Free | Alternative open‑source chat widgets |
| **Custom Material 3** | Free | `Material You`, dynamic color, glassmorphism, animated gradients — full control |
| **State mgmt:** `riverpod` or `flutter_bloc` | Free | Clean architecture, testable |

**Recommendation:** use **`flutter_chat_ui`** (backend‑agnostic) for the chat screen, and a **custom Material 3** theme for the call screens + app shell (splash, login, contacts) for a distinctive modern look. Add `flutter_animate` for micro‑interactions.

---

## 8. Recommended Architectures (final answer)

### 🥇 Path B — Fastest to a polished app (CHOSEN — see `AGORA_AND_CHAT_DECISION.md`)

| Layer | Choice | Why |
|---|---|---|
| Auth + user store | Firebase Auth + Firestore | Free, instant |
| Messaging | Firestore realtime listeners + FCM push | Free, offline cache, push bundled |
| Push / call invites | FCM + full‑screen intent + foreground service | Required on Android |
| **Calls (audio+video)** | **Agora RTC (`agora_rtc_engine`)** | 10,000 free min/mo; free built‑in **noise suppression + echo cancellation + auto gain** + beauty + face shaping + virtual background + video denoise |
| UI | `flutter_chat_ui` (chat) + custom Material 3 (calls/contacts) | Modern, backend‑agnostic chat UI |

**Why this wins for your requirements:** Agora bundles **noise filtering (free built-in NS/AEC/AGC) *and* video filters (beauty, virtual background, denoise) into one SDK**, and Firebase covers messaging + the push notifications that a chat/call app cannot work without — all for $0 (the paid AI Noise Suppression extension is unnecessary).

### 🥈 Path A — Fully free, open‑source, no vendor

| Layer | Choice | Why |
|---|---|---|
| Auth + store + realtime | Supabase (or Firebase) | Open source, free tier |
| **Calls** | **`flutter_webrtc`** (P2P) + **coturn** (free TURN) + **LiveKit** (self‑host, free) for groups | $0 forever, full control |
| **Noise filter** | WebRTC APM (AEC/NS/AGC) + **DeepFilterNet‑3** (best free quality) or **RNNoise** (lightest) | On‑device, free |
| **Video filters** | **Google ML Kit Selfie Segmentation** (background blur/replace) + custom shaders | Free, private |
| UI | `flutter_chat_ui` + custom Material 3 | Modern, no lock‑in |

**Why this wins:** zero recurring cost, zero data leaving your infra, maximum control — at the cost of building signaling, TURN and the filter pipeline yourself.

---

## 9. Cost Comparison (per month, rough)

| Scenario | ZEGOCLOUD + Firebase | flutter_webrtc + LiveKit + Supabase (self‑host) |
|---|---|---|
| Hobby / dev (< 10k call min) | **$0** | $0 (or ~$5 VPS for coturn/LiveKit) |
| 1,000 MAU | $0 – small usage fee | ~$5–10 (server only) |
| 10,000 MAU | usage‑based (grows linearly) | ~$15–30 (server only) |
| At large scale | becomes expensive | stays flat (you run servers) |

---

## 10. Suggested Implementation Roadmap (Android, Flutter)

1. **Scaffold** — `flutter create` (Android only), Material 3 theme, `riverpod`.
2. **Auth** — Firebase Auth (email + Google) → users in Firestore.
3. **Messaging** — chat list + chat screen (`flutter_chat_ui`), Firestore realtime.
4. **Calls** —
   - *Path B:* drop in ZEGO Call UIKit, wire call buttons to invitees, enable `enableANS(true)` + beauty params.
   - *Path A:* `flutter_webrtc` P2P + Firestore/Supabase signaling + coturn; enable `enableNoiseSuppression`/`enableAEC3`; add DeepFilterNet‑3 for best audio.
5. **Video filters** — ZEGO beauty/virtual bg (Path B) or ML Kit segmentation (Path A).
6. **Incoming‑call UX (Android)** — FCM high‑priority + **full‑screen intent** + **foreground service** (Android 14+ requires `USE_FULL_SCREEN_INTENT` and `FOREGROUND_SERVICE_PHONE_CALL`).
7. **Polish** — animations, dark mode, call history, presence, read receipts.
8. **Release** — min/target SDK, ProGuard/R8 rules for WebRTC/ZEGO, Play Store.

### Sample dependencies (Path B)

```yaml
dependencies:
  flutter:
    sdk: flutter
  agora_rtc_engine: ^6.6.3           # calls + AI noise suppression + filters
  firebase_core: ^3.x
  firebase_auth: ^5.x
  cloud_firestore: ^5.x              # chat + call signaling
  firebase_messaging: ^15.x          # push + call invites
  flutter_chat_ui: ^1.x              # modern chat UI
  flutter_riverpod: ^2.x
  flutter_animate: ^4.x
```

### Sample dependencies (Path A)

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_webrtc: ^0.12.x
  livekit_client: ^2.x               # optional, for group calls via self-hosted LiveKit
  supabase_flutter: ^2.x             # or firebase_* 
  flutter_chat_ui: ^1.x
  google_mlkit_selfie_segmentation: ^0.x
  flutter_riverpod: ^2.x
```

---

## 11. Sources / References

**Audio noise suppression**
- Krisp — noise‑cancelling apps comparison (2026): https://krisp.ai/blog/best-noise-cancelling-app/
- Guideflow — 12 noise cancellation tools: https://www.guideflow.com/blog/noise-cancellation-software
- RNNoise explained + DeepFilterNet comparison: https://noisereducerai.com/blogs/rnnoise/
- Forasoft — Real‑time noise suppression (RNNoise vs DeepFilterNet vs Krisp): https://www.forasoft.com/learn/ai-for-video-engineering/articles-ai/real-time-noise-suppression-krisp-rnnoise-deepfilternet
- Android DeepFilterNet (JNI): https://github.com/KaleyraVideo/AndroidDeepFilterNet

**Call SDKs / WebRTC**
- flutter‑webrtc (Flutter WebRTC): https://github.com/flutter-webrtc/awesome-flutter-webrtc
- LiveKit pricing / self‑host comparison: https://checkthat.ai/brands/livekit/pricing , https://celloip.com/blog/livekit-vs-agora-vs-twilio-cost/
- Agora vs LiveKit vs Twilio vs Daily vs 100ms: https://www.forasoft.com/blog/article/video-call-app-agora-sdk-2026
- VideoSDK Flutter example (features incl. virtual background): https://github.com/videosdk-live/videosdk-rtc-flutter-sdk-example

**Noise filter inside managed SDKs**
- Stream Flutter Video — Noise Cancellation (Krisp): https://getstream.io/video/docs/flutter/guides/noise-cancellation
- ZEGOCLOUD Express Audio/Video API (ANS/AEC/AGC/beauty/denoise): https://docs.zegocloud.com/article/3559
- ZEGOCLOUD Express changelog (AI NS, video denoise): https://pub.dev/packages/zego_express_engine/changelog

**Video filters / effects**
- Banuba Face AR SDK (Agora extension): https://prod.agora.io/en/extensions/banuba , https://github.com/Banuba/agora-plugin-filters-android
- DeepAR for Flutter: https://www.deepar.ai/blog/deepar-for-flutter-the-journey

**Backend / messaging**
- Supabase vs Firebase (2026): https://anotherwrapper.com/blog/supabase-vs-firebase , https://tech-insider.org/supabase-vs-firebase-2026/
- Best backend for Flutter: https://voxturrlabs.com/blog/best-backend-for-flutter/
- Stream Chat Flutter SDK: https://github.com/GetStream/stream-chat-flutter
- ZEGOCLOUD voice/video call in Flutter tutorial: https://medium.com/@oriohac/how-to-implement-voice-and-video-call-features-in-your-flutter-app-with-zegocloud-ac8a17530c32
