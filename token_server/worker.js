/**
 * Hangout — Cloudflare Worker
 *
 * Serves TWO jobs from one free worker:
 *
 * 1) GET  /rtc-token?channel=<channelName>&uid=<uid>&expire=<seconds>
 *        Agora AccessToken2 ("007") RTC tokens for secured call mode.
 *
 * 2) POST /push/call      — send an incoming-call FCM push
 * 3) POST /push/message   — send a new-message FCM push
 *
 * Both push endpoints talk to Firebase Cloud Messaging (free, unlimited).
 * They are 100% serverless on Cloudflare's free tier (100k req/day).
 *
 * Secrets (set with `npx wrangler secret put <NAME>`):
 *   AGORA_APP_ID           your Agora App ID
 *   AGORA_APP_CERTIFICATE  your Agora Primary Certificate
 *   FCM_SERVER_KEY         your Firebase Cloud Messaging server key
 *                          (Firebase Console → Project settings →
 *                           Cloud Messaging → Cloud Messaging API (Legacy)
 *                           → Server key — available on the FREE Spark plan)
 *
 * Deploy: npx wrangler deploy
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
/* FCM push helpers                                                    */
/* ------------------------------------------------------------------ */

/** Sends a data-only push via the free FCM legacy HTTP API. */
async function sendFcmPush(env, data) {
  if (!env.FCM_SERVER_KEY) {
    throw new Error('FCM_SERVER_KEY secret not set. See token_server/worker.js header.');
  }
  const res = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      Authorization: `key=${env.FCM_SERVER_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      to: data.token,
      priority: 'high',
      // Data-only (NO "notification" key) so Android wakes the app and the
      // Flutter background handler runs even when the app is killed.
      data: data.payload,
    }),
  });
  const body = await res.text();
  if (!res.ok) {
    throw new Error(`FCM returned ${res.status}: ${body}`);
  }
  return body;
}

/* ------------------------------------------------------------------ */
/* HTTP handler                                                        */
/* ------------------------------------------------------------------ */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

async function readJson(request) {
  try {
    return await request.json();
  } catch (e) {
    throw new Error('Invalid JSON body.');
  }
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname;

    // ── 1. Agora RTC token ──────────────────────────────────────────
    if (path === '/rtc-token' && request.method === 'GET') {
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
    }

    // ── 2. Incoming-call push ───────────────────────────────────────
    if (path === '/push/call' && request.method === 'POST') {
      let body;
      try {
        body = await readJson(request);
      } catch (e) {
        return json({ error: e.message }, 400);
      }

      const token = body.token;
      if (!token) return json({ error: 'Missing "token" (callee FCM token).' }, 400);

      try {
        await sendFcmPush(env, {
          token,
          payload: {
            type: 'incoming_call',
            callId: String(body.callId || ''),
            channelName: String(body.channelName || ''),
            callerId: String(body.callerId || ''),
            callerName: String(body.callerName || 'Someone'),
            isVideo: body.isVideo ? 'true' : 'false',
          },
        });
        return json({ ok: true });
      } catch (e) {
        return json({ error: `Push failed: ${e.message}` }, 502);
      }
    }

    // ── 3. New-message push ─────────────────────────────────────────
    if (path === '/push/message' && request.method === 'POST') {
      let body;
      try {
        body = await readJson(request);
      } catch (e) {
        return json({ error: e.message }, 400);
      }

      const token = body.token;
      if (!token) return json({ error: 'Missing "token" (recipient FCM token).' }, 400);

      try {
        await sendFcmPush(env, {
          token,
          payload: {
            type: 'message',
            chatId: String(body.chatId || ''),
            senderId: String(body.senderId || ''),
            senderName: String(body.senderName || 'Someone'),
            text: String(body.text || ''),
          },
        });
        return json({ ok: true });
      } catch (e) {
        return json({ error: `Push failed: ${e.message}` }, 502);
      }
    }

    return json({ error: 'Not found. Use GET /rtc-token, POST /push/call or POST /push/message.' }, 404);
  },
};
