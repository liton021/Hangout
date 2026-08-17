# 🚀 Complete Setup Guide — Agora + Cloudflare (No Terminal Needed)

This guide sets up secure "App ID + Token" calling for Hangout entirely from
your web browser. Takes about 10 minutes.

---

## 🅰️ PART 1 — Agora: get your App ID and App Certificate

1. Go to **https://console.agora.io** and log in.
2. Left sidebar → **Projects**. Use your existing project (secured mode /
   "App ID + Token" is exactly what we want).
3. **Copy the App ID** — click the copy icon in the *App ID* column.
   Save it in a notepad.
4. **Copy the App Certificate**:
   - Click the **pencil (edit) icon** on the project.
   - Find the **Primary Certificate** section.
   - Click the **copy icon** under it. Save it in the notepad.

> ⚠️ The App Certificate is a SECRET. It goes only into Cloudflare —
> never into the app code, never into GitHub.

---

## ☁️ PART 2 — Cloudflare: deploy the token server from the dashboard

### Step 1 — Create a free account
- Go to **https://dash.cloudflare.com/sign-up**
- Sign up with email, verify the email. Free plan, no credit card.

### Step 2 — Create the Worker
1. In the dashboard sidebar click **Compute (Workers)**
   (older UI: **Workers & Pages**).
2. Click **Create** → choose **Create Worker** ("Hello World" starter).
3. Name it: `hangout-token-server` — this becomes part of your URL.
4. Click **Deploy**. (It deploys a placeholder hello-world first — normal.)

### Step 3 — Paste the real code
1. Click **Edit code**.
2. In the browser editor, **select all** the hello-world code and delete it.
3. Open `token_server/worker.js` from this repository, copy the ENTIRE
   file, and paste it into the editor.
4. Click **Deploy** (top-right).

### Step 4 — Add the two secrets
1. Go back to the worker page → **Settings** tab → **Variables and Secrets**.
2. Click **Add**:
   - Type: **Secret**
   - Name: `AGORA_APP_ID`
   - Value: *(paste your App ID from Part 1)*
   - Click **Deploy**.
3. Click **Add** again:
   - Type: **Secret**
   - Name: `AGORA_APP_CERTIFICATE`
   - Value: *(paste your Primary Certificate from Part 1)*
   - Click **Deploy**.

> ⚠️ Names must be EXACTLY `AGORA_APP_ID` and `AGORA_APP_CERTIFICATE`
> (uppercase, with underscores).

### Step 5 — Add the Firebase project ID variable ⚠️ (the step people miss)

Profile pictures, voice messages, push notifications and even call tokens
can **all** fail with `401 Unauthorized` — and the app then shows
*"Your session expired. Sign in again."* — when this single variable is
missing. The Worker needs it to verify the app's Firebase ID token.

1. In the same **Settings → Variables and Secrets** screen, click **Add**.
2. Choose type **Variable** (not Secret — it is not sensitive).
3. **Name:** `FIREBASE_PROJECT_ID`
4. **Value:** your Firebase project ID. You can read it from
   `hangout_app/android/app/google-services.json` → `"project_id"`.
   (For this repo's app that is `litonsgembd`.)
5. Click **Deploy** (or **Save**).

> 🔍 **How to check it's missing:** open the Worker's URL in a browser and
> look at the `config` section of the JSON — a missing variable shows
> `"firebaseProjectIdConfigured": false`. A broken upload also returns
> `"errorCode": "server_missing_firebase_project_id"`.

### Step 5B — Provision the PUSH_ROOM Durable Object (for push/WebSocket signaling)

Background notifications (incoming calls, new-message heads-up) run over a
WebSocket that lives in a **Durable Object** named `PUSH_ROOM`.

⚠️ **You cannot create a Durable Object namespace from the dashboard.** If
you open the Durable Objects page you'll see *"Your account currently has no
Durable Objects namespaces"* — that's normal. Namespaces are created
**automatically when you deploy a Worker that exports a Durable Object
class**, so the correct path is to deploy with `wrangler` (below). This one
deploy does everything at once:

1. **Install Node.js** if you don't have it (https://nodejs.org).

2. From the `token_server/` folder, log in:

   ```bash
   npx wrangler login
   ```

   A browser opens asking you to authorize — click **Allow**.

3. **Put your real KV namespace id into `wrangler.toml`** — this is
   required, or the deploy fails / ships without avatar storage. If you
   already created the KV namespace in the dashboard (it's named
   `hangout-avatars`), find its id:

   ```bash
   npx wrangler kv namespace list
   ```

   Copy the `id` of `hangout-avatars` and paste it into `wrangler.toml` at
   the `[[kv_namespaces]]` block (replacing `PASTE_YOUR_KV_NAMESPACE_ID_HERE`).
   If you have no namespace yet, run
   `npx wrangler kv namespace create AVATARS_KV` and paste the printed id.

4. **Deploy** — this is the step that creates the namespace:

   ```bash
   npx wrangler deploy
   ```

   Wrangler provisions the `PushRoom` Durable Object namespace (SQLite
   backend — declared via `[exports.PushRoom]` in `wrangler.toml`), applies
   the `FIREBASE_PROJECT_ID` variable and the KV binding, and uploads the
   fixed worker code. The namespace then appears on the Durable Objects
   dashboard page.

5. Verify at the worker root — all three must be `true`:

   ```bash
   https://hangout-token-server.YOURNAME.workers.dev/
   ```

   → `config.pushRoomConfigured: true`

> What about the class name? You don't type it anywhere — `wrangler.toml`
> already pairs the binding (`PUSH_ROOM`) with the class (`PushRoom`) and
> the exports block (`[exports.PushRoom]`) declares the SQLite backend.
> The binding and exports names must match the class name in `worker.js`
> exactly — in this repo they already do.

> Your Agora secrets (`AGORA_APP_ID`, `AGORA_APP_CERTIFICATE`) were set in
> the dashboard and stay on the Worker across `wrangler deploy` — they are
> stored separately and are not touched. If `/rtc-token` ever reports
> "Server misconfigured" after a deploy, re-add them with
> `npx wrangler secret put AGORA_APP_ID` and
> `npx wrangler secret put AGORA_APP_CERTIFICATE`.

### Step 6 — Get your worker URL
On the worker overview page you'll see something like:

```
https://hangout-token-server.YOURNAME.workers.dev
```

If the URL is disabled, go to **Settings → Domains & Routes** and enable
the `workers.dev` route.

### Step 7 — Test it (don't skip!)
Open in your browser:

```text
https://hangout-token-server.YOURNAME.workers.dev/rtc-token?channel=test123
```

| Result | Meaning |
|---|---|
| JSON with `"token": "007..."` | ✅ Working! |
| `"Server misconfigured"` | Secrets missing or misnamed — redo Step 4 |
| `"Not found"` | You forgot `/rtc-token` in the URL |

Then open the worker root (this is the deployment self-check):

```text
https://hangout-token-server.YOURNAME.workers.dev/
```

| `config` field | Should read | If it says `false` |
|---|---|---|
| `firebaseProjectIdConfigured` | `true` | Redo Step 5 — the Firebase project ID variable is missing |
| `pushRoomConfigured` | `true` | Redo Step 5B — the PUSH_ROOM Durable Object isn't bound |
| `avatarStorageConfigured` | `true` | Redo Part 2B Step 2 — the KV binding is missing |
| `avatarStorage` / `voiceStorage` | `"kv"` (or `"r2"`) | Same as above |

All three must be `true` before profile pictures, voice messages and push
notifications will work.

---

## 🖼️ PART 2B — Enable profile pictures + voice messages (KV, no credit card)

Profile pictures and voice messages need somewhere to live. Both use the
**same** Workers KV namespace, which is free and — unlike R2 — does **not**
require a credit card. Set this up once and both features work.

> **Do I need this?** Only for profile pictures and voice messages. Calls,
> text chat and notifications work fine without it. If you skip it, `/`
> reports `"avatarStorage":"not configured"`, photo uploads show a friendly
> "photo storage is not set up" message, and the composer's mic button is
> hidden so there is no dead control.

### Step 1 — Create the KV namespace
1. In the Cloudflare dashboard sidebar, go to **Storage & Databases** →
   **KV** (older UI: **Workers & Pages** → **KV**).
2. Click **Create instance** / **Create namespace**.
3. Name it `hangout-avatars` and click **Create**. (It holds voice notes
   too — they just use a different key prefix.)

### Step 2 — Bind it to the Worker ⚠️ (the step people miss)
Creating the namespace is **not** enough — the Worker can't see it until you
bind it.

1. Go to **Compute (Workers)** → click **hangout-token-server**.
2. Open the **Settings** tab → **Bindings** → **Add binding**.
3. Choose **KV namespace**.
4. **Variable name:** `AVATARS_KV` — must be exactly this, uppercase with
   an underscore. This is the name the code looks for.
5. **KV namespace:** select `hangout-avatars` from the dropdown.
6. Click **Add binding** / **Deploy**.

### Step 3 — Verify
Open your worker URL in a browser:

```
https://hangout-token-server.YOURNAME.workers.dev/
```

| `avatarStorage` / `voiceStorage` says | Meaning |
|---|---|
| `"kv"` | ✅ Working — profile pictures **and voice messages** are ready |
| `"not configured"` | Binding missing or misnamed — redo Step 2 |
| `"r2"` | An R2 bucket is bound; it takes priority over KV (also fine) |

Both fields always report the same backend — one binding powers both.

> **Voice notes expire after 30 days.** That is deliberate: it keeps storage
> at a steady state so the free 1 GB tier never fills up. On the free plan the
> **1,000 KV writes/day** limit is the real ceiling (roughly 1,000 voice notes
> or avatar changes per day across all users). Adjust the window with
> `VOICE_TTL_SECONDS` in `worker.js`.

> **Note:** if you deploy from the dashboard, `wrangler.toml` is ignored —
> the dashboard is the source of truth for bindings. Only add the
> `[[kv_namespaces]]` block to `wrangler.toml` if you deploy with the
> `wrangler` CLI instead.

---

## 📱 PART 3 — Point the app at your token server

Edit `hangout_app/lib/config/app_config.dart`:

```dart
static const String _agoraAppId = 'YOUR_APP_ID_HERE';

static const String _tokenServerUrl =
    'https://hangout-token-server.YOURNAME.workers.dev';

// Same worker URL for push and profile pictures:
static const String _pushServerUrl =
    'https://hangout-token-server.YOURNAME.workers.dev';

static const String _avatarServerUrl =
    'https://hangout-token-server.YOURNAME.workers.dev';
```

Leave `_agoraToken = ''` unchanged. Commit → let CI build → install the
new APK → make a test call between two devices.

---

## 🔧 Troubleshooting calls

| Symptom | Cause | Fix |
|---|---|---|
| Agora error `110` / `109` | Bad/expired token | Re-test the worker URL (Part 2 Step 7) |
| "Could not fetch call token" | Wrong `_tokenServerUrl` / no internet | Check URL: https, no trailing slash, no typos |
| Agora error `101` | Wrong App ID | App ID in the app must match the certificate's project |
| Call joins, no audio/video | Permissions denied | Enable mic + camera in Android settings |

## 🔧 Troubleshooting profile pictures & voice messages

| Symptom | Cause | Fix |
|---|---|---|
| `"avatarStorage":"not configured"` | KV namespace not bound to the Worker | Do Part 2B Step 2 — creating the namespace alone is not enough |
| Mic button missing from the chat composer | `_voiceServerUrl` is empty in `app_config.dart` | Set it to your worker URL (Part 3) |
| "Voice messages are not set up on the server yet" | Worker deployed but no KV binding | Do Part 2B Step 2 |
| A voice note plays as "Unavailable" | It is older than 30 days and has expired | Expected — ask the sender to re-record |
| "Photo storage is not set up" in the app | Same as above (the app is reporting the Worker's 501) | Do Part 2B Step 2 |
| Binding added but still "not configured" | Variable name typo | It must be exactly `AVATARS_KV` (uppercase, underscore) |
| Upload shows "session expired, sign in again" | ⚠️ Almost always **not** a real session problem — the Worker is missing the `FIREBASE_PROJECT_ID` variable, so it rejects every ID token with 401 | Do **Step 5** (add the variable) and redeploy the Worker. Your session is fine — do NOT sign out |
| Voice message shows "Unauthorized: server missing FIREBASE_PROJECT_ID" | Same missing variable, surfaced raw by older app builds | Do **Step 5** and redeploy; then update the app (newer builds show a friendly message instead) |
| `/ws` (notifications) shows Cloudflare "Error 1101 — Worker threw exception" | `PUSH_ROOM` Durable Object not bound (or its migration never ran) | Do **Step 5B** and redeploy |
| Push/notifications never arrive | `pushRoomConfigured` is `false` in the `/` self-check | Do **Step 5B** and redeploy |
| "Too many uploads" | Rate limit (6/min per user) | Wait a minute |

> **After adding the variable or binding, always redeploy** (dashboard:
> **Deploy** button; CLI: `npx wrangler deploy`). Variables and bindings
> only take effect on the next deploy.

## ℹ️ Notes

- Free tier = 100,000 requests/day. One request per call join — more than
  enough.
- Tokens expire after 1 hour, but the app renews them automatically during
  long calls (`onTokenPrivilegeWillExpire` → fetch → `renewToken`).
- Later hardening (optional): require a Firebase Auth ID token in the
  request so only logged-in users can obtain call tokens.
