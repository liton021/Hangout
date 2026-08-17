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
 *   CLOUDFLARE_API_TOKEN
 *   CLOUDFLARE_ACCOUNT_ID
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

if (!process.env.CLOUDFLARE_API_TOKEN || !process.env.CLOUDFLARE_ACCOUNT_ID) {
  console.error(
    'Missing CLOUDFLARE_API_TOKEN or CLOUDFLARE_ACCOUNT_ID environment variables.',
  );
  process.exit(1);
}

const id = ensureNamespace();
patchWranglerToml(id);
