/**
 * Hangout — Agora RTC token server (Cloudflare Worker).
 *
 * Generates Agora AccessToken2 ("007") RTC tokens on demand so the app can
 * run in "App ID + Token" (secured) mode with a different channel per call.
 *
 * Endpoint:
 *   GET /rtc-token?channel=<channelName>&uid=<uid>&expire=<seconds>
 *     channel  (required)  Agora channel name (1-64 chars)
 *     uid      (optional)  integer uid, default 0 (= any uid)
 *     expire   (optional)  token lifetime in seconds, default 3600, max 86400
 *
 * Response: { "token": "007...", "appId": "...", "channel": "...",
 *             "uid": "0", "expireAt": 1730000000 }
 *
 * Secrets (set with `wrangler secret put <NAME>`):
 *   AGORA_APP_ID           your Agora App ID
 *   AGORA_APP_CERTIFICATE  your Agora Primary Certificate
 */

const VERSION = '007';
const SERVICE_TYPE_RTC = 1;

// RTC privileges (AccessToken2)
const PRIV_JOIN_CHANNEL = 1;
const PRIV_PUBLISH_AUDIO = 2;
const PRIV_PUBLISH_VIDEO = 3;
const PRIV_PUBLISH_DATA = 4;

/* ------------------------------------------------------------------ */
/* Binary packing (little-endian), mirrors Agora's official ByteBuf.  */
/* ------------------------------------------------------------------ */

class ByteBuf {
  constructor() {
    this.chunks = [];
  }
  putUint16(v) {
    const b = new Uint8Array(2);
    new DataView(b.buffer).setUint16(0, v, true);
    this.chunks.push(b);
    return this;
  }
  putUint32(v) {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setUint32(0, v >>> 0, true);
    this.chunks.push(b);
    return this;
  }
  putBytes(bytes) {
    this.putUint16(bytes.length);
    this.chunks.push(bytes);
    return this;
  }
  putString(s) {
    return this.putBytes(new TextEncoder().encode(s));
  }
  pack() {
    const len = this.chunks.reduce((a, c) => a + c.length, 0);
    const out = new Uint8Array(len);
    let o = 0;
    for (const c of this.chunks) {
      out.set(c, o);
      o += c.length;
    }
    return out;
  }
}

function concatBytes(...arrays) {
  const len = arrays.reduce((a, c) => a + c.length, 0);
  const out = new Uint8Array(len);
  let o = 0;
  for (const a of arrays) {
    out.set(a, o);
    o += a.length;
  }
  return out;
}

async function hmacSha256(keyBytes, msgBytes) {
  const key = await crypto.subtle.importKey(
    'raw',
    keyBytes,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, msgBytes));
}

/** zlib-deflate (RFC 1950), as required by AccessToken2. */
async function zlibDeflate(data) {
  const stream = new Blob([data]).stream().pipeThrough(new CompressionStream('deflate'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function base64Encode(bytes) {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

/* ------------------------------------------------------------------ */
/* AccessToken2 build                                                  */
/* ------------------------------------------------------------------ */

async function buildRtcToken({ appId, appCert, channel, uid, expire }) {
  const issueTs = Math.floor(Date.now() / 1000);
  const salt = Math.floor(Math.random() * 99999999) + 1;
  const uidStr = uid === 0 ? '' : String(uid);
  const enc = new TextEncoder();

  // RTC service: type + privileges map + channel + uid
  const service = new ByteBuf()
    .putUint16(SERVICE_TYPE_RTC)
    .putUint16(4) // number of privileges
    .putUint16(PRIV_JOIN_CHANNEL).putUint32(expire)
    .putUint16(PRIV_PUBLISH_AUDIO).putUint32(expire)
    .putUint16(PRIV_PUBLISH_VIDEO).putUint32(expire)
    .putUint16(PRIV_PUBLISH_DATA).putUint32(expire)
    .putString(channel)
    .putString(uidStr)
    .pack();

  const signingInfo = concatBytes(
    new ByteBuf()
      .putString(appId)
      .putUint32(issueTs)
      .putUint32(expire)
      .putUint32(salt)
      .putUint16(1) // number of services
      .pack(),
    service,
  );

  // signing key = HMAC(salt, HMAC(issueTs, appCertificate))
  const k1 = await hmacSha256(new ByteBuf().putUint32(issueTs).pack(), enc.encode(appCert));
  const signingKey = await hmacSha256(new ByteBuf().putUint32(salt).pack(), k1);
  const signature = await hmacSha256(signingKey, signingInfo);

  const content = concatBytes(new ByteBuf().putBytes(signature).pack(), signingInfo);
  const compressed = await zlibDeflate(content);
  return VERSION + base64Encode(compressed);
}

/* ------------------------------------------------------------------ */
/* HTTP handler                                                        */
/* ------------------------------------------------------------------ */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    const url = new URL(request.url);
    if (url.pathname !== '/rtc-token') {
      return json({ error: 'Not found. Use GET /rtc-token?channel=...' }, 404);
    }

    const appId = env.AGORA_APP_ID;
    const appCert = env.AGORA_APP_CERTIFICATE;
    if (!appId || !appCert) {
      return json(
        { error: 'Server misconfigured: set AGORA_APP_ID and AGORA_APP_CERTIFICATE secrets.' },
        500,
      );
    }

    const channel = url.searchParams.get('channel') || '';
    if (!channel || channel.length > 64) {
      return json({ error: 'Missing or invalid "channel" query parameter.' }, 400);
    }

    const uid = Math.max(0, parseInt(url.searchParams.get('uid') || '0', 10) || 0);
    const expire = Math.min(
      86400,
      Math.max(60, parseInt(url.searchParams.get('expire') || '3600', 10) || 3600),
    );

    try {
      const token = await buildRtcToken({ appId, appCert, channel, uid, expire });
      return json({
        token,
        appId,
        channel,
        uid: String(uid),
        expireAt: Math.floor(Date.now() / 1000) + expire,
      });
    } catch (e) {
      return json({ error: `Token generation failed: ${e.message}` }, 500);
    }
  },
};
