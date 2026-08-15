# Hangout Agora Token Server (Cloudflare Worker)

Generates Agora RTC tokens (AccessToken2 / "007") on demand so the app can run
in **App ID + Token (secured) mode** with a different channel per call.

## Deploy (one time, ~5 minutes)

1. Create a free Cloudflare account at https://dash.cloudflare.com/sign-up
   (no credit card needed).

2. Install Node.js if you don't have it, then from this `token_server/` folder:

   ```bash
   npx wrangler login          # opens browser, authorize
   npx wrangler deploy         # deploys the worker
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

5. Paste that URL into `hangout_app/lib/config/app_config.dart`:

   ```dart
   static const String _tokenServerUrl =
       'https://hangout-token-server.<your-subdomain>.workers.dev';
   ```

   Also set `_agoraAppId` to the same App ID. Rebuild the app. Done.

## Test it

```bash
curl "https://hangout-token-server.<your-subdomain>.workers.dev/rtc-token?channel=test123"
```

Should return JSON with a `token` starting with `007`.

## API

`GET /rtc-token?channel=<name>&uid=<uid>&expire=<seconds>`

| param   | required | default | notes                          |
|---------|----------|---------|--------------------------------|
| channel | yes      | —       | 1–64 chars                     |
| uid     | no       | 0       | 0 = token valid for any uid    |
| expire  | no       | 3600    | seconds, 60–86400              |

## Security notes

- The App Certificate lives ONLY in Cloudflare secrets — never in the app.
- Free tier: 100,000 requests/day (one request per call join — plenty).
- Optional hardening later: require a Firebase Auth ID token in the request
  and verify it in the worker, so only logged-in Hangout users can get tokens.
