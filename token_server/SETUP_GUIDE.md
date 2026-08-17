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

### Step 5 — Get your worker URL
On the worker overview page you'll see something like:

```
https://hangout-token-server.YOURNAME.workers.dev
```

If the URL is disabled, go to **Settings → Domains & Routes** and enable
the `workers.dev` route.

### Step 6 — Test it (don't skip!)
Open in your browser:

```
https://hangout-token-server.YOURNAME.workers.dev/rtc-token?channel=test123
```

| Result | Meaning |
|---|---|
| JSON with `"token": "007..."` | ✅ Working! |
| `"Server misconfigured"` | Secrets missing or misnamed — redo Step 4 |
| `"Not found"` | You forgot `/rtc-token` in the URL |

---

## 🖼️ PART 2B — Enable profile pictures (KV storage, no credit card)

Profile pictures need somewhere to live. This uses **Workers KV**, which is
free and — unlike R2 — does **not** require a credit card.

> **Do I need this?** Only for profile pictures. Calls, chat and
> notifications work fine without it. If you skip it, `/` reports
> `"avatarStorage":"not configured"` and photo uploads show a friendly
> "photo storage is not set up" message in the app.

### Step 1 — Create the KV namespace
1. In the Cloudflare dashboard sidebar, go to **Storage & Databases** →
   **KV** (older UI: **Workers & Pages** → **KV**).
2. Click **Create instance** / **Create namespace**.
3. Name it `hangout-avatars` and click **Create**.

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

| `avatarStorage` says | Meaning |
|---|---|
| `"kv"` | ✅ Working — profile pictures are ready |
| `"not configured"` | Binding missing or misnamed — redo Step 2 |
| `"r2"` | An R2 bucket is bound; it takes priority over KV (also fine) |

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
| Agora error `110` / `109` | Bad/expired token | Re-test the worker URL (Part 2 Step 6) |
| "Could not fetch call token" | Wrong `_tokenServerUrl` / no internet | Check URL: https, no trailing slash, no typos |
| Agora error `101` | Wrong App ID | App ID in the app must match the certificate's project |
| Call joins, no audio/video | Permissions denied | Enable mic + camera in Android settings |

## 🔧 Troubleshooting profile pictures

| Symptom | Cause | Fix |
|---|---|---|
| `"avatarStorage":"not configured"` | KV namespace not bound to the Worker | Do Part 2B Step 2 — creating the namespace alone is not enough |
| "Photo storage is not set up" in the app | Same as above (the app is reporting the Worker's 501) | Do Part 2B Step 2 |
| Binding added but still "not configured" | Variable name typo | It must be exactly `AVATARS_KV` (uppercase, underscore) |
| Upload says "session expired" | Firebase ID token rejected | Sign out and back in; check `FIREBASE_PROJECT_ID` matches your project |
| "Too many uploads" | Rate limit (6/min per user) | Wait a minute |

## ℹ️ Notes

- Free tier = 100,000 requests/day. One request per call join — more than
  enough.
- Tokens expire after 1 hour, but the app renews them automatically during
  long calls (`onTokenPrivilegeWillExpire` → fetch → `renewToken`).
- Later hardening (optional): require a Firebase Auth ID token in the
  request so only logged-in users can obtain call tokens.
