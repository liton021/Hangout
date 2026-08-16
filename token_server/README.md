# Hangout Token + Push Server (Cloudflare Worker)

One Worker, two jobs — both **free tier, no billing**:

1. **Agora RTC tokens** (AccessToken2 / "007") — the app runs in
   "App ID + Token (secured) mode" with a different channel per call.
2. **FCM-free push/signaling** — each device keeps a WebSocket open to the
   Worker; when someone messages or calls you, the event is forwarded to your
   device and the app raises a local notification itself. No Firebase Cloud
   Messaging, no Google Cloud Run, no service account, no billing.

## Deploy (one time, ~5 minutes)

1. Create a free Cloudflare account at https://dash.cloudflare.com/sign-up
   (no credit card needed).

2. Install Node.js if you don't have it, then from this `token_server/` folder:

   ```bash
   npx wrangler login          # opens browser, authorize
   npx wrangler deploy         # deploys worker + Durable Object ("PushRoom")
   ```

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
   (`_tokenServerUrl` **and** `_pushServerUrl`), or override with
   `--dart-define=TOKEN_SERVER_URL=...` / `--dart-define=PUSH_SERVER_URL=...`.
   Rebuild the app. Done.

## Test it

```bash
# Agora tokens:
curl "https://hangout-token-server.<your-subdomain>.workers.dev/rtc-token?channel=test123"
# → JSON with a token starting with "007"
```

Push endpoints can't be tested with curl alone (they require a signed
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

## Security notes

- The Agora App Certificate lives ONLY in Cloudflare secrets — never in the app.
- Push endpoints are authenticated: only a signed-in Hangout user (with a
  valid Firebase ID token) can connect a mailbox or send events, and senders
  can only address events, never impersonate a recipient.
- `FIREBASE_PROJECT_ID` (set in `wrangler.toml`) is not secret — it only tells
  the token verifier which project's tokens to accept.
- Free tier: 100,000 requests/day including WebSocket messages + Durable
  Objects free tier — plenty for a small app.
