/**
 * server/signed_media.mjs — GET /media/:key?exp=...&sig=..., the real
 * signed-URL-serving route. `StoragePort.signedUrl()`/`verifySignedKey()`
 * have always been able to mint and verify a signature; nothing in this
 * codebase ever served the actual bytes until this pass (see this file's
 * own header for the full account). Proven here against a real, throwaway
 * FilesystemStorage doing real disk I/O — the same discipline packages/
 * storage/test/storage.test.mjs already applies to the storage layer
 * itself, extended through the actual HTTP-shaped entry point.
 *
 * A fake `res` (capturing writeHead/end calls) stands in for a real
 * `http.ServerResponse` — this file's own header explains why importing
 * server/index.mjs directly (to get a REAL listening server) is unsafe to
 * do from a test: unconditional module-level side effects, no `isMain`
 * guard. serveSignedMedia() itself has zero dependency on index.mjs's own
 * module state (storage is injected), so this is a genuine, real exercise
 * of the actual logic, not a weakened substitute for one.
 */
import { promises as fs } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { serveSignedMedia } from '../signed_media.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const root = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-signed-media-test-'));
const storage = new FilesystemStorage(root);

// A real, distinctive byte payload — every value 0-255 once, so a mangled
// byte anywhere in the response pipeline (encoding, a stray toString(),
// truncation) would show up as a real mismatch, not pass by luck. Same
// discipline packages/api/test/media_route.test.mjs's own REAL_BYTES uses.
const REAL_BYTES = Buffer.from(Array.from({ length: 256 }, (_, i) => i));
const KEY = 'children/ivy/messages/real-artifact.mp4';
await storage.put(KEY, REAL_BYTES);

/** A minimal fake http.ServerResponse — captures exactly what
 * serveSignedMedia() actually calls, nothing more. */
function fakeRes() {
  const res = { statusCode: null, headers: null, body: null };
  res.writeHead = (status, headers) => { res.statusCode = status; res.headers = headers; };
  res.end = (body) => { res.body = body; };
  return res;
}

// Real wall-clock "now" — NOT a fixed constant. serveSignedMedia() reads
// Date.now() internally (via storage.verifySignedKey()), so a URL minted
// against any OTHER fixed timestamp would already be expired relative to
// real time the moment it's verified — the exact bug this test's own first
// draft had (a small fixed constant read as "year 1970", making every
// "valid" URL below immediately expired). Section B still proves real
// expiry, deliberately, using a negative TTL rather than a stale mint time.
const NOW = Date.now();

// ===========================================================================
// A · the real roundtrip — a real signed URL, real bytes served back
// ===========================================================================
{
  const url = storage.signedUrl(KEY, 300, NOW);
  const res = fakeRes();
  await serveSignedMedia(url, res, storage);
  check('A roundtrip', 'a valid, unexpired signed URL serves 200', res.statusCode, 200);
  check('A roundtrip', 'the real bytes come back byte-for-byte identical',
    Buffer.isBuffer(res.body) && res.body.equals(REAL_BYTES), 'true');
  check('A roundtrip', 'Content-Type is honestly generic, not a guessed/fabricated MIME type',
    res.headers['content-type'], 'application/octet-stream');
  check('A roundtrip', 'cache-control is private and short — never a public/long-lived cache '
    + 'for a child\'s media', res.headers['cache-control'], 'private, max-age=300');
  check('A roundtrip', 'nosniff is set, same discipline every other real response in this '
    + 'server carries', res.headers['x-content-type-options'], 'nosniff');
}

// ===========================================================================
// B · expiry — the real 5-minute TTL actually expires, not decorative
// ===========================================================================
{
  // serveSignedMedia() reads Date.now() internally (via
  // storage.verifySignedKey()), so the real way to prove expiry here is to
  // mint a URL whose own expiry is already in the past relative to real
  // wall-clock time — a negative TTL does exactly that.
  const alreadyExpiredUrl = storage.signedUrl(KEY, -1, NOW);
  const res = fakeRes();
  await serveSignedMedia(alreadyExpiredUrl, res, storage);
  check('B expiry', 'a signed URL past its own real expiry is refused, not served',
    res.statusCode, 403);
  check('B expiry', 'the real reason is named', JSON.parse(res.body).error, 'expired');
  check('B expiry', 'no bytes are ever included in a refused response',
    res.body.includes(REAL_BYTES.toString('base64')), 'false');
}

// ===========================================================================
// C · tampering — a modified signature or key is refused, not served
// ===========================================================================
{
  const url = storage.signedUrl(KEY, 300, NOW);
  const parsed = new URL(url, 'http://internal');
  const exp = parsed.searchParams.get('exp');
  const sig = parsed.searchParams.get('sig');

  const tamperedSigRes = fakeRes();
  await serveSignedMedia(
    `/media/${encodeURIComponent(KEY)}?exp=${exp}&sig=${sig.slice(0, -1)}x`, tamperedSigRes, storage);
  check('C tampering', 'a tampered signature is refused', tamperedSigRes.statusCode, 403);
  check('C tampering', 'the real reason is bad_signature, not confused with expiry',
    JSON.parse(tamperedSigRes.body).error, 'bad_signature');

  const wrongKeyRes = fakeRes();
  await serveSignedMedia(
    `/media/${encodeURIComponent('children/ivy/messages/a-different-artifact.mp4')}?exp=${exp}&sig=${sig}`,
    wrongKeyRes, storage);
  check('C tampering', 'the identical, real signature does not verify for a DIFFERENT key '
    + '— proves this route actually calls verifySignedKey() with the real requested key, not '
    + 'just trusting any well-formed exp/sig pair', wrongKeyRes.statusCode, 403);
}

// ===========================================================================
// D · malformed requests — honest 400s, never a crash
// ===========================================================================
{
  const missingSigRes = fakeRes();
  await serveSignedMedia(`/media/${encodeURIComponent(KEY)}?exp=9999999999`, missingSigRes, storage);
  check('D malformed', 'a missing sig is a real 400, not a 500 or a crash', missingSigRes.statusCode, 400);

  const missingExpRes = fakeRes();
  await serveSignedMedia(`/media/${encodeURIComponent(KEY)}?sig=whatever`, missingExpRes, storage);
  check('D malformed', 'a missing exp is a real 400', missingExpRes.statusCode, 400);

  const badExpRes = fakeRes();
  await serveSignedMedia(
    `/media/${encodeURIComponent(KEY)}?exp=not-a-number&sig=whatever`, badExpRes, storage);
  check('D malformed', 'a non-numeric exp is a real 400, not a NaN comparison silently passing',
    badExpRes.statusCode, 400);
}

// ===========================================================================
// E · a valid signature for a key with no real blob behind it — honest 404
// ===========================================================================
{
  const NO_BLOB_KEY = 'children/ivy/messages/never-uploaded.mp4';
  const url = storage.signedUrl(NO_BLOB_KEY, 300, NOW);
  const res = fakeRes();
  await serveSignedMedia(url, res, storage);
  check('E orphan key', 'a validly-signed key with no real blob is an honest 404, never a '
    + '500 or an empty-but-200 body', res.statusCode, 404);
  check('E orphan key', 'the real reason is media_not_found, matching the session-based '
    + 'route\'s own identical convention', JSON.parse(res.body).error, 'media_not_found');
}

// ===========================================================================
// F · path traversal — the key can never escape storage.root, even via
//     this route (belt-and-braces: FilesystemStorage's own resolve() guard
//     already refuses this; proven end-to-end through the real HTTP path)
// ===========================================================================
{
  // A real signature minted directly for a traversal key (not copied from
  // the real KEY above) — proves the refusal is FilesystemStorage's own
  // path-escape guard, not merely a signature mismatch.
  const traversalKey = '../../../../etc/passwd';
  const traversalUrl = storage.signedUrl(traversalKey, 300, NOW);
  const tParsed = new URL(traversalUrl, 'http://internal');
  const res = fakeRes();
  let threw = false;
  try {
    await serveSignedMedia(
      `/media/${encodeURIComponent(traversalKey)}?exp=${tParsed.searchParams.get('exp')}`
        + `&sig=${tParsed.searchParams.get('sig')}`,
      res, storage);
  } catch {
    threw = true;
  }
  // Either outcome (a thrown error, caught by the outer server's own real
  // try/catch in production; or FilesystemStorage.get() somehow returning
  // null) is acceptable here — what must NEVER happen is bytes from outside
  // storage.root being served with a 200.
  check('F traversal', 'a path-traversal key is never served with a 200',
    res.statusCode === 200, 'false');
  if (threw) console.error('F traversal: get() threw for a path-traversal key (expected — '
    + 'FilesystemStorage.resolve()\'s own defensive guard) — the outer HTTP handler\'s real '
    + 'try/catch in server/index.mjs is what turns this into a real 500 in production.');
}

await fs.rm(root, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
