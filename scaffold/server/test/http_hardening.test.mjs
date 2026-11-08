/**
 * HTTP-layer hardening (audit P-05, P-07 server half, P-08, P-19).
 *
 * No database needed: every case here is decided before a query runs, so the
 * real server/index.mjs is spawned against an UNREACHABLE database URL on
 * purpose (that also proves the hardening does not depend on Postgres being
 * up -- /healthz honestly reports 503 while everything below still works).
 *
 *   A. Body integrity (P-05): byte-exact UTF-8 round trip, in every chunking,
 *      through the real Api.listen(); the cap counts BYTES.
 *   B. Unauthenticated body cap (P-08): 413 for an anonymous caller, the big
 *      cap only for a verifying session; Content-Length checked up front.
 *   C. Malformed percent escape in a route param is a 400, not a 500 (P-19).
 *   D. Rate limit on /v1/auth/* (P-08): per-IP and per-identifier buckets,
 *      Retry-After, isolation between identifiers, and a 429 never consumes
 *      the wrong bucket. Unit-level bucket math with an injected clock.
 *   E. Observability (P-07): one JSON line per request, request id echoed,
 *      route TEMPLATE not the concrete URL (no ids in logs), counters behind
 *      the internal-only guard.
 *   F. Uniform login challenge for a non-uuid id (P-08; the real-user vs
 *      unknown-user comparison needs Postgres and lives in
 *      packages/db/test/auth_hardening.test.mjs).
 */
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { EventEmitter } from 'node:events';
import net from 'node:net';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { readFileSync } from 'node:fs';
import { Api, readRequestBody, MAX_UNAUTH_BODY_BYTES, MAX_REQUEST_BODY_BYTES }
  from '../../packages/api/src/api.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { TokenBuckets, createAuthLimiter, clientIp } from '../rate_limit.mjs';
import { Metrics, accessLogLine, isInternalRequest, requestIdFor } from '../observability.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const sha = (b) => createHash('sha256').update(b).digest('hex');

const here = dirname(fileURLToPath(import.meta.url));
const serverEntry = join(here, '..', 'index.mjs');

// ===========================================================================
// A · body integrity, through the REAL Api.listen().
// ===========================================================================
const SECRET = Buffer.from('h'.repeat(32), 'utf8');
const USER = '11111111-1111-4111-9111-0000000000aa';
const fakeDb = {
  edgesFor: async () => [],
  isDeviceRevoked: async () => false,
  withSession: async (_p, fn) => fn(async () => []),
};
const api = new Api(SECRET, fakeDb);
api.register({
  method: 'POST', path: '/v1/echo', action: null, skipOuterSession: true,
  handler: async (c) => ({ body: { len: c.body.s.length, sha: sha(Buffer.from(c.body.s, 'utf8')) } }),
});
api.register({
  method: 'POST', path: '/v1/anon-echo', action: null, skipOuterSession: true, noSessionRequired: true,
  handler: async (c) => ({ body: { len: String(c.body?.s ?? '').length } }),
});
api.register({
  method: 'GET', path: '/v1/children/:childId/thing', action: null, identityScopedByHandler: true,
  skipOuterSession: true, handler: async (c) => ({ body: { childId: c.childId } }),
});
const tok = issueSession(SECRET, { userId: USER, roleName: 'guardian', childId: null, escalated: false },
  Date.now());
const srv = await api.listen(0);
const base = `http://127.0.0.1:${srv.port}`;

/** POST `buf` in fixed-size chunks over a raw socket so chunk boundaries are EXACTLY what we choose. */
function rawPost(path, buf, { chunk, token, extraHeaders = '' }) {
  return new Promise((resolve) => {
    const s = net.connect(srv.port, '127.0.0.1');
    let data = '';
    s.on('data', (d) => { data += d.toString('utf8'); });
    s.on('close', () => resolve(data));
    s.on('error', () => resolve(data));
    s.on('connect', async () => {
      s.setNoDelay(true);
      s.write(`POST ${path} HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n` +
        (token ? `Authorization: Bearer ${token}\r\n` : '') + extraHeaders +
        `Content-Length: ${buf.length}\r\nConnection: close\r\n\r\n`);
      for (let i = 0; i < buf.length; i += chunk) {
        if (!s.write(buf.subarray(i, i + chunk))) await new Promise((r) => s.once('drain', r));
      }
    });
  });
}
const parseHttp = (raw) => {
  const status = Number(/^HTTP\/1\.1 (\d+)/.exec(raw)?.[1] ?? 0);
  const body = raw.split('\r\n\r\n').slice(1).join('\r\n\r\n');
  let json = null; try { json = JSON.parse(body.replace(/^[0-9a-f]+\r\n/i, '').replace(/\r\n0\r\n\r\n$/, '')); } catch {}
  return { status, json, raw };
};

{
  // The reproduced audit case: 200,008 'é' (2 bytes each) -> 400,016 bytes.
  const s = 'é'.repeat(200_008);
  const payload = Buffer.from(JSON.stringify({ s }), 'utf8');
  for (const chunk of [1_000_003, 65_537, 16_383, 7, 3, 1]) {
    // Tiny chunk sizes over 400 KB would be hundreds of thousands of writes;
    // the odd tiny sizes use a slice of the body (still crossing every
    // multi-byte boundary), the large sizes use the full reproduced body.
    const small = chunk <= 7;
    const text = small ? 'é€😀'.repeat(300) : s;
    const body = small ? Buffer.from(JSON.stringify({ s: text }), 'utf8') : payload;
    const out = parseHttp(await rawPost('/v1/echo', body, { chunk, token: tok }));
    check('A body integrity', `non-ASCII body survives ${chunk}-byte chunks byte-exact (${text.length} chars)`,
      `${out.status}/${out.json?.len}/${out.json?.sha}`,
      `200/${text.length}/${sha(Buffer.from(text, 'utf8'))}`);
  }
  check('A body integrity', 'no U+FFFD replacement characters appear in the decoded body',
    parseHttp(await rawPost('/v1/echo', Buffer.from(JSON.stringify({ s: '€😀é'.repeat(40) }), 'utf8'),
      { chunk: 2, token: tok })).json?.sha,
    sha(Buffer.from('€😀é'.repeat(40), 'utf8')));
}

{
  // readRequestBody directly, with a fake request splitting EVERY byte.
  const mk = (chunks, headers = {}) => {
    const req = new EventEmitter(); req.headers = headers;
    setImmediate(() => { for (const c of chunks) req.emit('data', c); req.emit('end'); });
    return req;
  };
  const text = '{"s":"é€😀 ünï"}';
  const bytes = Buffer.from(text, 'utf8');
  const split = [...bytes].map((b) => Buffer.from([b]));
  const r = await readRequestBody(mk(split), 1_000);
  check('A body integrity', 'a body split at EVERY byte (incl. inside 2/3/4-byte sequences) decodes exactly',
    r.ok && r.body === text, 'true');

  // The cap counts BYTES. 600 'é' is 600 chars but 1,200 bytes: a char-count
  // cap of 1,000 (the old `raw.length`) would have admitted it.
  const big = await readRequestBody(mk([Buffer.from('é'.repeat(600), 'utf8')]), 1_000);
  check('A body integrity', 'the cap counts bytes: 600 chars of "é" (1,200 bytes) exceeds a 1,000-byte cap',
    big.ok === false && big.reason === 'too_large', 'true');
  const exact = await readRequestBody(mk([Buffer.from('a'.repeat(1_000))]), 1_000);
  check('A body integrity', 'a body of exactly the cap is accepted (off-by-one guard)', exact.ok, 'true');
  const over = await readRequestBody(mk([Buffer.from('a'.repeat(1_001))]), 1_000);
  check('A body integrity', 'one byte over the cap is refused', over.ok, 'false');
  const cl = await readRequestBody(mk([], { 'content-length': '5000' }), 1_000);
  check('A body integrity', 'a Content-Length already over the cap is refused before any body is read',
    cl.ok === false && cl.reason === 'too_large', 'true');
  const aborted = await readRequestBody((() => {
    const req = new EventEmitter(); req.headers = {};
    setImmediate(() => { req.emit('data', Buffer.from('{"par')); req.emit('aborted'); });
    return req;
  })(), 1_000);
  check('A body integrity', 'an aborted upload is NOT processed as a complete (truncated) body',
    aborted.ok === false && aborted.reason === 'aborted', 'true');
}

// ===========================================================================
// B · unauthenticated body cap.
// ===========================================================================
{
  check('B unauth cap', 'unauthenticated cap is the small 16 KiB default', MAX_UNAUTH_BODY_BYTES, 16 * 1024);
  check('B unauth cap', 'authenticated cap is still the large one (media/homework uploads)',
    MAX_REQUEST_BODY_BYTES > 1024 * 1024, 'true');
  const big = Buffer.from(JSON.stringify({ s: 'x'.repeat(20_000) }));
  const anon = parseHttp(await rawPost('/v1/anon-echo', big, { chunk: 4096 }));
  check('B unauth cap', 'a 20 KB body to a noSessionRequired route is refused 413', anon.status, 413);
  check('B unauth cap', '...with a named reason', anon.json?.error, 'payload_too_large');
  const noTok = parseHttp(await rawPost('/v1/echo', big, { chunk: 4096 }));
  check('B unauth cap', 'a 20 KB body with NO token is refused 413 before any handler runs', noTok.status, 413);
  const badTok = parseHttp(await rawPost('/v1/echo', big, { chunk: 4096, token: 'forged.token' }));
  check('B unauth cap', 'a 20 KB body with a FORGED token is refused 413 (cap keyed on a verified session)',
    badTok.status, 413);
  const good = parseHttp(await rawPost('/v1/echo', big, { chunk: 4096, token: tok }));
  check('B unauth cap', 'the same 20 KB body with a verifying session is served', good.status, 200);
  const small = parseHttp(await rawPost('/v1/anon-echo',
    Buffer.from(JSON.stringify({ s: 'x'.repeat(100) })), { chunk: 4096 }));
  check('B unauth cap', 'a small anonymous body still works', `${small.status}/${small.json?.len}`, '200/100');
  const noRoute = parseHttp(await rawPost('/v1/nope', big, { chunk: 4096, token: tok }));
  check('B unauth cap', 'a body sent to a path with no route is capped small too', noRoute.status, 413);
  const clOnly = parseHttp(await rawPost('/v1/anon-echo', Buffer.alloc(0), { chunk: 1,
    extraHeaders: 'X-Pad: 1\r\n' }));
  check('B unauth cap', 'an empty anonymous POST is not refused as oversized', clOnly.status !== 413, 'true');
}

// ===========================================================================
// C · malformed percent escapes -> 400.
// ===========================================================================
{
  const r = await api.handle('GET', '/v1/children/%E0%A4%A/thing', { authorization: `Bearer ${tok}` }, '');
  check('C malformed path', 'a malformed percent escape in a route param is 400, not a thrown URIError',
    `${r.status}/${r.body.error}`, '400/bad_path');
  const lone = await api.handle('GET', '/v1/children/%/thing', { authorization: `Bearer ${tok}` }, '');
  check('C malformed path', 'a lone % is 400 too', lone.status, 400);
  const ok = await api.handle('GET', '/v1/children/abc%20def/thing', { authorization: `Bearer ${tok}` }, '');
  check('C malformed path', 'a VALID escape still decodes ("abc def")', `${ok.status}/${ok.body.childId}`, '200/abc def');
  check('C malformed path', 'routeTemplate() returns the registered template, never the concrete URL',
    api.routeTemplate('GET', '/v1/children/some-child-id/thing'), '/v1/children/:childId/thing');
  check('C malformed path', 'routeTemplate() of a malformed path / unknown path is null (no raw URL)',
    `${api.routeTemplate('GET', '/v1/children/%/thing')}/${api.routeTemplate('GET', '/zzz')}`, 'null/null');
}
await srv.close();

// ===========================================================================
// D · rate limiting.
// ===========================================================================
{
  let t = 1_000_000;
  const b = new TokenBuckets({ capacity: 3, refillPerSec: 1, now: () => t });
  const seq = [b.take('a').ok, b.take('a').ok, b.take('a').ok, b.take('a').ok];
  check('D rate limit', 'a bucket allows exactly `capacity` then refuses', seq.join(','), 'true,true,true,false');
  check('D rate limit', 'the refusal carries a Retry-After of at least 1 s', b.take('a').retryAfterSec >= 1, 'true');
  check('D rate limit', 'another key is unaffected', b.take('b').ok, 'true');
  t += 2_000;
  check('D rate limit', 'tokens refill with time (2 s -> 2 tokens)',
    [b.take('a').ok, b.take('a').ok, b.take('a').ok].join(','), 'true,true,false');
  t += 60_000;
  const full = [b.take('a'), b.take('a'), b.take('a'), b.take('a')].map((x) => x.ok).join(',');
  check('D rate limit', 'refill is capped at capacity (no banked credit beyond it)', full, 'true,true,true,false');

  const small = new TokenBuckets({ capacity: 1, refillPerSec: 1, maxKeys: 50, now: () => t });
  for (let i = 0; i < 500; i++) small.take(`k${i}`);
  check('D rate limit', 'the key map is bounded (500 distinct keys, cap 50)', small.size <= 50, 'true');

  const lim = createAuthLimiter({ env: { AUTH_RATE_IP_CAPACITY: '2', AUTH_RATE_ID_CAPACITY: 'abc' }, now: () => t });
  check('D rate limit', 'env overrides apply and an invalid value falls back to the default',
    `${lim.byIp.capacity}/${lim.byId.capacity}`, '2/10');
  const long = lim.checkIdentifier('x'.repeat(100_000));
  check('D rate limit', 'an enormous identifier is clamped (no key-space bloat)', long.ok &&
    [...lim.byId.buckets.keys()][0].length <= 3 + 128, 'true');

  const mkReq = (headers, addr) => ({ headers, socket: { remoteAddress: addr } });
  check('D rate limit', 'X-Forwarded-For is IGNORED by default (a direct caller cannot dodge the per-IP bucket)',
    clientIp(mkReq({ 'x-forwarded-for': '9.9.9.9' }, '10.0.0.5'), {}), '10.0.0.5');
  check('D rate limit', 'with TRUST_PROXY=1 the RIGHTMOST (proxy-observed) address is used',
    clientIp(mkReq({ 'x-forwarded-for': '1.1.1.1, 2.2.2.2' }, '10.0.0.5'), { TRUST_PROXY: '1' }), '2.2.2.2');
}

// ---- spawned-server helpers ------------------------------------------------
const DEAD_DB = 'postgres://nobody:nopass@127.0.0.1:9/none';
async function boot(env = {}) {
  const port = 24000 + Math.floor(Math.random() * 3000);
  const child = spawn(process.execPath, [serverEntry], {
    env: { ...process.env, DATABASE_URL: DEAD_DB, SESSION_SECRET: 'h'.repeat(40), PORT: String(port),
      DB_CONNECTION_TIMEOUT_MS: '1000', ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d.toString(); });
  child.stderr.on('data', (d) => { out += d.toString(); });
  const deadline = Date.now() + 60_000;
  while (!out.includes('listening on') && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
  return {
    port, child, base: `http://127.0.0.1:${port}`,
    logs: () => out.split('\n').filter((l) => l.startsWith('{')).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean),
    stop: async () => { child.kill(); await new Promise((r) => setTimeout(r, 150)); },
  };
}
const postJson = (base, path, body, headers = {}) => fetch(base + path, {
  method: 'POST', headers: { 'content-type': 'application/json', ...headers },
  body: typeof body === 'string' ? body : JSON.stringify(body),
});

{
  // Per-identifier: IP bucket huge, identifier bucket 3, ~no refill.
  const s = await boot({ AUTH_RATE_IP_CAPACITY: '1000', AUTH_RATE_ID_CAPACITY: '3', AUTH_RATE_ID_PER_MIN: '1' });
  const statuses = [];
  for (let i = 0; i < 5; i++) {
    statuses.push((await postJson(s.base, '/v1/auth/dev-login', { userId: 'victim' })).status);
  }
  check('D rate limit', 'hammering ONE identifier: first 3 reach the handler (404 dev-login off), the rest are 429',
    statuses.join(','), '404,404,404,429,429');
  const other = await postJson(s.base, '/v1/auth/dev-login', { userId: 'someone-else' });
  check('D rate limit', 'a DIFFERENT identifier is not throttled by the first one', other.status, 404);
  const lim429 = await postJson(s.base, '/v1/auth/dev-login', { userId: 'victim' });
  check('D rate limit', 'a 429 names the reason and carries Retry-After',
    `${lim429.status}/${(await lim429.json()).error}/${Number(lim429.headers.get('retry-after')) >= 1}`,
    '429/rate_limited/true');
  const ch = await postJson(s.base, '/v1/auth/webauthn/login/challenge', { userId: 'victim' });
  check('D rate limit', 'the identifier bucket is shared across the /v1/auth/ login routes', ch.status, 429);
  await s.stop();
}
{
  // Per-IP: identifiers all distinct, IP bucket 4, ~no refill.
  const s = await boot({ AUTH_RATE_IP_CAPACITY: '4', AUTH_RATE_IP_PER_MIN: '1', AUTH_RATE_ID_CAPACITY: '1000' });
  const statuses = [];
  for (let i = 0; i < 6; i++) {
    statuses.push((await postJson(s.base, '/v1/auth/dev-login', { userId: `u${i}` })).status);
  }
  check('D rate limit', 'one IP cycling through distinct identifiers is stopped by the per-IP bucket',
    statuses.join(','), '404,404,404,404,429,429');
  const healthz = await fetch(s.base + '/healthz');
  check('D rate limit', 'the throttle is scoped to /v1/auth/*: /healthz is unaffected', healthz.status, 503);
  const authed = await postJson(s.base, '/v1/children/x/messages', {});
  check('D rate limit', 'and so are non-auth API routes (401, not 429)', authed.status, 401);
  await s.stop();
}

// ===========================================================================
// B/E · body cap + observability through the REAL server.
// ===========================================================================
{
  const s = await boot({ DEV_LOGIN: '1' });
  const big = await postJson(s.base, '/v1/auth/dev-login', JSON.stringify({ userId: 'u', pad: 'x'.repeat(20_000) }));
  check('B unauth cap', 'the real server refuses a 20 KB login body with 413 payload_too_large',
    `${big.status}/${(await big.json()).error}`, '413/payload_too_large');
  const after = await postJson(s.base, '/v1/auth/dev-login', { userId: 'u' });
  check('B unauth cap', 'the server keeps serving after refusing an oversized body', after.status !== 413 && after.status !== 0, 'true');

  const r1 = await fetch(s.base + '/v1/children/11111111-1111-4111-9111-000000000002/expenses');
  const id1 = r1.headers.get('x-request-id');
  check('E observability', 'every response carries an x-request-id header', /^[0-9a-f-]{36}$/.test(id1 ?? ''), 'true');
  const r2 = await fetch(s.base + '/v1/me', { headers: { 'x-request-id': 'client-corr-12345' } });
  check('E observability', 'a short, plain inbound request id is echoed back for correlation',
    r2.headers.get('x-request-id'), 'client-corr-12345');
  const r3 = await fetch(s.base + '/v1/me', { headers: { 'x-request-id': 'evil\tid with spaces & "quotes"' } });
  check('E observability', 'an unsafe inbound request id is replaced, never reflected into a log line',
    /^[0-9a-f-]{36}$/.test(r3.headers.get('x-request-id') ?? ''), 'true');

  await new Promise((r) => setTimeout(r, 200));
  const logs = s.logs().filter((l) => l.msg === 'request');
  const line = logs.find((l) => l.id === id1);
  check('E observability', 'one JSON access-log line exists for the request, with the same id', Boolean(line), 'true');
  check('E observability', 'it has method, status and a numeric latency',
    `${line?.method}/${line?.status}/${typeof line?.ms}`, 'GET/401/number');
  check('E observability', 'route is the TEMPLATE -- no child id and no query string in the log',
    line?.route, '/v1/children/:childId/expenses');
  check('E observability', 'no concrete child id appears anywhere in the log line',
    JSON.stringify(line).includes('11111111-1111-4111'), 'false');
  const unmatched = await fetch(s.base + '/some/attacker/chosen/path?token=secret');
  await new Promise((r) => setTimeout(r, 150));
  const l2 = s.logs().filter((l) => l.msg === 'request').pop();
  check('E observability', 'an unmatched path logs the fixed label "unmatched", never the attacker-chosen path',
    `${unmatched.status}/${l2.route}/${JSON.stringify(l2).includes('secret')}`, '404/unmatched/false');
  check('E observability', 'the oversized-body request was logged with its 413',
    s.logs().some((l) => l.route === '/v1/auth/dev-login' && l.status === 413), 'true');

  const m = await fetch(s.base + '/internal/metrics');
  const snap = await m.json();
  check('E observability', 'GET /internal/metrics from loopback returns the counters', m.status, 200);
  check('E observability', 'counters include requests_total, status classes and per-route stats',
    `${snap.requests_total > 3}/${snap.by_status_class['4xx'] >= 2}/${snap.routes['GET /v1/me']?.count}`, 'true/true/2');
  check('E observability', 'counters include the pool gauge and body_too_large_total',
    `${typeof snap.pool.total}/${snap.counters.body_too_large_total}`, 'number/1');
  const viaProxy = await fetch(s.base + '/internal/metrics', { headers: { 'x-forwarded-for': '203.0.113.9' } });
  check('E observability', 'a request that came through a reverse proxy (X-Forwarded-For) is refused: 404, not 403',
    `${viaProxy.status}/${(await viaProxy.json()).error}`, '404/not_found');
  const health = await fetch(s.base + '/healthz');
  check('E observability', '/healthz still reports an unreachable database honestly (503) and quickly',
    health.status, 503);
  await s.stop();
}
{
  const s = await boot({ INTERNAL_METRICS_TOKEN: 'scrape-token-123' });
  const none = await fetch(s.base + '/internal/metrics');
  const wrong = await fetch(s.base + '/internal/metrics', { headers: { 'x-internal-token': 'nope' } });
  const right = await fetch(s.base + '/internal/metrics', { headers: { 'x-internal-token': 'scrape-token-123' } });
  check('E observability', 'with INTERNAL_METRICS_TOKEN set: no token -> 404, wrong token -> 404, right token -> 200',
    `${none.status}/${wrong.status}/${right.status}`, '404/404/200');
  await s.stop();
}
{
  // The guard and the log helpers as pure units.
  const loop = { headers: {}, socket: { remoteAddress: '127.0.0.1' } };
  const v6 = { headers: {}, socket: { remoteAddress: '::1' } };
  const mapped = { headers: {}, socket: { remoteAddress: '::ffff:127.0.0.1' } };
  const lan = { headers: {}, socket: { remoteAddress: '192.168.1.50' } };
  const pub = { headers: {}, socket: { remoteAddress: '203.0.113.7' } };
  check('E observability', 'isInternalRequest: loopback v4/v6/mapped allowed; LAN and public refused',
    [loop, v6, mapped, lan, pub].map((r) => isInternalRequest(r, {})).join(','), 'true,true,true,false,false');
  check('E observability', 'isInternalRequest: Forwarded / X-Real-IP headers also mark a proxied request',
    [{ forwarded: 'for=1.2.3.4' }, { 'x-real-ip': '1.2.3.4' }]
      .map((h) => isInternalRequest({ headers: h, socket: loop.socket }, {})).join(','), 'false,false');
  const line = JSON.parse(accessLogLine({ id: 'abc', method: 'GET', route: '/r', status: 200, ms: 12.345, now: 0 }));
  check('E observability', 'accessLogLine is single-line JSON with the documented fields',
    Object.keys(line).join(','), 'ts,level,msg,id,method,route,status,ms');
  check('E observability', 'requestIdFor mints a uuid when none is supplied',
    /^[0-9a-f-]{36}$/.test(requestIdFor({ headers: {} })), 'true');
  const mm = new Metrics(() => 5000);
  mm.record({ method: 'GET', route: '/a', status: 500, ms: 10 });
  mm.record({ method: 'GET', route: '/a', status: 200, ms: 30 });
  const snap = mm.snapshot();
  check('E observability', 'Metrics aggregates count / 5xx / avg / max per route',
    `${snap.routes['GET /a'].count}/${snap.routes['GET /a'].errors_5xx}/${snap.routes['GET /a'].ms_avg}/${snap.routes['GET /a'].ms_max}`,
    '2/1/20/30');
}

// ===========================================================================
// F · uniform login challenge for a malformed id; process-level handlers wired.
// ===========================================================================
{
  const s = await boot();
  const a = await postJson(s.base, '/v1/auth/webauthn/login/challenge', { userId: 'not-a-uuid' });
  const aj = await a.json();
  check('F uniform login', 'a malformed userId gets 200 + a challenge, not 404 user_not_found / a 500',
    `${a.status}/${typeof aj.challenge}/${typeof aj.rpId}`, '200/string/string');
  const b = await postJson(s.base, '/v1/auth/webauthn/login/challenge', { userId: "' OR 1=1 --" });
  check('F uniform login', 'an injection-shaped id gets the identical response shape',
    `${b.status}/${Object.keys(await b.json()).join(',')}`, `200/${Object.keys(aj).join(',')}`);
  check('F uniform login', 'decoy challenges are fresh and unguessable (distinct, 43-char base64url)',
    `${aj.challenge !== (await (await postJson(s.base, '/v1/auth/webauthn/login/challenge', { userId: 'x' })).json()).challenge}/${aj.challenge.length}`,
    'true/43');
  const none = await postJson(s.base, '/v1/auth/webauthn/login/challenge', {});
  check('F uniform login', 'a missing userId is still a plain 400 (input validation, not an account oracle)',
    none.status, 400);
  await s.stop();
}
{
  const src = readFileSync(serverEntry, 'utf8');
  check('F process handlers', 'server/index.mjs registers an unhandledRejection handler',
    /process\.on\('unhandledRejection'/.test(src), 'true');
  check('F process handlers', 'server/index.mjs registers an uncaughtException handler that shuts down',
    /process\.on\('uncaughtException'[\s\S]*shutdown\('uncaughtException'\)/.test(src), 'true');
  check('F process handlers', 'SIGINT and SIGTERM both route through the one idempotent shutdown()',
    /process\.on\('SIGINT'[\s\S]*onSignal\('SIGINT'\)[\s\S]*process\.on\('SIGTERM'[\s\S]*onSignal\('SIGTERM'\)/.test(src), 'true');
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
