# 🖱️ Deploy the token server from GitHub — no terminal needed

The Cloudflare dashboard **cannot** create Durable Object namespaces —
that's done automatically by `wrangler deploy`. If you don't want to use a
terminal, this guide gets you the same result with GitHub Actions, all in
your browser. The workflow also **finds or creates the KV namespace
automatically** (via `token_server/scripts/ensure-kv.mjs`, which is already
in the repo), so you never have to look up an id.

---

## Step 1 — Create the workflow file (one-time, ~2 minutes)

1. Open your repo on GitHub: `https://github.com/liton021/Hangout`
2. Click the **Actions** tab.
3. Click **New workflow** → **set up a workflow yourself** (or "configure").
4. GitHub opens a file editor for `.github/workflows/main.yml`.
   - Change the file name (top field) to:
     ```
     deploy-token-server.yml
     ```
   - Delete the starter content and paste the entire block below.
5. Click **Commit changes** → **Commit changes** (to your `arena/01a00e96-hangout`
   branch or `main` — either works).

```yaml
name: Deploy token server

# One-click deploy — no terminal needed:
#   1. Actions tab → "Deploy token server" → "Run workflow"
# Or it also deploys automatically on every push that touches token_server/.
#
# This is the ONLY way to create the PUSH_ROOM Durable Object namespace —
# the Cloudflare dashboard cannot create namespaces; `wrangler deploy` can.
# The same deploy also applies FIREBASE_PROJECT_ID and the AVATARS_KV
# binding (the script finds or creates the KV namespace automatically).
#
# Required repo secrets (Settings → Secrets and variables → Actions):
#   CLOUDFLARE_API_TOKEN   — dash.cloudflare.com → My Profile →
#                            API Tokens → Create Token → "Edit Cloudflare
#                            Workers" template
#   CLOUDFLARE_ACCOUNT_ID  — OPTIONAL. Your Account ID is the hex string in
#                            the dashboard URL after dash.cloudflare.com/
#                            (it is NOT your email). Auto-detected when the
#                            token has exactly one account; add it anyway if
#                            you can find it (see guide Step 2).

on:
  workflow_dispatch:        # the "Run workflow" button
  push:
    branches: [main, 'arena/**']
    paths: ['token_server/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 22        # wrangler requires Node.js v22+ (v20 fails)

      - name: Ensure AVATARS_KV namespace exists and patch wrangler.toml
        run: node token_server/scripts/ensure-kv.mjs
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}

      - name: Deploy with wrangler (creates PUSH_ROOM namespace)
        working-directory: token_server
        run: npx --yes wrangler@latest deploy
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}

      - name: Verify deployment self-check
        run: |
          URL="https://hangout-token-server.onelitonbd.workers.dev/"
          BODY=$(curl -fsS "$URL")
          echo "$BODY"
          echo "$BODY" | grep -q '"pushRoomConfigured":true' || {
            echo "::error::pushRoomConfigured is not true — check the deploy log."
            exit 1
          }
          echo "$BODY" | grep -q '"firebaseProjectIdConfigured":true' || {
            echo "::error::firebaseProjectIdConfigured is not true."
            exit 1
          }
          echo "Deployment verified OK ✅"
```

---

## Step 2 — Create the two Cloudflare API credentials (browser)

### Cloudflare API token
1. Go to https://dash.cloudflare.com and log in.
2. Top right → **My Profile** → **API Tokens** → **Create Token**.
3. Find the **"Edit Cloudflare Workers"** template → **Use template**.
4. Leave the permissions as they are → **Continue to summary** → **Create
   Token**.
5. **Copy the token** — it is shown only once.

### Account ID (now optional — but good to add)

Your Account ID is **not your email** — it's a 32-character hex string (letters
and numbers, e.g. `8f3c...a91b`). Three ways to find it:

1. **Address bar (easiest):** log in at https://dash.cloudflare.com and look
   at the URL — it reads
   `https://dash.cloudflare.com/<ACCOUNT_ID>/...`
   The part right after `dash.cloudflare.com/` is your Account ID. Copy it
   up to the next `/`.
2. **API Tokens page:** open https://dash.cloudflare.com/profile/api-tokens —
   the same hex string appears in the URL there too.
3. **Workers & Pages page:** https://dash.cloudflare.com → **Workers & Pages**
   → on the right side under *Resources* there's an **Account ID** field with
   a copy button. (If you don't see it, use method 1 or 2.)

If you skip it, the workflow can usually **auto-detect** the account from your
API token (when the token belongs to exactly one account). Adding it is
recommended but not required.

---

## Step 3 — Add them as GitHub secrets (browser)

1. Your repo → **Settings** → **Secrets and variables** → **Actions**.
2. **New repository secret**:
   - Name: `CLOUDFLARE_API_TOKEN` — value: the API token. **This one is
     required.** Add it first.
   - Optional: Name: `CLOUDFLARE_ACCOUNT_ID` — value: the account id from
     Step 2. If you can't find it, skip it — the workflow auto-detects it
     from the token.

---

## Step 4 — Run it (browser)

1. Repo → **Actions** tab → **"Deploy token server"** (left sidebar).
2. Click **Run workflow** → pick your branch → **Run workflow**.
3. Click the run to watch the steps. The last step prints
   `Deployment verified OK ✅` when everything is configured
   (`pushRoomConfigured`, `firebaseProjectIdConfigured` and
   `avatarStorageConfigured` all `true`).

After the first run, the workflow also **auto-deploys on every push** that
changes anything in the `token_server/` folder.

---

## What it does for you

| Problem you had | Solved by |
|---|---|
| "no Durable Objects namespaces" | `wrangler deploy` creates `PushRoom` (SQLite) automatically |
| "server missing FIREBASE_PROJECT_ID" (avatar/voice 401) | `[vars]` in `wrangler.toml` deploys with the worker |
| `PASTE_YOUR_KV_NAMESPACE_ID_HERE` placeholder | `ensure-kv.mjs` finds or creates the namespace and patches the file |

> Your Agora secrets (`AGORA_APP_ID`, `AGORA_APP_CERTIFICATE`) live on the
> Worker and are **not** touched by this deploy. If `/rtc-token` ever says
> "Server misconfigured", re-add them in the dashboard (Settings →
> Variables and Secrets → Add → Secret) — that part *is* doable from the
> dashboard.
