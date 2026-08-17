#!/usr/bin/env node
/**
 * Ensures the AVATARS_KV namespace exists and that wrangler.toml points at a
 * real namespace id — before `wrangler deploy` runs in CI.
 *
 * Why this exists: `wrangler deploy` fails (or ships without avatar/voice
 * storage) while wrangler.toml still contains the placeholder id
 * `PASTE_YOUR_KV_NAMESPACE_ID_HERE`. This script finds the namespace the
 * account already has, or creates one, and writes the real id into
 * wrangler.toml — so the whole deploy stays a single click with no terminal.
 *
 * Requires the same env vars wrangler uses:
 *   CLOUDFLARE_API_TOKEN   (required)
 *   CLOUDFLARE_ACCOUNT_ID  (optional — auto-detected when the token has
 *                           access to exactly one account)
 */

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const tokenServerDir = join(here, '..');
const wranglerToml = join(tokenServerDir, 'wrangler.toml');

const PLACEHOLDER = 'PASTE_YOUR_KV_NAMESPACE_ID_HERE';
const BINDING = 'AVATARS_KV';

/**
 * Resolves the Cloudflare account id. Uses CLOUDFLARE_ACCOUNT_ID when set;
 * otherwise asks the Cloudflare API which accounts the token can access and
 * uses the id when there is exactly one (the common case). This saves users
 * from having to hunt for the account id in the dashboard.
 */
async function resolveAccountId() {
  if (process.env.CLOUDFLARE_ACCOUNT_ID) {
    return process.env.CLOUDFLARE_ACCOUNT_ID;
  }
  const token = process.env.CLOUDFLARE_API_TOKEN;
  if (!token) {
    throw new Error('Missing CLOUDFLARE_API_TOKEN environment variable.');
  }
  const res = await fetch('https://api.cloudflare.com/client/v4/accounts', {
    headers: { Authorization: `Bearer ${token}` },
  });
  const data = await res.json();
  if (res.ok && data?.success && Array.isArray(data.result)) {
    if (data.result.length === 1) {
      const id = data.result[0].id;
      console.log(`Auto-detected Cloudflare account id: ${id}`);
      return id;
    }
    throw new Error(
      `CLOUDFLARE_ACCOUNT_ID is not set and the API token has access to ` +
        `${data.result.length} accounts. Set CLOUDFLARE_ACCOUNT_ID — see ` +
        `token_server/GITHUB_ACTIONS_DEPLOY.md for how to find it.`,
    );
  }
  throw new Error(
    `Could not list accounts (${res.status}): ` +
      `${JSON.stringify(data).slice(0, 300)}`,
  );
}

/** Runs a wrangler command and returns its stdout (with JSON-safe parsing). */
function wrangler(args) {
  return execFileSync(
    'npx',
    ['--yes', 'wrangler@latest', ...args],
    { cwd: tokenServerDir, encoding: 'utf8' },
  );
}

/** Parses the JSON array `wrangler kv namespace list` prints on stdout. */
function parseNamespaceList(raw) {
  const start = raw.indexOf('[');
  const end = raw.lastIndexOf(']');
  if (start === -1 || end === -1) return [];
  try {
    const parsed = JSON.parse(raw.slice(start, end + 1));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

/** Finds the namespace id for this binding, creating it if needed. */
function ensureNamespace() {
  const listRaw = wrangler(['kv', 'namespace', 'list']);
  const namespaces = parseNamespaceList(listRaw);

  // Accept either a dashboard-created namespace or a CLI-created one
  // (the CLI names it "<worker-name>-AVATARS_KV").
  const match =
    namespaces.find((n) => n.title === 'hangout-avatars') ||
    namespaces.find((n) => n.title === `hangout-token-server-${BINDING}`) ||
    namespaces.find((n) => n.title.endsWith(`-${BINDING}`));

  if (match) {
    console.log(`Using existing KV namespace "${match.title}" (${match.id})`);
    return match.id;
  }

  const createRaw = wrangler(['kv', 'namespace', 'create', BINDING]);
  console.log(createRaw.trim());
  // Newer wrangler prints:  id = "abc123…"
  // Some versions print:    "id": "abc123…"
  const idMatch = createRaw.match(/id\s*=\s*"([^"]+)"/) ||
                  createRaw.match(/"id"\s*:\s*"([^"]+)"/);
  if (!idMatch) {
    throw new Error('Could not parse the namespace id from wrangler output.');
  }
  return idMatch[1];
}

function patchWranglerToml(id) {
  let toml = readFileSync(wranglerToml, 'utf8');
  if (!toml.includes(PLACEHOLDER)) {
    // Already patched — but make sure the id is the right one.
    const current = toml.match(/id = "([^"]+)"/)?.[1];
    if (current === id) {
      console.log('wrangler.toml already points at the namespace id.');
      return;
    }
  }
  toml = toml.replace(PLACEHOLDER, id);
  writeFileSync(wranglerToml, toml);
  console.log(`Patched wrangler.toml with KV namespace id ${id}`);
}

if (!process.env.CLOUDFLARE_API_TOKEN) {
  console.error('Missing CLOUDFLARE_API_TOKEN environment variable.');
  process.exit(1);
}

// Make the resolved id visible to the wrangler commands run below.
process.env.CLOUDFLARE_ACCOUNT_ID = await resolveAccountId();

const id = ensureNamespace();
patchWranglerToml(id);
