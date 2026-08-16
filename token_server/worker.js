/**
 * Hangout — Agora RTC token server + FCM-free push/signaling (Cloudflare Worker).
 *
 * Part 1 — Agora tokens (unchanged):
 *   GET /rtc-token?channel=<channelName>&uid=<uid>&expire=<seconds>
 *   Generates Agora AccessToken2 ("007") RTC tokens so the app can run in
 *   "App ID + Token" (secured) mode with a different channel per call.
 *
 * Part 2 — Push notifications WITHOUT Firebase/FCM:
 *   The app keeps a persistent WebSocket to this Worker. When someone sends
 *   you a message or calls you, the sender's app POSTs to /send and the
 *   Worker forwards the event to your device over the WebSocket. The app
 *   then raises a local notification itself (heads-up for messages,
 *   full-screen-intent for incoming calls).
 *
 *   GET  /ws?uid=<uid>      (WebSocket upgrade, requires Firebase ID token)
 *   POST /send              body: { "to": "<uid>", "event": "call_invite" |
 *                             "call_cancelled" | "call_rejected" | "new_message",
 *                             "payload": { ... } }
 *
 * Auth: both endpoints require an `Authorization: Bearer <firebase-id-token>`
 * header. Tokens are verified against Google's public signing certs (RS256,
 * cached ~6h) — this needs NO Firebase service account, NO Cloud Messaging
 * API, NO billing, and NO extra console configuration. It only needs the
 * Firebase project id (set below via wrangler vars / env).
 *
 * Cost: runs on Cloudflare Workers free plan (100k requests/day incl.
 * WebSocket messages, Durable Objects free tier) — plenty for a small app.
 *
 * Secrets (set with `wrangler secret put <NAME>`):
 *   AGORA_APP_ID           your Agora App ID
 *   AGORA_APP_CERTIFICATE  your Agora Primary Certificate
 *
 * Vars (wrangler.toml `[vars]`, not secret):
 *   FIREBASE_PROJECT_ID    your Firebase project id (used only for verifying
 *                          the app's auth tokens — no Cloud APIs involved).
 */

import { DurableObject } from 'cloudflare:workers';

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
/* Firebase ID-token verification (free, no service account needed)   */
/* ------------------------------------------------------------------ */

const GOOGLE_CERTS_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
const CERTS_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours

let certsCache = null;
let certsCacheAt = 0;

async function googleCerts() {
  const now = Date.now();
  if (certsCache && now - certsCacheAt < CERTS_TTL_MS) return certsCache;
  const res = await fetch(GOOGLE_CERTS_URL);
  if (!res.ok) throw new Error(`failed to fetch Google certs (${res.status})`);
  certsCache = await res.json();
  certsCacheAt = now;
  return certsCache;
}

function base64UrlDecodeToBytes(str) {
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const padded = b64.padEnd(Math.ceil(b64.length / 4) * 4, '=');
  const bin = atob(padded);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

function base64UrlDecodeToText(str) {
  return new TextDecoder().decode(base64UrlDecodeToBytes(str));
}

function pemToBytes(pem) {
  // Handles any PEM block markers (CERTIFICATE, PUBLIC KEY, RSA PUBLIC KEY…).
  const b64 = pem.replace(/-----BEGIN [^-]+-----|-----END [^-]+-----|\s+/g, '');
  const bin = atob(b64);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

/**
 * Verifies a Firebase Auth ID token (RS256) against Google's public certs.
 * Returns the decoded claims (claims.sub === uid).
 */
async function verifyFirebaseIdToken(token, projectId) {
  if (!token) throw new Error('missing Bearer token');
  if (!projectId) throw new Error('server missing FIREBASE_PROJECT_ID');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('malformed token');

  const header = JSON.parse(base64UrlDecodeToText(parts[0]));
  if (header.alg !== 'RS256' || !header.kid) throw new Error('unsupported token algorithm');

  const payload = JSON.parse(base64UrlDecodeToText(parts[1]));
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp <= now) throw new Error('token expired');
  if (typeof payload.iat === 'number' && payload.iat > now + 300) {
    throw new Error('token issued in the future');
  }
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new Error('wrong issuer');
  }
  if (payload.aud !== projectId) throw new Error('wrong audience');

  const certs = await googleCerts();
  const pem = certs[header.kid];
  if (!pem) throw new Error('unknown signing key');

  const key = await crypto.subtle.importKey(
    'spki',
    pemToBytes(pem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );

  const signature = base64UrlDecodeToBytes(parts[2]);
  const data = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, signature, data);
  if (!valid) throw new Error('invalid signature');
  return payload;
}

/* ------------------------------------------------------------------ */
/* Push room (Durable Object) — one "mailbox" per user id             */
/* ------------------------------------------------------------------ */

const ALLOWED_EVENTS = ['call_invite', 'call_cancelled', 'call_rejected', 'new_message'];
const MAX_PENDING = 25;            // buffered events per offline user
const PENDING_TTL_MS = 10 * 60 * 1000; // drop buffered events after 10 min

export class PushRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
  }

  /**
   * WebSocket upgrade (called via the outer worker's /ws route).
   * Verifies the Firebase ID token, accepts the socket, then drains any
   * events that arrived while this device was offline.
   */
  async fetch(request) {
    const url = new URL(request.url);
    const uid = (url.searchParams.get('uid') || '').trim();
    if (!uid) return json({ error: 'Missing "uid" query parameter.' }, 400);

    const auth = request.headers.get('Authorization') || '';
    try {
      const claims = await verifyFirebaseIdToken(
        auth.replace(/^Bearer\s+/i, ''),
        this.env.FIREBASE_PROJECT_ID,
      );
      if (claims.sub !== uid) return json({ error: 'uid does not match token.' }, 403);
    } catch (e) {
      return json({ error: `Unauthorized: ${e.message}` }, 401);
    }

    if (request.headers.get('Upgrade') !== 'websocket') {
      return json({ error: 'Expected a WebSocket upgrade.' }, 426);
    }

    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [uid]);
    await this.#drainPending();

    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  /** Client heartbeats — nothing to do (the runtime handles protocol pings). */
  async webSocketMessage() {}

  async webSocketClose() {}

  async webSocketError() {}

  /** Deliver [event] to every connected socket; buffer it if offline. */
  async notify(event) {
    const sockets = this.ctx.getWebSockets();
    if (sockets.length === 0) {
      const now = Date.now();
      let pending = (await this.ctx.storage.get('pending')) || [];
      pending = pending.filter((m) => m.at > now - PENDING_TTL_MS);
      pending.push({ at: now, ...event });
      if (pending.length > MAX_PENDING) pending = pending.slice(-MAX_PENDING);
      await this.ctx.storage.put('pending', pending);
      return { delivered: false, buffered: true };
    }

    let delivered = 0;
    const raw = JSON.stringify(event);
    for (const ws of sockets) {
      try {
        ws.send(raw);
        delivered += 1;
      } catch (_) {
        // Socket raced with a disconnect — ignore.
      }
    }
    return { delivered: delivered > 0, buffered: false };
  }

  async #drainPending() {
    const pending = (await this.ctx.storage.get('pending')) || [];
    if (pending.length === 0) return;
    const now = Date.now();
    const fresh = pending.filter((m) => m.at > now - PENDING_TTL_MS);
    if (fresh.length < pending.length) {
      await this.ctx.storage.put('pending', fresh);
    }
    const sockets = this.ctx.getWebSockets();
    for (const m of fresh) {
      const raw = JSON.stringify(m);
      for (const ws of sockets) {
        try {
          ws.send(raw);
        } catch (_) {}
      }
    }
    await this.ctx.storage.put('pending', []);
  }
}

/* ------------------------------------------------------------------ */
/* HTTP handler                                                        */
/* ------------------------------------------------------------------ */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });
}

function bearer(request) {
  return (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
}

// Simple per-sender rate limiter (in-memory; enough for a small app).
const sendCounts = new Map();
const SEND_RATE_LIMIT = 120; // sends per minute per user
const SEND_WINDOW_MS = 60 * 1000;

function rateLimited(uid) {
  const now = Date.now();
  const entry = sendCounts.get(uid);
  if (!entry || now - entry.start > SEND_WINDOW_MS) {
    sendCounts.set(uid, { start: now, count: 1 });
    return false;
  }
  entry.count += 1;
  return entry.count > SEND_RATE_LIMIT;
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    const url = new URL(request.url);

    /* ---------------- /rtc-token (Agora tokens) ---------------- */
    if (url.pathname === '/rtc-token') {
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

    /* ---------------- /send (push an event to a user) ---------------- */
    if (url.pathname === '/send') {
      if (request.method !== 'POST') return json({ error: 'Use POST /send' }, 405);

      let claims;
      try {
        claims = await verifyFirebaseIdToken(bearer(request), env.FIREBASE_PROJECT_ID);
      } catch (e) {
        return json({ error: `Unauthorized: ${e.message}` }, 401);
      }
      if (rateLimited(claims.sub)) return json({ error: 'Rate limit exceeded.' }, 429);

      let body;
      try {
        body = await request.json();
      } catch (_) {
        return json({ error: 'Invalid JSON body.' }, 400);
      }

      const to = typeof body.to === 'string' ? body.to.trim() : '';
      const event = typeof body.event === 'string' ? body.event : '';
      const payload = body.payload && typeof body.payload === 'object' ? body.payload : {};

      if (!to || to.length > 128) return json({ error: 'Missing or invalid "to".' }, 400);
      if (!ALLOWED_EVENTS.includes(event)) return json({ error: `Unknown event. Use one of: ${ALLOWED_EVENTS.join(', ')}.` }, 400);
      if (JSON.stringify(payload).length > 16 * 1024) return json({ error: 'Payload too large (max 16 KB).' }, 413);

      const stub = env.PUSH_ROOM.get(env.PUSH_ROOM.idFromName(to));
      const result = await stub.notify({
        type: 'push',
        event,
        payload,
        from: claims.sub,
        at: Date.now(),
      });
      return json({ ok: true, ...result });
    }

    /* ---------------- /ws (device mailbox connection) ---------------- */
    if (url.pathname === '/ws') {
      const uid = (url.searchParams.get('uid') || '').trim();
      if (!uid || uid.length > 128) {
        return json({ error: 'Missing or invalid "uid" query parameter.' }, 400);
      }
      const stub = env.PUSH_ROOM.get(env.PUSH_ROOM.idFromName(uid));
      return stub.fetch(request);
    }

    /* ---------------- root info ---------------- */
    if (url.pathname === '/' || url.pathname === '') {
      return json({
        service: 'hangout-token-server',
        endpoints: [
          'GET /rtc-token?channel=...&uid=...&expire=... (Agora tokens)',
          'GET /ws?uid=<uid> (WebSocket mailbox, Authorization: Bearer <id-token>)',
          'POST /send { to, event, payload } (push event, Authorization: Bearer <id-token>)',
        ],
      });
    }

    return json({ error: 'Not found.' }, 404);
  },
};
