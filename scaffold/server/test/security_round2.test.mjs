/**
 * server/test/security_round2.test.mjs — the pure (no database) half of the
 * round-2 security audit fixes. The database halves are
 * server/test/security_round2_route.test.mjs and packages/db/test/edge_rls.test.mjs.
 *
 *   S-B1   MissBudget (global pairing-miss counter), per-IP scope of the limiter
 *   S-B6   header-only image dimension check (refuse > 20 Mpx before decoding),
 *          per-principal write limiter, in-flight upload semaphore
 *   S-B8   magic-byte media sniffing
 *   S-B13  boot secret validation + the HMAC signed-URL key function
 *   S-B14  strictIds: a malformed uuid path parameter is 400, never reaches a handler
 *   S-B15  login identifier bucket keyed on (id, IP)
 *   S-B16  session key id + two-key rotation + role allowlist
 *
 * Every deny path below is a real assertion against the real module, imported
 * unmodified; nothing here is a hand-typed copy of production logic.
 */
import { spawnSync } from 'node:child_process';
import { createHmac, randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { Api } from '../../packages/api/src/api.mjs';
import { issueSession, readSession, keyId, SESSION_ROLES } from '../../packages/auth/src/auth.mjs';
import { decodeImage, imageDimensions, assertImageWithinLimits, MAX_IMAGE_PIXELS }
  from '../../packages/homework/src/measure.mjs';
import { signKey, verifySignedUrl } from '../../packages/storage/src/storage.mjs';
import { securityEventSummary } from '../../packages/db/src/pool.mjs';
import { MissBudget, InFlightLimiter, createAuthLimiter, createWriteLimiter, createPairingMissBudget }
  from '../rate_limit.mjs';
import { parseHexSecret, checkBootSecrets, looksLikePlaceholder } from '../secrets.mjs';
import { sniffMedia, SERVABLE_MIMES } from '../media_sniff.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const HERE = dirname(fileURLToPath(import.meta.url));
const SERVER_ENTRY = join(HERE, '..', 'index.mjs');
const NOW = Date.parse('2026-11-08T12:00:00Z');
const UUID_A = '11111111-1111-4111-8111-111111111111';
const hex = (n) => randomBytes(n).toString('hex');

// ===========================================================================
// A · S-B1 — the global miss budget
// ===========================================================================
{
  let t = 0;
  const b = new MissBudget({ limit: 3, windowMs: 60_000, now: () => t });
  check('A miss budget', 'a fresh budget is not blocked', b.check().blocked, false);
  b.hit(); b.hit();
  check('A miss budget', 'two misses of three are still allowed', b.check().blocked, false);
  b.hit();
  const blocked = b.check();
  check('A miss budget', 'the third miss exhausts it: blocked', blocked.blocked, true);
  check('A miss budget', 'with a positive retry-after', blocked.retryAfterSec >= 1, true);
  t = 59_000;
  check('A miss budget', 'still blocked 59 s into the window', b.check().blocked, true);
  t = 60_001;
  check('A miss budget', 'the window rolling over re-opens it', b.check().blocked, false);
  check('A miss budget', 'and clears the count (a full new budget)', (b.hit(), b.hit(), b.check().blocked), false);

  const dflt = createPairingMissBudget({ env: {} });
  check('A miss budget', 'default is 20 misses/min', dflt.limit, 20);
  check('A miss budget', 'env override applies', createPairingMissBudget({ env: { PAIRING_MISS_BUDGET_PER_MIN: '5' } }).limit, 5);
  check('A miss budget', 'an invalid env value falls back to the default',
    createPairingMissBudget({ env: { PAIRING_MISS_BUDGET_PER_MIN: '-3' } }).limit, 20);
}

// ===========================================================================
// B · S-B1/S-B14 — the per-IP limiter now covers the pairing + invite routes
//     (a source-level tripwire: index.mjs is a script and cannot be imported)
// ===========================================================================
{
  const { readFileSync } = await import('node:fs');
  const src = readFileSync(SERVER_ENTRY, 'utf8');
  check('B ip scope', 'the per-IP limiter covers /v1/device-pairing/', /pathname\.startsWith\('\/v1\/device-pairing\/'\)/.test(src), true);
  check('B ip scope', 'and /v1/guardian-invites/', /pathname\.startsWith\('\/v1\/guardian-invites\/'\)/.test(src), true);
  check('B ip scope', 'the Api is built with strictIds', /strictIds:\s*true/.test(src), true);
  check('B ip scope', 'and with the authenticated-write limiter', /writeLimiter:\s*createWriteLimiter\(\)/.test(src), true);
  check('B ip scope', 'the login identifier bucket is keyed with the caller IP', /checkIdentifier\(ident, clientIp\(req\)\)/.test(src), true);
}

// ===========================================================================
// C · S-B15 — the identifier bucket is keyed on (id, IP)
// ===========================================================================
{
  let t = 0;
  const lim = createAuthLimiter({ env: { AUTH_RATE_ID_CAPACITY: '2', AUTH_RATE_ID_PER_MIN: '1' }, now: () => t });
  const victim = '22222222-2222-4222-8222-222222222222';
  lim.checkIdentifier(victim, '203.0.113.9'); lim.checkIdentifier(victim, '203.0.113.9');
  check('C id+ip', 'an attacker at one address exhausts only THEIR bucket for the victim id',
    lim.checkIdentifier(victim, '203.0.113.9').ok, false);
  check('C id+ip', 'the victim, from their own address, is not locked out of their own id',
    lim.checkIdentifier(victim, '198.51.100.7').ok, true);
}

// ===========================================================================
// D · S-B6 — write limiter + in-flight upload cap
// ===========================================================================
{
  let t = 0;
  const wl = createWriteLimiter({ env: { WRITE_RATE_CAPACITY: '2', WRITE_RATE_PER_MIN: '60' }, now: () => t });
  const dad = { userId: 'dad', childId: null }, kid = { userId: null, childId: 'kid' };
  check('D write limit', '1st write allowed', wl(dad).ok, true);
  check('D write limit', '2nd write allowed', wl(dad).ok, true);
  check('D write limit', '3rd write inside the burst is refused', wl(dad).ok, false);
  check('D write limit', 'a different principal has their own bucket', wl(kid).ok, true);
  t = 2000;
  check('D write limit', 'tokens refill with time', wl(dad).ok, true);

  const f = new InFlightLimiter({ max: 2 });
  const r1 = f.acquire('u:a'), r2 = f.acquire('u:a');
  check('D in-flight', 'two concurrent uploads are admitted', Boolean(r1 && r2), true);
  check('D in-flight', 'a third for the same principal is refused (not queued)', f.acquire('u:a'), null);
  check('D in-flight', 'another principal is unaffected', typeof f.acquire('u:b'), 'function');
  r1();
  check('D in-flight', 'releasing a slot admits the next', typeof f.acquire('u:a'), 'function');
  r2(); r2(); // double release must not under-count
  check('D in-flight', 'a double release is harmless (count never negative)', f.count('u:a') >= 0, true);
}

// ===========================================================================
// E · S-B6 — image dimensions read from the header, refused BEFORE decoding
// ===========================================================================
{
  const pngHeader = (w, h) => {
    const b = Buffer.alloc(33);
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(b, 0);
    b.writeUInt32BE(13, 8); b.write('IHDR', 12, 'latin1');
    b.writeUInt32BE(w, 16); b.writeUInt32BE(h, 20); b[24] = 8; b[25] = 6;
    return b;
  };
  const jpegHeader = (w, h) => {
    const b = Buffer.alloc(30);
    b[0] = 0xff; b[1] = 0xd8;
    // APP0 segment (length 16) then SOF0
    b[2] = 0xff; b[3] = 0xe0; b.writeUInt16BE(16, 4);
    b[20] = 0xff; b[21] = 0xc0; b.writeUInt16BE(17, 22); b[24] = 8;
    b.writeUInt16BE(h, 25); b.writeUInt16BE(w, 27);
    return b;
  };
  const eight = imageDimensions(pngHeader(8000, 8000));
  check('E image limits', 'PNG IHDR dimensions are read from the header alone', `${eight.width}x${eight.height}`, '8000x8000');
  const jd = imageDimensions(jpegHeader(6000, 4000));
  check('E image limits', 'JPEG SOF dimensions are read past the APP0 segment', `${jd.width}x${jd.height}`, '6000x4000');
  check('E image limits', 'non-images have no dimensions', imageDimensions(Buffer.from('hello world, not an image at all')), null);

  const t0 = Date.now();
  let msg = '';
  try { decodeImage(pngHeader(8000, 8000)); } catch (e) { msg = String(e.message); }
  check('E image limits', 'an 8000x8000 PNG header is refused as image_too_large (64 Mpx)', /^image_too_large/.test(msg), true);
  check('E image limits', 'refused without allocating (instant, no ~830 MB decode)', Date.now() - t0 < 500, true);
  msg = '';
  try { decodeImage(jpegHeader(9000, 9000)); } catch (e) { msg = String(e.message); }
  check('E image limits', 'an oversize JPEG is refused too', /^image_too_large/.test(msg), true);
  msg = '';
  try { assertImageWithinLimits(pngHeader(4472, 4472)); msg = 'ok'; } catch (e) { msg = String(e.message); }
  check('E image limits', '4472x4472 (19.99 Mpx) is inside the 20 Mpx ceiling', msg, 'ok');
  msg = '';
  try { assertImageWithinLimits(pngHeader(4473, 4473)); msg = 'ok'; } catch (e) { msg = String(e.message); }
  check('E image limits', '4473x4473 (20.01 Mpx) is over it', /^image_too_large/.test(msg), true);
  msg = '';
  try { assertImageWithinLimits(pngHeader(0, 5)); msg = 'ok'; } catch (e) { msg = String(e.message); }
  check('E image limits', 'a zero dimension is refused', /^image_too_large/.test(msg), true);
  check('E image limits', 'the ceiling is 20 megapixels', MAX_IMAGE_PIXELS, 20_000_000);
}

// ===========================================================================
// F · S-B8 — magic-byte sniffing
// ===========================================================================
{
  const ftyp = (brand) => Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftyp'), Buffer.from(brand), Buffer.alloc(12)]);
  check('F sniff', 'JPEG', sniffMedia(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0])).mime, 'image/jpeg');
  check('F sniff', 'PNG', sniffMedia(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0])).mime, 'image/png');
  check('F sniff', 'WebM (EBML)', sniffMedia(Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 1, 2, 3])).mime, 'video/webm');
  check('F sniff', 'MP4 (ftyp isom) is video', sniffMedia(ftyp('isom')).mime, 'video/mp4');
  check('F sniff', 'an M4A brand is audio', sniffMedia(ftyp('M4A ')).mime, 'audio/mp4');
  check('F sniff', 'plain text is refused', sniffMedia(Buffer.from('<script>alert(1)</script>')), null);
  check('F sniff', 'an HTML page named like a video is refused', sniffMedia(Buffer.from('<!doctype html><html></html>')), null);
  check('F sniff', 'a PE executable is refused', sniffMedia(Buffer.from('MZ\x90\x00\x03\x00\x00\x00\x04\x00')), null);
  check('F sniff', 'too-short input is refused', sniffMedia(Buffer.from([0xff])), null);
  check('F sniff', 'a truncated PNG signature is refused', sniffMedia(Buffer.from([0x89, 0x50, 0x4e, 0x47])), null);
  check('F sniff', 'every MIME the sniffer can return is in the servable set',
    ['image/jpeg', 'image/png', 'video/webm', 'video/mp4', 'audio/mp4'].every((m) => SERVABLE_MIMES.has(m)), true);
}

// ===========================================================================
// G · S-B13 — secret validation + HMAC signed URLs
// ===========================================================================
{
  const throws = (fn) => { try { fn(); return ''; } catch (e) { return String(e.message); } };
  check('G secrets', 'non-hex is refused (Buffer.from would have made a ZERO-length key)',
    /must be a hex string/.test(throws(() => parseHexSecret('not-hex-value', 'X'))), true);
  check('G secrets', 'odd-length hex is refused', /must be a hex string/.test(throws(() => parseHexSecret('abc', 'X'))), true);
  check('G secrets', 'hex under 32 bytes is refused', /at least 32 bytes/.test(throws(() => parseHexSecret('ab'.repeat(31), 'X'))), true);
  check('G secrets', '32 bytes of hex is accepted', parseHexSecret(hex(32), 'X').length, 32);
  check('G secrets', 'an empty string is refused', /must be a hex string/.test(throws(() => parseHexSecret('', 'X'))), true);

  check('G secrets', 'all-zero hex looks like a placeholder', looksLikePlaceholder('0'.repeat(64)), true);
  check('G secrets', 'a repeated short block looks like a placeholder', looksLikePlaceholder('deadbeef'.repeat(8)), true);
  check('G secrets', 'random hex does not', looksLikePlaceholder(hex(32)), false);

  const good = { SESSION_SECRET: hex(32), MEDIA_SIGNING_SECRET: hex(32), NODE_ENV: 'production' };
  check('G secrets', 'a production env with two real keys has no problems', checkBootSecrets(good).problems.length, 0);
  check('G secrets', 'SESSION_SECRET=changeme is refused in production',
    checkBootSecrets({ ...good, SESSION_SECRET: 'changeme' }).problems.length > 0, true);
  check('G secrets', 'a placeholder SESSION_SECRET (all aa) is refused in production',
    checkBootSecrets({ ...good, SESSION_SECRET: 'aa'.repeat(32) }).problems.length > 0, true);
  check('G secrets', 'a short SESSION_SECRET is refused when NODE_ENV is unset',
    checkBootSecrets({ SESSION_SECRET: 'x'.repeat(40), MEDIA_SIGNING_SECRET: hex(32) }).problems.length > 0, true);
  check('G secrets', 'a missing MEDIA_SIGNING_SECRET is refused in production',
    checkBootSecrets({ SESSION_SECRET: good.SESSION_SECRET, NODE_ENV: 'production' }).problems.length > 0, true);
  check('G secrets', 'a typo in MEDIA_SIGNING_SECRET is refused even in development',
    checkBootSecrets({ SESSION_SECRET: 'dev', NODE_ENV: 'development', MEDIA_SIGNING_SECRET: 'not-hex-value' }).problems.length > 0, true);
  check('G secrets', 'development may use a plain SESSION_SECRET and no media secret',
    checkBootSecrets({ SESSION_SECRET: 'dev-secret', NODE_ENV: 'development' }).problems.length, 0);
  check('G secrets', 'a missing SESSION_SECRET is refused everywhere',
    checkBootSecrets({ NODE_ENV: 'development' }).problems.length > 0, true);
  const withPrev = checkBootSecrets({ ...good, SESSION_SECRET_PREVIOUS: hex(32) });
  check('G secrets', 'a valid SESSION_SECRET_PREVIOUS is parsed for rotation', withPrev.previousSessionSecret?.length > 0, true);
  check('G secrets', 'a malformed SESSION_SECRET_PREVIOUS is a boot problem',
    checkBootSecrets({ ...good, SESSION_SECRET_PREVIOUS: 'nope' }).problems.length > 0, true);

  // The real process refuses to start (exit 2) — spawned, not simulated.
  const boot = (env) => spawnSync(process.execPath, [SERVER_ENTRY], {
    env: { PATH: process.env.PATH, DATABASE_URL: 'postgres://nobody@127.0.0.1:9/none', ...env },
    encoding: 'utf8', timeout: 20_000,
  });
  const r1 = boot({ NODE_ENV: 'production', SESSION_SECRET: 'changeme', MEDIA_SIGNING_SECRET: hex(32) });
  check('G boot', 'a production boot with SESSION_SECRET=changeme exits 2', r1.status, 2);
  check('G boot', 'and says why', /SESSION_SECRET/.test(r1.stderr), true);
  const r2 = boot({ NODE_ENV: 'production', SESSION_SECRET: hex(32), MEDIA_SIGNING_SECRET: 'not-hex-value' });
  // (routes.mjs is imported before the boot check runs, so it is the one that refuses: exit 1, same outcome.)
  check('G boot', 'a boot with a non-hex MEDIA_SIGNING_SECRET refuses to start', r2.status !== 0 && r2.status !== null, true);
  check('G boot', 'and names MEDIA_SIGNING_SECRET', /MEDIA_SIGNING_SECRET/.test(r2.stderr), true);
  const r3 = boot({ NODE_ENV: 'production', SESSION_SECRET: hex(32) });
  check('G boot', 'a production boot without MEDIA_SIGNING_SECRET exits 2', r3.status, 2);

  // routes.mjs itself refuses a malformed MEDIA_SIGNING_SECRET at import.
  const imp = spawnSync(process.execPath, ['--input-type=module', '-e',
    `await import(${JSON.stringify('file:///' + join(HERE, '..', 'routes.mjs').replace(/\\/g, '/'))})`], {
    env: { PATH: process.env.PATH, MEDIA_SIGNING_SECRET: 'not-hex-value', LIVEKIT_URL: 'wss://x.invalid',
      LIVEKIT_API_KEY: 'k', LIVEKIT_API_SECRET: 's'.repeat(32) }, encoding: 'utf8', timeout: 20_000 });
  check('G boot', 'importing routes.mjs with a malformed MEDIA_SIGNING_SECRET fails loudly', imp.status !== 0, true);

  const key = randomBytes(32);
  const sig = signKey(key, 'children/a/messages/b', 1_900_000_000);
  check('G hmac', 'the signed-URL signature is HMAC-SHA256 over key NUL exp',
    sig, createHmac('sha256', key).update('children/a/messages/b').update('\u0000').update('1900000000').digest('base64url'));
  check('G hmac', 'it verifies for the same key and expiry', verifySignedUrl(key, 'children/a/messages/b', 1_900_000_000, sig, 1_800_000_000_000).ok, true);
  check('G hmac', 'it does not verify for another key', verifySignedUrl(key, 'children/a/messages/c', 1_900_000_000, sig, 1_800_000_000_000).ok, false);
  check('G hmac', 'nor for another expiry', verifySignedUrl(key, 'children/a/messages/b', 1_900_000_001, sig, 1_800_000_000_000).ok, false);
  check('G hmac', 'nor under another secret', verifySignedUrl(randomBytes(32), 'children/a/messages/b', 1_900_000_000, sig, 1_800_000_000_000).ok, false);
}

// ===========================================================================
// H · S-B14 — strictIds on the real Api
// ===========================================================================
{
  const secret = randomBytes(32);
  const db = {
    edgesFor: async () => [], isDeviceRevoked: async () => false,
    withSession: async (_p, fn) => fn(async () => []),
  };
  const mk = (opts) => {
    const api = new Api(secret, db, () => NOW, opts);
    api.register({ method: 'GET', path: '/v1/invites/:inviteId', action: null,
      skipOuterSession: true, noSessionRequired: true,
      handler: async (c) => ({ body: { got: c.params.inviteId } }) });
    api.register({ method: 'GET', path: '/v1/learn/:day', action: null, skipOuterSession: true,
      handler: async (c) => ({ body: { day: c.params.day } }) });
    api.register({ method: 'POST', path: '/v1/things', action: null, skipOuterSession: true,
      handler: async () => ({ body: { ok: true } }) });
    return api;
  };
  const strict = mk({ strictIds: true }), loose = mk({});
  const tok = issueSession(secret, { userId: UUID_A, roleName: 'guardian', childId: null, escalated: false }, NOW);
  const auth = { authorization: `Bearer ${tok}` };

  const bad = await strict.handle('GET', '/v1/invites/not-a-uuid', {}, '');
  check('H strict ids', 'a malformed :inviteId is 400 bad_path (never a 500)', `${bad.status}/${bad.body.error}`, '400/bad_path');
  check('H strict ids', 'SQL-ish junk is 400 too', (await strict.handle('GET', "/v1/invites/1'%20OR%201=1", {}, '')).status, 400);
  check('H strict ids', 'an over-long id is 400', (await strict.handle('GET', '/v1/invites/' + 'a'.repeat(5000), {}, '')).status, 400);
  const ok = await strict.handle('GET', `/v1/invites/${UUID_A}`, {}, '');
  check('H strict ids', 'a real uuid reaches the handler', ok.body.got, UUID_A);
  check('H strict ids', 'an UPPERCASE uuid is accepted (Postgres accepts it)',
    (await strict.handle('GET', `/v1/invites/${UUID_A.toUpperCase()}`, {}, '')).status, 200);
  check('H strict ids', 'a non-uuid param that is NOT an id (:day) is untouched',
    (await strict.handle('GET', '/v1/learn/2026-11-08', auth, '')).body.day, '2026-11-08');
  check('H strict ids', 'strictIds is opt-in: the default Api still passes odd ids through (fake-id route tests rely on it)',
    (await loose.handle('GET', '/v1/invites/fake-id', {}, '')).body.got, 'fake-id');
  check('H strict ids', 'bodyLimitFor does not throw on a malformed id (it gets the small unauthenticated cap)',
    strict.bodyLimitFor('GET', '/v1/invites/not-a-uuid', {}) > 0, true);
  check('H strict ids', 'routeTemplate is null for a malformed id (no id lands in the access log)',
    strict.routeTemplate('GET', '/v1/invites/not-a-uuid'), null);

  let t = 0;
  const limited = new Api(secret, db, () => NOW, { writeLimiter: createWriteLimiter({
    env: { WRITE_RATE_CAPACITY: '2', WRITE_RATE_PER_MIN: '1' }, now: () => t }) });
  limited.register({ method: 'POST', path: '/v1/things', action: null, skipOuterSession: true,
    handler: async () => ({ body: { ok: true } }) });
  limited.register({ method: 'GET', path: '/v1/things', action: null, skipOuterSession: true,
    handler: async () => ({ body: { ok: true } }) });
  const statuses = [];
  for (let i = 0; i < 4; i++) statuses.push((await limited.handle('POST', '/v1/things', auth, '{}')).status);
  check('H write limit', 'the 3rd and 4th authenticated writes in a burst are 429', statuses.join(','), '200,200,429,429');
  const limitedBody = await limited.handle('POST', '/v1/things', auth, '{}');
  check('H write limit', 'the 429 names rate_limited and carries a retry hint', `${limitedBody.body.error}/${limitedBody.body.retryAfterSec >= 1}`, 'rate_limited/true');
  check('H write limit', 'reads are not write-limited', (await limited.handle('GET', '/v1/things', auth, '')).status, 200);
  check('H write limit', 'an unauthenticated write is a 401, not spending the bucket',
    (await limited.handle('POST', '/v1/things', {}, '{}')).status, 401);
}

// ===========================================================================
// I · S-B16 — session key id, two-key rotation, role allowlist
// ===========================================================================
{
  const k1 = randomBytes(32), k2 = randomBytes(32), k3 = randomBytes(32);
  const p = { userId: UUID_A, roleName: 'guardian', childId: null, escalated: false };
  const tok1 = issueSession(k1, p, NOW);
  const body = JSON.parse(Buffer.from(tok1.split('.')[0], 'base64url').toString('utf8'));
  check('I sessions', 'a token carries the id of the key that signed it', body.kid, keyId(k1));
  check('I sessions', 'key ids differ between keys', keyId(k1) !== keyId(k2), true);
  check('I sessions', 'a key id is short and not the key', keyId(k1).length, 8);
  check('I sessions', 'a plain Buffer secret still works (every existing caller)', readSession(k1, tok1, NOW).ok, true);
  check('I sessions', 'a wrong key is bad_signature', readSession(k2, tok1, NOW).reason, 'bad_signature');

  // rotation: deploy SESSION_SECRET=k2, SESSION_SECRET_PREVIOUS=k1
  const ring = { current: k2, previous: k1 };
  check('I rotation', 'a token signed by the PREVIOUS key still verifies during rotation', readSession(ring, tok1, NOW).ok, true);
  const tok2 = issueSession(ring, p, NOW);
  check('I rotation', 'new tokens are signed with the CURRENT key', JSON.parse(Buffer.from(tok2.split('.')[0], 'base64url').toString()).kid, keyId(k2));
  check('I rotation', 'and verify under the ring', readSession(ring, tok2, NOW).ok, true);
  check('I rotation', 'once the previous key is dropped, old tokens stop verifying',
    readSession({ current: k2, previous: null }, tok1, NOW).reason, 'bad_signature');
  check('I rotation', 'a token from an unrelated key is refused by the ring', readSession(ring, issueSession(k3, p, NOW), NOW).reason, 'bad_signature');
  check('I rotation', 'a token that names another key id cannot be verified with the wrong key',
    readSession({ current: k2, previous: k1 }, (() => {
      // payload says kid=k1 but is MAC'd by k2: must NOT verify (the kid only selects the key to try)
      const pl = Buffer.from(JSON.stringify({ ...p, exp: NOW + 1000, kid: keyId(k1) })).toString('base64url');
      return `${pl}.${createHmac('sha256', k2).update(pl).digest('base64url')}`;
    })(), NOW).ok, false);

  // legacy (pre-kid) token: payload without kid, MAC'd by the current key
  const legacyPayload = Buffer.from(JSON.stringify({ ...p, exp: NOW + 60_000 })).toString('base64url');
  const legacy = `${legacyPayload}.${createHmac('sha256', k1).update(legacyPayload).digest('base64url')}`;
  check('I sessions', 'a pre-kid token still verifies (no forced sign-out on deploy)', readSession(k1, legacy, NOW).ok, true);
  check('I sessions', 'an expired token is expired', readSession(k1, issueSession(k1, p, NOW - 7_200_000), NOW).reason, 'expired');

  const forge = (extra) => {
    const pl = Buffer.from(JSON.stringify({ ...p, ...extra, exp: NOW + 60_000, kid: keyId(k1) })).toString('base64url');
    return `${pl}.${createHmac('sha256', k1).update(pl).digest('base64url')}`;
  };
  check('I roles', 'a correctly SIGNED token naming role `system` is refused', readSession(k1, forge({ roleName: 'system' }), NOW).reason, 'bad_role');
  check('I roles', 'so is an arbitrary role name', readSession(k1, forge({ roleName: 'root' }), NOW).reason, 'bad_role');
  check('I roles', 'and a missing role', readSession(k1, forge({ roleName: undefined }), NOW).reason, 'bad_role');
  check('I roles', 'the allowlist has exactly the nine human roles',
    [...SESSION_ROLES].sort().join(','), 'caseworker,child,coordinator,foster_parent,guardian,sitter,step_parent,therapist,trusted_adult');
  for (const r of ['guardian', 'sitter', 'trusted_adult']) {
    check('I roles', `role ${r} is accepted`, readSession(k1, forge({ roleName: r }), NOW).ok, true);
  }
  check('I roles', 'child needs a childId',
    readSession(k1, forge({ roleName: 'child', childId: null, userId: null }), NOW).reason, 'child_without_child_id');
}

// ===========================================================================
// J · S-B3 — security-event wording is fixed server-side
// ===========================================================================
{
  check('J summaries', 'child device pairing', securityEventSummary('device_paired', 'child'), 'A child device was paired');
  check('J summaries', 'guardian device pairing', securityEventSummary('device_paired', 'guardian'), 'A guardian device was paired');
  check('J summaries', 'an unknown variant falls back to the base wording, never echoing the input',
    securityEventSummary('device_paired', "x'; DROP TABLE message_log; --"), 'A device was paired');
  check('J summaries', 'raw export wording', securityEventSummary('export_taken', 'raw'), 'A raw export of the family records was taken');
  check('J summaries', 'every kind has a wording',
    ['passkey_added', 'passkey_removed', 'pin_changed', 'pin_lockout', 'device_paired', 'export_taken', 'invite_created']
      .every((k) => typeof securityEventSummary(k) === 'string' && securityEventSummary(k).length > 0), true);
  check('J summaries', 'no wording contains a digit-run, email or hex blob (content-free)',
    ['passkey_added', 'passkey_removed', 'pin_changed', 'pin_lockout', 'device_paired', 'export_taken', 'invite_created']
      .every((k) => !/\d{3,}|@|[0-9a-f]{16}/i.test(securityEventSummary(k))), true);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
