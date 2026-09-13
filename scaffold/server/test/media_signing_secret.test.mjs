/**
 * server/routes.mjs — defaultMediaStorage's own signing secret,
 * MEDIA_SIGNING_SECRET-driven since this project's own post-tier audit.
 *
 * Real bug this file exists to prove fixed: FilesystemStorage's own signing
 * secret used to default to a fresh `randomBytes(32)` EVERY process start,
 * with nothing anywhere reading a configured value in. Fine within one
 * running process (mint and verify always agreed with each other there) —
 * but every real server restart silently invalidated every signed URL still
 * inside its 5-minute TTL, and structurally forbade ever scaling `server`
 * past one replica (two processes would each mint a different secret and
 * neither could verify the other's URLs).
 *
 * The real proof needs TWO SEPARATE Node processes — a module-level secret
 * read once at import time can't be exercised meaningfully within a single
 * process, and that is exactly the shape of the real bug (each `server`
 * container is its own process). Each subprocess here stands in for one
 * "restart"/replica: they share nothing but the env var.
 */
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { promises as fs } from 'node:fs';
import * as os from 'node:os';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const HERE = dirname(fileURLToPath(import.meta.url));
const ROUTES = join(HERE, '..', 'routes.mjs');
const root = await fs.mkdtemp(join(os.tmpdir(), 'olive-media-secret-test-'));

// A small inline script, run in its own process via -e, that imports
// routes.mjs's real defaultMediaStorage (module load time is exactly when
// MEDIA_SIGNING_SECRET is read) and either mints or verifies a signed key
// for the SAME real KEY, printing JSON to stdout — never anything more, so
// the parent can assert on it precisely.
const KEY = 'children/ivy/messages/restart-proof.mp4';
const MINT = `
import { defaultMediaStorage } from ${JSON.stringify(ROUTES)};
const url = defaultMediaStorage.signedUrl(${JSON.stringify(KEY)}, 300, Date.now());
process.stdout.write(JSON.stringify({ url }));
`;
const VERIFY = `
import { defaultMediaStorage } from ${JSON.stringify(ROUTES)};
const parsed = new URL(process.argv[1], 'http://internal');
const exp = Number(parsed.searchParams.get('exp'));
const sig = parsed.searchParams.get('sig');
const result = defaultMediaStorage.verifySignedKey(${JSON.stringify(KEY)}, exp, sig, Date.now());
process.stdout.write(JSON.stringify(result));
`;

function run(script, env, extraArgs = []) {
  return JSON.parse(execFileSync(process.execPath, ['--input-type=module', '-e', script, ...extraArgs], {
    encoding: 'utf8',
    env: { ...process.env, MEDIA_STORAGE_ROOT: root, ...env },
  }));
}

// ===========================================================================
// A · MEDIA_SIGNING_SECRET set — the whole point: a signature minted by one
//     process verifies in a completely separate one, proving the secret
//     really persists across what each subprocess here stands in for (a
//     restart, or a second replica) rather than being re-randomized.
// ===========================================================================
{
  const SECRET = '11'.repeat(32); // 32 real bytes, hex-encoded, like openssl rand -hex 32
  const { url } = run(MINT, { MEDIA_SIGNING_SECRET: SECRET });
  const result = run(VERIFY, { MEDIA_SIGNING_SECRET: SECRET }, [url]);
  check('A persisted secret', 'a signature minted in one process verifies in a totally '
    + 'separate one given the SAME MEDIA_SIGNING_SECRET — this is the actual restart/'
    + 'multi-replica fix, not just "the env var is read"', result.ok, true);
}

// ===========================================================================
// B · MEDIA_SIGNING_SECRET NOT set — must still work (a bare local dev run
//     is not broken by this fix), but a signature minted in one process must
//     NOT verify in another: this is the pre-existing, still-real "no
//     persisted secret" limitation for anyone who doesn't set it, proven
//     here so a future change can't silently regress the case where it
//     genuinely IS set (A above) while leaving this one looking the same.
// ===========================================================================
{
  const { url } = run(MINT, {});
  const result = run(VERIFY, {}, [url]);
  check('B no secret set', 'a single mint still produces a real signed URL -- the '
    + 'fallback to a fresh random secret is not itself broken by this fix',
    typeof url, 'string');
  check('B no secret set', 'a signature minted in one process does NOT verify in a '
    + 'separate one with no persisted secret -- the honest, still-real limitation for '
    + 'anyone who leaves MEDIA_SIGNING_SECRET unset', result.ok, false);
}

await fs.rm(root, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
