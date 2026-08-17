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
 * Part 3 — Profile pictures (avatar hosting):
 *   POST   /avatar          raw image bytes, Content-Type: image/jpeg|png|webp
 *                           → { url } ; the app stores that URL on the user's
 *                             Firestore document (`users/{uid}.avatarUrl`).
 *   GET    /avatar/<uid>/<hash>.<ext>   public, immutable, cached forever.
 *   POST   /voice                       upload a voice note (auth required).
 *   GET    /voice/<uid>/<hash>.<ext>    public; auto-expires after 10 days.
 *   POST   /image                       upload a chat photo (auth required).
 *   GET    /image/<uid>/<hash>.<ext>    public; auto-expires after 10 days.
 *   Profile pictures never expire (they last until the user deletes them).
 *   DELETE /avatar          removes the caller's picture.
 *
 *   Storage is pluggable and picked automatically at runtime:
 *     • R2 bucket bound as AVATARS_R2  → used when present (10 GB free,
 *       but Cloudflare asks for a card on file to enable R2).
 *     • Workers KV bound as AVATARS_KV → the card-free fallback (1 GB,
 *       1,000 writes/day — thousands of avatars at ~60 KB each).
 *   Bind R2 later and uploads move over with no app change.
 *
 * Auth: both endpoints require an `Authorization: Bearer <firebase-id-token>`
 * header. Tokens are verified against Google's public signing keys from the
 * JWKS endpoint (RS256, cached ~6h) — this needs NO Firebase service account,
 * NO Cloud Messaging API, NO billing, and NO extra console configuration. It
 * only needs the Firebase project id (set below via wrangler vars / env).
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
 *
 * Bindings (wrangler.toml):
 *   PUSH_ROOM     Durable Object namespace (push mailboxes)
 *   AVATARS_KV    KV namespace for profile pictures (card-free default)
 *   AVATARS_R2    optional R2 bucket; takes priority over KV when bound
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

const GOOGLE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const CERTS_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours

let jwksCache = null;
let jwksCacheAt = 0;

/**
 * Fetches Google's public keys for Firebase Auth ID tokens (RS256) and
 * returns them as a map of kid → JWK (kty/n/e).
 *
 * Why JWKS and not the X.509 cert endpoint: Web Crypto's `importKey('spki')`
 * requires a bare SubjectPublicKeyInfo structure, but Google's
 * /metadata/x509/ endpoint serves full X.509 certificates — importing those
 * throws DataError, so every valid token failed verification with a 401
 * ("Unauthorized: …") even when the project id was configured correctly.
 * The JWKS endpoint serves RSA n/e parameters that import cleanly with
 * `importKey('jwk')`.
 */
async function googleJwks() {
  const now = Date.now();
  if (jwksCache && now - jwksCacheAt < CERTS_TTL_MS) return jwksCache;
  const res = await fetch(GOOGLE_JWKS_URL);
  if (!res.ok) throw new Error(`failed to fetch Google signing keys (${res.status})`);
  const data = await res.json();
  const byKid = {};
  for (const key of data.keys || []) {
    if (key.kid) byKid[key.kid] = key;
  }
  jwksCache = byKid;
  jwksCacheAt = now;
  return byKid;
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

/**
 * Auth failures carry a stable machine-readable [code] so the app can tell a
 * server misconfiguration (fixable by the developer) apart from a genuinely
 * bad session (fixable by the user signing in again). The message stays
 * human-readable for anyone hitting the endpoint with curl.
 */
class AuthError extends Error {
  constructor(message, code) {
    super(message);
    this.code = code;
  }
}

/**
 * Standard 401 body for every endpoint that verifies the Firebase ID token.
 * The `errorCode` field is what the Flutter app keys on; never rely on the
 * wording of `error` (it may change).
 */
function authError(e) {
  return json(
    {
      error: `Unauthorized: ${e.message}`,
      ...(e.code ? { errorCode: e.code } : {}),
    },
    401,
  );
}

/**
 * Verifies a Firebase Auth ID token (RS256) against Google's public signing
 * keys (JWKS). Returns the decoded claims (claims.sub === uid).
 */
async function verifyFirebaseIdToken(token, projectId) {
  if (!token) throw new Error('missing Bearer token');
  if (!projectId) {
    throw new AuthError(
      'server missing FIREBASE_PROJECT_ID',
      'server_missing_firebase_project_id',
    );
  }
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

  const jwks = await googleJwks();
  const jwk = jwks[header.kid];
  if (!jwk) throw new Error('unknown signing key');

  const key = await crypto.subtle.importKey(
    'jwk',
    {
      kty: jwk.kty || 'RSA',
      n: jwk.n,
      e: jwk.e,
      alg: 'RS256',
      use: 'sig',
    },
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
      return authError(e);
    }

    if (request.headers.get('Upgrade') !== 'websocket') {
      return json({ error: 'Expected a WebSocket upgrade.' }, 426);
    }

    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1], [uid]);
    await this.#drainPending();

    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  /**
   * App-level heartbeats: the client sends `{"type":"ping"}` every 20s and
   * treats any inbound message as proof of life. Answer with a pong so the
   * client's stale-connection watchdog never force-reconnects a healthy
   * socket (which would drop push events in the gap).
   */
  async webSocketMessage(message) {
    if (typeof message !== 'string') return;
    let parsed;
    try {
      parsed = JSON.parse(message);
    } catch {
      return;
    }
    if (parsed && parsed.type === 'ping') {
      const pong = JSON.stringify({ type: 'pong' });
      for (const ws of this.ctx.getWebSockets()) {
        try {
          ws.send(pong);
        } catch {
          // Socket raced with a disconnect — ignore.
        }
      }
    }
  }

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
/* Avatar storage — R2 when bound, otherwise Workers KV               */
/* ------------------------------------------------------------------ */

const AVATAR_MAX_BYTES = 512 * 1024; // 512 KB — the app resizes to ~60 KB
const AVATAR_TYPES = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};
const EXT_TO_TYPE = {
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

/** Cache-Control for immutable, content-addressed avatar objects. */
const AVATAR_CACHE_CONTROL = 'public, max-age=31536000, immutable';

/* ---------------- voice notes ---------------- */

/**
 * Voice notes are capped hard: the app records mono AAC at 32 kbps and stops
 * at 2 minutes, which lands around 480 KB worst case.
 */
const VOICE_MAX_BYTES = 1024 * 1024; // 1 MB
const VOICE_MAX_SECONDS = 120;

/**
 * Voice notes and chat photos expire after 10 days. This is what keeps the
 * card-free 1 GB KV tier viable: storage reaches a steady state instead of
 * growing forever. Profile pictures are NOT given a TTL — they stay until
 * the user removes them.
 */
const VOICE_TTL_SECONDS = 10 * 24 * 60 * 60;

const VOICE_TYPES = {
  'audio/mp4': 'm4a',   // AAC-LC in an MP4 container (Android/iOS default)
  'audio/aac': 'm4a',
  'audio/mpeg': 'mp3',
  'audio/ogg': 'ogg',   // Opus, when the device supports it
};

const VOICE_EXT_TO_TYPE = {
  m4a: 'audio/mp4',
  mp3: 'audio/mpeg',
  ogg: 'audio/ogg',
};

const VOICE_RATE_LIMIT = 30; // uploads per minute per user

/* ---------------- chat photos ---------------- */

/**
 * Chat photos use the same storage, the same content-addressed URL scheme
 * and the same 10-day TTL as voice notes (see VOICE_TTL_SECONDS above).
 * The app compresses to ~150–400 KB before uploading.
 */
const IMAGE_MAX_BYTES = 2 * 1024 * 1024; // 2 MB
const IMAGE_TTL_SECONDS = VOICE_TTL_SECONDS; // 10 days, same as voice
const IMAGE_RATE_LIMIT = 15; // uploads per minute per user

const IMAGE_TYPES = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const IMAGE_EXT_TO_TYPE = {
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

/**
 * Picks the storage backend. R2 wins when its binding exists so you can add
 * a bucket later without touching the app; KV is the no-credit-card default.
 *
 * The same bucket/namespace backs both avatars (`avatars/…`) and voice notes
 * (`voice/…`) — they are just different key prefixes.
 */
function avatarStore(env) {
  if (env.AVATARS_R2) return { kind: 'r2', bucket: env.AVATARS_R2 };
  if (env.AVATARS_KV) return { kind: 'kv', kv: env.AVATARS_KV };
  return null;
}

/** Short content hash — makes each upload a unique, cacheable URL. */
async function shortHash(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const view = new Uint8Array(digest).subarray(0, 8);
  return Array.from(view, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** `avatars/<uid>/<hash>.<ext>` — the object key in R2/KV. */
function avatarKey(uid, hash, ext) {
  return `avatars/${uid}/${hash}.${ext}`;
}

/**
 * Writes an object. `ttlSeconds` (optional) makes KV expire the value
 * automatically — that is how voice notes stay inside the 1 GB free tier
 * without any cleanup job. R2 has no per-object TTL, so there the expiry is
 * recorded as metadata and enforced lazily on read.
 */
async function putAvatar(store, key, bytes, contentType, ttlSeconds) {
  const expiresAt = ttlSeconds ? Date.now() + ttlSeconds * 1000 : null;

  if (store.kind === 'r2') {
    await store.bucket.put(key, bytes, {
      httpMetadata: { contentType, cacheControl: AVATAR_CACHE_CONTROL },
      customMetadata: expiresAt ? { expiresAt: String(expiresAt) } : undefined,
    });
    return;
  }
  // KV values are capped at 25 MB; our limits are well inside that.
  // KV requires expirationTtl >= 60s.
  const options = { metadata: { contentType, expiresAt } };
  if (ttlSeconds && ttlSeconds >= 60) options.expirationTtl = ttlSeconds;
  await store.kv.put(key, bytes, options);
}

async function getAvatar(store, key) {
  if (store.kind === 'r2') {
    const object = await store.bucket.get(key);
    if (!object) return null;
    // R2 has no native TTL — enforce the recorded expiry on read and reclaim
    // the space lazily.
    const expiresAt = parseInt(object.customMetadata?.expiresAt || '0', 10);
    if (expiresAt && Date.now() > expiresAt) {
      await store.bucket.delete(key).catch(() => {});
      return null;
    }
    return {
      body: object.body,
      contentType: object.httpMetadata?.contentType || 'application/octet-stream',
      etag: object.httpEtag,
    };
  }
  const { value, metadata } = await store.kv.getWithMetadata(key, {
    type: 'arrayBuffer',
  });
  if (!value) return null;
  return {
    body: value,
    contentType: metadata?.contentType || 'application/octet-stream',
    etag: null,
  };
}

/** Deletes every object stored under `avatars/<uid>/`. */
async function deleteAvatars(store, uid) {
  const prefix = `avatars/${uid}/`;
  if (store.kind === 'r2') {
    let cursor;
    do {
      const listing = await store.bucket.list({ prefix, cursor });
      if (listing.objects.length > 0) {
        await store.bucket.delete(listing.objects.map((o) => o.key));
      }
      cursor = listing.truncated ? listing.cursor : undefined;
    } while (cursor);
    return;
  }
  let cursor;
  do {
    const listing = await store.kv.list({ prefix, cursor });
    await Promise.all(listing.keys.map((k) => store.kv.delete(k.name)));
    cursor = listing.list_complete ? undefined : listing.cursor;
  } while (cursor);
}

/**
 * Sniffs the real image type from magic bytes so a caller cannot mislabel a
 * non-image (or an SVG carrying script) as `image/png`.
 */
function sniffImageType(bytes) {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return 'image/png';
  }
  if (
    bytes.length >= 12 &&
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    return 'image/webp';
  }
  return null;
}

/**
 * Sniffs the real audio type from magic bytes, so a caller cannot smuggle
 * arbitrary content in by mislabelling the Content-Type.
 */
function sniffAudioType(bytes) {
  // ISO-BMFF / MP4: bytes 4..7 are 'ftyp'. Covers m4a/aac from both platforms.
  if (
    bytes.length >= 12 &&
    bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70
  ) {
    return 'audio/mp4';
  }
  // OggS — Opus/Vorbis.
  if (
    bytes.length >= 4 &&
    bytes[0] === 0x4f && bytes[1] === 0x67 && bytes[2] === 0x67 && bytes[3] === 0x53
  ) {
    return 'audio/ogg';
  }
  // ID3-tagged MP3.
  if (
    bytes.length >= 3 &&
    bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33
  ) {
    return 'audio/mpeg';
  }
  // Raw MPEG frame sync (0xFFEx / 0xFFFx).
  if (bytes.length >= 2 && bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0) {
    return 'audio/mpeg';
  }
  return null;
}

/** `voice/<uid>/<hash>.<ext>` — the object key for a voice note. */
function voiceKey(uid, hash, ext) {
  return `voice/${uid}/${hash}.${ext}`;
}

/** `images/<uid>/<hash>.<ext>` — chat photos (same TTL as voice notes). */
function imageKey(uid, hash, ext) {
  return `images/${uid}/${hash}.${ext}`;
}

/* ------------------------------------------------------------------ */
/* HTTP handler                                                        */
/* ------------------------------------------------------------------ */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
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

function rateLimited(uid, { bucket = 'send', limit = SEND_RATE_LIMIT } = {}) {
  const now = Date.now();
  const mapKey = `${bucket}:${uid}`;
  const entry = sendCounts.get(mapKey);
  if (!entry || now - entry.start > SEND_WINDOW_MS) {
    sendCounts.set(mapKey, { start: now, count: 1 });
    return false;
  }
  entry.count += 1;
  return entry.count > limit;
}

// Avatar uploads get their own, much smaller budget: the KV free tier only
// allows 1,000 writes/day, and each upload costs a delete + a put.
const AVATAR_RATE_LIMIT = 6; // uploads per minute per user

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
        return authError(e);
      }
      if (rateLimited(claims.sub)) return json({ error: 'Rate limit exceeded.' }, 429);
      if (!env.PUSH_ROOM) {
        return json(
          {
            error:
              'Push is not configured: bind the PUSH_ROOM Durable Object (and run its migration) before deploying again.',
            errorCode: 'server_missing_push_room',
          },
          503,
        );
      }

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

    /* ---------------- /avatar (profile pictures) ---------------- */

    // Public read: GET /avatar/<uid>/<hash>.<ext>
    // No auth — this URL goes into <img>/Image.network on every device.
    if (url.pathname.startsWith('/avatar/')) {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return json({ error: 'Use GET /avatar/<uid>/<hash>.<ext>' }, 405);
      }
      const store = avatarStore(env);
      if (!store) return json({ error: 'Avatar storage is not configured.' }, 501);

      const match = url.pathname.match(
        /^\/avatar\/([A-Za-z0-9_-]{1,128})\/([a-f0-9]{16})\.(jpg|png|webp)$/,
      );
      if (!match) return json({ error: 'Not found.' }, 404);

      const [, uid, hash, ext] = match;
      const object = await getAvatar(store, avatarKey(uid, hash, ext));
      if (!object) return json({ error: 'Not found.' }, 404);

      // Content-addressed: the bytes for a URL never change, so a matching
      // ETag can always be answered with a 304.
      const etag = object.etag || `"${hash}"`;
      if (request.headers.get('If-None-Match') === etag) {
        return new Response(null, {
          status: 304,
          headers: { ETag: etag, 'Cache-Control': AVATAR_CACHE_CONTROL },
        });
      }

      return new Response(request.method === 'HEAD' ? null : object.body, {
        headers: {
          'Content-Type': object.contentType || EXT_TO_TYPE[ext],
          'Cache-Control': AVATAR_CACHE_CONTROL,
          ETag: etag,
          'X-Content-Type-Options': 'nosniff',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // Upload / delete the caller's own picture.
    if (url.pathname === '/avatar') {
      const store = avatarStore(env);
      if (!store) {
        return json(
          {
            error:
              'Avatar storage is not configured: bind AVATARS_KV (or AVATARS_R2) in wrangler.toml.',
          },
          501,
        );
      }

      let claims;
      try {
        claims = await verifyFirebaseIdToken(bearer(request), env.FIREBASE_PROJECT_ID);
      } catch (e) {
        return authError(e);
      }
      const uid = claims.sub;

      if (request.method === 'DELETE') {
        await deleteAvatars(store, uid);
        return json({ ok: true, url: null });
      }

      if (request.method !== 'POST') {
        return json({ error: 'Use POST or DELETE /avatar' }, 405);
      }
      if (rateLimited(uid, { bucket: 'avatar', limit: AVATAR_RATE_LIMIT })) {
        return json({ error: 'Too many uploads — please wait a minute.' }, 429);
      }

      // Reject oversized uploads before reading the body when we can.
      const declared = parseInt(request.headers.get('Content-Length') || '0', 10);
      if (declared > AVATAR_MAX_BYTES) {
        return json({ error: `Image too large (max ${AVATAR_MAX_BYTES / 1024} KB).` }, 413);
      }

      const declaredType = (request.headers.get('Content-Type') || '')
        .split(';')[0]
        .trim()
        .toLowerCase();
      if (!AVATAR_TYPES[declaredType]) {
        return json(
          { error: 'Unsupported Content-Type. Use image/jpeg, image/png or image/webp.' },
          415,
        );
      }

      const bytes = new Uint8Array(await request.arrayBuffer());
      if (bytes.length === 0) return json({ error: 'Empty body.' }, 400);
      if (bytes.length > AVATAR_MAX_BYTES) {
        return json({ error: `Image too large (max ${AVATAR_MAX_BYTES / 1024} KB).` }, 413);
      }

      // Trust the bytes, not the header.
      const actualType = sniffImageType(bytes);
      if (!actualType) return json({ error: 'Body is not a JPEG, PNG or WebP image.' }, 415);

      const ext = AVATAR_TYPES[actualType];
      const hash = await shortHash(bytes);
      const key = avatarKey(uid, hash, ext);

      // One picture per user: drop the previous object(s) first so storage
      // stays flat (important on the 1 GB KV free tier).
      await deleteAvatars(store, uid);
      await putAvatar(store, key, bytes, actualType);

      // Storage keys are `avatars/<uid>/…`; the public route is `/avatar/<uid>/…`.
      const publicUrl = `${url.origin}/avatar/${uid}/${hash}.${ext}`;
      return json({
        ok: true,
        url: publicUrl,
        key,
        size: bytes.length,
        contentType: actualType,
        storage: store.kind,
      });
    }

    /* ---------------- /voice (voice notes) ---------------- */

    // Public read: GET /voice/<uid>/<hash>.<ext>
    // No auth — the URL is unguessable (content hash) and is fetched by the
    // recipient's audio player, which cannot attach headers.
    if (url.pathname.startsWith('/voice/')) {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return json({ error: 'Use GET /voice/<uid>/<hash>.<ext>' }, 405);
      }
      const store = avatarStore(env);
      if (!store) return json({ error: 'Voice storage is not configured.' }, 501);

      const match = url.pathname.match(
        /^\/voice\/([A-Za-z0-9_-]{1,128})\/([a-f0-9]{16})\.(m4a|mp3|ogg)$/,
      );
      if (!match) return json({ error: 'Not found.' }, 404);

      const [, uid, hash, ext] = match;
      const object = await getAvatar(store, voiceKey(uid, hash, ext));
      if (!object) {
        // Either never existed or aged out of the 10-day window.
        return json({ error: 'This voice message has expired.' }, 404);
      }

      const etag = object.etag || `"${hash}"`;
      if (request.headers.get('If-None-Match') === etag) {
        return new Response(null, {
          status: 304,
          headers: { ETag: etag, 'Cache-Control': AVATAR_CACHE_CONTROL },
        });
      }

      return new Response(request.method === 'HEAD' ? null : object.body, {
        headers: {
          'Content-Type': object.contentType || VOICE_EXT_TO_TYPE[ext],
          'Cache-Control': AVATAR_CACHE_CONTROL,
          ETag: etag,
          'X-Content-Type-Options': 'nosniff',
          'Access-Control-Allow-Origin': '*',
          // Players seek; advertising range support avoids a full refetch.
          'Accept-Ranges': 'bytes',
        },
      });
    }

    // Upload a voice note: POST /voice (raw audio bytes).
    if (url.pathname === '/voice') {
      const store = avatarStore(env);
      if (!store) {
        return json(
          {
            error:
              'Voice storage is not configured: bind AVATARS_KV (or AVATARS_R2) in the dashboard.',
          },
          501,
        );
      }

      let claims;
      try {
        claims = await verifyFirebaseIdToken(bearer(request), env.FIREBASE_PROJECT_ID);
      } catch (e) {
        return authError(e);
      }
      const uid = claims.sub;

      if (request.method !== 'POST') {
        return json({ error: 'Use POST /voice' }, 405);
      }
      if (rateLimited(uid, { bucket: 'voice', limit: VOICE_RATE_LIMIT })) {
        return json({ error: 'Too many voice messages — please wait a minute.' }, 429);
      }

      const declared = parseInt(request.headers.get('Content-Length') || '0', 10);
      if (declared > VOICE_MAX_BYTES) {
        return json({ error: `Voice note too large (max ${VOICE_MAX_BYTES / 1024} KB).` }, 413);
      }

      const declaredType = (request.headers.get('Content-Type') || '')
        .split(';')[0]
        .trim()
        .toLowerCase();
      if (!VOICE_TYPES[declaredType]) {
        return json(
          { error: 'Unsupported Content-Type. Use audio/mp4, audio/aac, audio/mpeg or audio/ogg.' },
          415,
        );
      }

      const bytes = new Uint8Array(await request.arrayBuffer());
      if (bytes.length === 0) return json({ error: 'Empty body.' }, 400);
      if (bytes.length > VOICE_MAX_BYTES) {
        return json({ error: `Voice note too large (max ${VOICE_MAX_BYTES / 1024} KB).` }, 413);
      }

      const actualType = sniffAudioType(bytes);
      if (!actualType) return json({ error: 'Body is not a recognised audio file.' }, 415);

      const ext = VOICE_TYPES[actualType];
      const hash = await shortHash(bytes);
      const key = voiceKey(uid, hash, ext);

      // Unlike avatars, previous notes are NOT deleted — each is its own
      // message. The 10-day TTL is what bounds total storage.
      await putAvatar(store, key, bytes, actualType, VOICE_TTL_SECONDS);

      const publicUrl = `${url.origin}/voice/${uid}/${hash}.${ext}`;
      return json({
        ok: true,
        url: publicUrl,
        key,
        size: bytes.length,
        contentType: actualType,
        storage: store.kind,
        expiresInDays: VOICE_TTL_SECONDS / 86400,
      });
    }

    /* ---------------- /image (chat photos) ---------------- */

    // Public read: GET /image/<uid>/<hash>.<ext>
    // No auth — the URL is unguessable (content hash) and is fetched by the
    // recipient's image loader, which cannot attach headers.
    if (url.pathname.startsWith('/image/')) {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return json({ error: 'Use GET /image/<uid>/<hash>.<ext>' }, 405);
      }
      const store = avatarStore(env);
      if (!store) return json({ error: 'Photo storage is not configured.' }, 501);

      const match = url.pathname.match(
        /^\/image\/([A-Za-z0-9_-]{1,128})\/([a-f0-9]{16})\.(jpg|png|webp)$/,
      );
      if (!match) return json({ error: 'Not found.' }, 404);

      const [, uid, hash, ext] = match;
      const object = await getAvatar(store, imageKey(uid, hash, ext));
      if (!object) {
        // Either never existed or aged out of the 10-day window.
        return json({ error: 'This photo has expired.' }, 404);
      }

      const etag = object.etag || `"${hash}"`;
      if (request.headers.get('If-None-Match') === etag) {
        return new Response(null, {
          status: 304,
          headers: { ETag: etag, 'Cache-Control': AVATAR_CACHE_CONTROL },
        });
      }

      return new Response(request.method === 'HEAD' ? null : object.body, {
        headers: {
          'Content-Type': object.contentType || IMAGE_EXT_TO_TYPE[ext],
          'Cache-Control': AVATAR_CACHE_CONTROL,
          ETag: etag,
          'X-Content-Type-Options': 'nosniff',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // Upload a chat photo: POST /image (raw image bytes).
    if (url.pathname === '/image') {
      const store = avatarStore(env);
      if (!store) {
        return json(
          {
            error:
              'Photo storage is not configured: bind AVATARS_KV (or AVATARS_R2) in the dashboard.',
          },
          501,
        );
      }

      let claims;
      try {
        claims = await verifyFirebaseIdToken(bearer(request), env.FIREBASE_PROJECT_ID);
      } catch (e) {
        return authError(e);
      }
      const uid = claims.sub;

      if (request.method !== 'POST') {
        return json({ error: 'Use POST /image' }, 405);
      }
      if (rateLimited(uid, { bucket: 'image', limit: IMAGE_RATE_LIMIT })) {
        return json({ error: 'Too many photos — please wait a minute.' }, 429);
      }

      const declared = parseInt(request.headers.get('Content-Length') || '0', 10);
      if (declared > IMAGE_MAX_BYTES) {
        return json({ error: `Photo too large (max ${IMAGE_MAX_BYTES / 1024} KB).` }, 413);
      }

      const declaredType = (request.headers.get('Content-Type') || '')
        .split(';')[0]
        .trim()
        .toLowerCase();
      if (!IMAGE_TYPES[declaredType]) {
        return json(
          { error: 'Unsupported Content-Type. Use image/jpeg, image/png or image/webp.' },
          415,
        );
      }

      const bytes = new Uint8Array(await request.arrayBuffer());
      if (bytes.length === 0) return json({ error: 'Empty body.' }, 400);
      if (bytes.length > IMAGE_MAX_BYTES) {
        return json({ error: `Photo too large (max ${IMAGE_MAX_BYTES / 1024} KB).` }, 413);
      }

      const actualType = sniffImageType(bytes);
      if (!actualType) return json({ error: 'Body is not a JPEG, PNG or WebP image.' }, 415);

      const ext = IMAGE_TYPES[actualType];
      const hash = await shortHash(bytes);
      const key = imageKey(uid, hash, ext);

      // Each photo is its own message; the 10-day TTL bounds total storage.
      await putAvatar(store, key, bytes, actualType, IMAGE_TTL_SECONDS);

      const publicUrl = `${url.origin}/image/${uid}/${hash}.${ext}`;
      return json({
        ok: true,
        url: publicUrl,
        key,
        size: bytes.length,
        contentType: actualType,
        storage: store.kind,
        expiresInDays: IMAGE_TTL_SECONDS / 86400,
      });
    }

    /* ---------------- /ws (device mailbox connection) ---------------- */
    if (url.pathname === '/ws') {
      const uid = (url.searchParams.get('uid') || '').trim();
      if (!uid || uid.length > 128) {
        return json({ error: 'Missing or invalid "uid" query parameter.' }, 400);
      }
      if (!env.PUSH_ROOM) {
        // Without this guard the Worker would throw and the client would see
        // a bare Cloudflare "Error 1101 — Worker threw exception" instead of
        // a readable answer.
        return json(
          {
            error:
              'Push is not configured: bind the PUSH_ROOM Durable Object (and run its migration) before deploying again.',
            errorCode: 'server_missing_push_room',
          },
          503,
        );
      }
      const stub = env.PUSH_ROOM.get(env.PUSH_ROOM.idFromName(uid));
      return stub.fetch(request);
    }

    /* ---------------- root info ---------------- */
    if (url.pathname === '/' || url.pathname === '') {
      const store = avatarStore(env);
      return json({
        service: 'hangout-token-server',
        endpoints: [
          'GET /rtc-token?channel=...&uid=...&expire=... (Agora tokens)',
          'GET /ws?uid=<uid> (WebSocket mailbox, Authorization: Bearer <id-token>)',
          'POST /send { to, event, payload } (push event, Authorization: Bearer <id-token>)',
          'POST /avatar (raw image bytes, Authorization: Bearer <id-token>) → { url }',
          'DELETE /avatar (remove your picture, Authorization: Bearer <id-token>)',
          'GET /avatar/<uid>/<hash>.<ext> (public profile picture, no expiry)',
          'POST /voice (raw audio bytes, Authorization: Bearer <id-token>) → { url }',
          'GET /voice/<uid>/<hash>.<ext> (public voice note, expires after 10 days)',
          'POST /image (raw image bytes, Authorization: Bearer <id-token>) → { url }',
          'GET /image/<uid>/<hash>.<ext> (public chat photo, expires after 10 days)',
        ],
        avatarStorage: store?.kind ?? 'not configured',
        voiceStorage: store?.kind ?? 'not configured',
        imageStorage: store?.kind ?? 'not configured',
        voiceRetentionDays: VOICE_TTL_SECONDS / 86400,
        imageRetentionDays: IMAGE_TTL_SECONDS / 86400,
        // Deployment self-check — every field should read `true` on a
        // correctly configured worker:
        //   config.firebaseProjectIdConfigured — [vars] FIREBASE_PROJECT_ID
        //   config.pushRoomConfigured          — PUSH_ROOM Durable Object binding
        //   config.avatarStorageConfigured    — AVATARS_KV / AVATARS_R2 binding
        config: {
          firebaseProjectIdConfigured: Boolean(env.FIREBASE_PROJECT_ID),
          firebaseProjectId: env.FIREBASE_PROJECT_ID || null,
          pushRoomConfigured: Boolean(env.PUSH_ROOM),
          avatarStorageConfigured: Boolean(store),
        },
      });
    }

    return json({ error: 'Not found.' }, 404);
  },
};
