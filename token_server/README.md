# Hangout Token + Push Server (Cloudflare Worker)

One Worker, three jobs — all **free tier, no billing**:

1. **Agora RTC tokens** (AccessToken2 / "007") — the app runs in
   "App ID + Token (secured) mode" with a different channel per call.
2. **FCM-free push/signaling** — each device keeps a WebSocket open to the
   Worker; when someone messages or calls you, the event is forwarded to your
   device and the app raises a local notification itself. No Firebase Cloud
   Messaging, no Google Cloud Run, no service account, no billing.
3. **Profile pictures** — the app uploads a cropped, compressed avatar and
   the Worker stores it and serves it back on a permanent, cacheable URL.
   Storage is **Workers KV by default (no credit card)** and switches to
   **R2** automatically if you bind a bucket.

> **Deploying from the Cloudflare dashboard instead of the CLI?** Then
> `wrangler.toml` is ignored and you must add the KV binding in the
> dashboard — see **PART 2B** in [`SETUP_GUIDE.md`](./SETUP_GUIDE.md).
> A missing binding is what makes `/` report
> `"avatarStorage":"not configured"`.
>
> ⚠️ **Dashboard deploys also need two more things that `wrangler.toml`
> would otherwise provide:** the `FIREBASE_PROJECT_ID` **variable**
> (Settings → Variables and Secrets; without it every authed endpoint —
> avatars, voice notes, push — returns `401 Unauthorized`) and the
> `PUSH_ROOM` **Durable Object binding** (Settings → Bindings; without it
> `/ws` crashes with Cloudflare Error 1101). See **Step 5** and **Step 5B**
> in [`SETUP_GUIDE.md`](./SETUP_GUIDE.md). After deploying, verify with the
> self-check at the worker root `/` — all `config.*Configured` fields must
> read `true`.

## Deploy (one time, ~5 minutes)

1. Create a free Cloudflare account at https://dash.cloudflare.com/sign-up
   (no credit card needed).

2. Install Node.js if you don't have it, then from this `token_server/` folder,
   sign in and get your avatar storage namespace ready:

   ```bash
   npx wrangler login                        # opens browser, authorize
   npx wrangler kv namespace list            # find the id of your existing
                                             # "hangout-avatars" namespace…
   ```

   …and paste that id into the `[[kv_namespaces]]` block in `wrangler.toml`
   (it ships with a `PASTE_YOUR_KV_NAMESPACE_ID_HERE` placeholder). If you
   don't have a namespace yet:

   ```bash
   npx wrangler kv namespace create AVATARS_KV   # prints an id — paste it too
   ```

   Then deploy:

   ```bash
   npx wrangler deploy         # worker + Durable Object ("PushRoom") + KV
   ```

   The `[vars] FIREBASE_PROJECT_ID` in `wrangler.toml` deploys with it — the
   value must match the `project_id` in
   `hangout_app/android/app/google-services.json` (here: `litonsgembd`).
   `npx wrangler secret put`-style values are not needed for it; it's a plain
   variable.

   The `[exports.PushRoom]` block in `wrangler.toml` makes this deploy
   **create the Durable Object namespace automatically** (SQLite backend) —
   there is nothing to set up in the dashboard, and the dashboard's Durable
   Objects page will correctly say "no namespaces" until this deploy runs.

3. Set the two secrets (values from https://console.agora.io → your project):

   ```bash
   npx wrangler secret put AGORA_APP_ID            # paste App ID
   npx wrangler secret put AGORA_APP_CERTIFICATE   # paste Primary Certificate
   ```

4. Wrangler prints your worker URL, e.g.:

   ```
   https://hangout-token-server.<your-subdomain>.workers.dev
   ```

5. Paste that URL into `hangout_app/lib/config/app_config.dart`
   (`_tokenServerUrl`, `_pushServerUrl` **and** `_avatarServerUrl`), or
   override with `--dart-define=TOKEN_SERVER_URL=...` /
   `--dart-define=PUSH_SERVER_URL=...` / `--dart-define=AVATAR_SERVER_URL=...`.
   Rebuild the app. Done.

6. **Verify the deployment** — open the worker root in a browser:

   ```
   https://hangout-token-server.<your-subdomain>.workers.dev/
   ```

   `config.firebaseProjectIdConfigured`, `config.pushRoomConfigured` and
   `config.avatarStorageConfigured` must all be `true`, or the app will
   show "session expired" / "server missing FIREBASE_PROJECT_ID" errors on
   profile-picture and voice-message uploads even though the user is signed
   in fine.

## Test it

```bash
# Agora tokens:
curl "https://hangout-token-server.<your-subdomain>.workers.dev/rtc-token?channel=test123"
# → JSON with a token starting with "007"
```

```bash
# Avatar storage wired up? The root endpoint reports the active backend:
curl "https://hangout-token-server.<your-subdomain>.workers.dev/"
# → "avatarStorage":"kv"  (or "r2", or "not configured")
```

Push and avatar upload endpoints can't be tested with curl alone (they require a signed
Firebase ID token) — test end-to-end from the app: background one device and
send it a message/call from another.

## API

### `GET /rtc-token?channel=<name>&uid=<uid>&expire=<seconds>`

| param   | required | default | notes                          |
|---------|----------|---------|--------------------------------|
| channel | yes      | —       | 1–64 chars                     |
| uid     | no       | 0       | 0 = token valid for any uid    |
| expire  | no       | 3600    | seconds, 60–86400              |

### `GET /ws?uid=<uid>` — device mailbox (WebSocket)

- Requires header `Authorization: Bearer <firebase-id-token>`; the token is
  verified against Google's public certs (RS256, cached ~6h) and must match
  `uid`. No Firebase console changes needed — this is pure JWT verification.
- Multiple devices per user are supported; offline events are buffered in the
  Durable Object for ~10 minutes (max 25).

### `POST /send` — push an event to a user

- Requires the same `Authorization: Bearer <firebase-id-token>` header.
- Body: `{ "to": "<uid>", "event": "call_invite" | "call_cancelled" |
  "call_rejected" | "new_message", "payload": { ... } }` (payload ≤ 16 KB).
- Rate limit: 120 sends/minute per user.

### `POST /avatar` — upload your profile picture

- Requires `Authorization: Bearer <firebase-id-token>`.
- Body: **raw image bytes** (not multipart), with
  `Content-Type: image/jpeg`, `image/png` or `image/webp`.
- Max 512 KB. The app already crops to 512×512 and JPEG-encodes (~40–80 KB),
  so this is only a safety net.
- The file type is verified from the actual magic bytes, not the header, so a
  script or SVG cannot be smuggled in as an "image".
- Replaces any previous picture (one avatar per user — no orphaned objects).
- Returns `{ "url": "https://…/avatar/<uid>/<hash>.jpg", "storage": "kv"|"r2" }`.
  The app saves that URL to `users/{uid}.avatarUrl` in Firestore.
- Rate limit: 6 uploads/minute per user.

### `DELETE /avatar` — remove your profile picture

- Requires the same auth header. Deletes every object under `avatars/<uid>/`.

### `GET /avatar/<uid>/<hash>.<ext>` — public image

- **No auth** — this URL is loaded directly by `Image.network` on every
  device, so it has to be publicly readable (the same as any CDN avatar).
- URLs are content-addressed (the hash is of the bytes), so the response is
  served `Cache-Control: public, max-age=31536000, immutable` with an ETag.
  Changing your picture produces a *new* URL, so caches never go stale.

### `POST /voice` — upload a voice note

- Requires `Authorization: Bearer <firebase-id-token>`.
- Body: **raw audio bytes**, with `Content-Type: audio/mp4` (what the app
  sends), `audio/aac`, `audio/mpeg` or `audio/ogg`.
- Max 1 MB. The app records mono AAC at 32 kbps and stops at 2 minutes, so a
  worst-case note is around 480 KB.
- As with images, the format is verified from the magic bytes, not the header.
- Returns `{ "url": "https://…/voice/<uid>/<hash>.m4a", "expiresInDays": 30 }`.
  The app stores that URL on the Firestore message document.
- Rate limit: 30 uploads/minute per user.
- **Notes are not deleted on re-upload** — each one is its own message. Total
  storage is bounded by the 30-day TTL instead.

### `GET /voice/<uid>/<hash>.<ext>` — public audio

- **No auth**, for the same reason as avatars: the audio player fetches this
  URL directly and cannot attach headers. The URL is unguessable (a content
  hash) and expires.
- Returns `404 { "error": "This voice message has expired." }` once the note
  ages out, which the app renders as a disabled "Unavailable" bubble.

## Why voice notes expire after 30 days

This is the single design decision that makes voice messaging viable on a
free tier. Without a TTL, storage grows forever and the 1 GB KV limit is a
matter of time; with it, usage reaches a steady state:

| | Storage per note | Sustainable rate (1 GB KV) |
|---|---|---|
| 30-second note | ~120 KB | ~290 notes/day, indefinitely |
| 60-second note | ~240 KB | ~145 notes/day, indefinitely |

On KV the expiry is native (`expirationTtl`). R2 has no per-object TTL, so
the expiry is written as metadata and enforced lazily on read — an expired
object is deleted the first time anyone asks for it.

Change the window by editing `VOICE_TTL_SECONDS` in `worker.js`.

## Storage: KV vs R2

Avatars (`avatars/…`) and voice notes (`voice/…`) share one namespace/bucket —
they are just different key prefixes, so there is nothing extra to set up for
voice once avatars work.

| | Workers KV (default) | R2 (optional) |
|---|---|---|
| Credit card | **Not required** | **Required** to enable, even on the free tier |
| Free storage | 1 GB (~15,000 avatars at 65 KB) | 10 GB |
| Free writes | 1,000/day | 1M Class A ops/month |
| Free reads | 100,000/day | 10M Class B ops/month |
| Object TTL | Native (`expirationTtl`) | Emulated on read |

On the free KV tier the **1,000 writes/day** limit binds before storage does:
that is the real ceiling on how many voice notes and avatar changes can be
uploaded per day across all users. Reads (playback) are far more generous at
100,000/day.

KV is the default precisely so the whole feature works with no billing setup.
To move to R2 later, create the bucket, uncomment the `[[r2_buckets]]` block
in `wrangler.toml`, and redeploy:

```bash
npx wrangler r2 bucket create hangout-avatars
npx wrangler deploy
```

The Worker prefers R2 the moment that binding exists — **no app change and no
rebuild required**. Already-uploaded KV avatars keep working only if you keep
the KV binding in place, so leave both bound during a migration.

## Security notes

- The Agora App Certificate lives ONLY in Cloudflare secrets — never in the app.
- Push endpoints are authenticated: only a signed-in Hangout user (with a
  valid Firebase ID token) can connect a mailbox or send events, and senders
  can only address events, never impersonate a recipient.
- `FIREBASE_PROJECT_ID` (set in `wrangler.toml`) is not secret — it only tells
  the token verifier which project's tokens to accept.
- Avatar uploads are authenticated and always keyed by the *token's* uid, so
  a user can only ever overwrite or delete their own picture — the uid is
  never taken from the request body or query string.
- Uploaded bytes are sniffed for a real JPEG/PNG/WebP signature and served
  with `X-Content-Type-Options: nosniff`, so a stored file cannot be
  interpreted as HTML/SVG script by a browser.
- Free tier: 100,000 requests/day including WebSocket messages + Durable
  Objects free tier — plenty for a small app.
