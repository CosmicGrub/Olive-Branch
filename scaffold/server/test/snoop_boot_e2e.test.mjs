/**
 * server/test/snoop_boot_e2e.test.mjs — the transport and fingerprinting
 * guarantees against the REAL booted server process (node server/index.mjs) and
 * REAL Postgres (server-snoop hardening, spec 4.1/4.3/4.4):
 *
 *   A  a production process with a bad deployment shape refuses to start
 *   B  production serves nothing over plain HTTP; the loopback probes still work
 *   C  headers on every response; CORS stays closed
 *   D  fingerprinting: generic 404s, no banner, no stack, same-shape healthz
 *   E  what the process prints: no address, no query, no token, no body
 */
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import net from 'node:net';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import WebSocket from 'ws';

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.'); process.exit(2); }
let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const INDEX = fileURLToPath(new URL('../index.mjs', import.meta.url));
const hex = () => randomBytes(32).toString('hex');

async function freePort() {
  const s = createServer(); s.listen(0, '127.0.0.1'); await once(s, 'listening');
  const p = s.address().port; s.close(); await once(s, 'close'); return p;
}

/** Boots the real server; resolves once it prints its listening line or exits. */
async function boot(extraEnv) {
  const port = await freePort();
  const env = {
    PATH: process.env.PATH, SystemRoot: process.env.SystemRoot,
    PORT: String(port), DATABASE_URL, SESSION_SECRET: hex(), MEDIA_SIGNING_SECRET: hex(),
    LIVEKIT_URL: 'wss://x.invalid', LIVEKIT_API_KEY: 'devkey', LIVEKIT_API_SECRET: 'devsecret_at_least_32_chars_long_xx',
    // This suite is about transport and logging, and CI connects it as app_owner; the database-role
    // boot check (S-B11) has its own suite, tools/test/runtime_role.test.mjs.
    ALLOW_OWNER_DB_ROLE: '1',
    ...extraEnv,
  };
  const child = spawn(process.execPath, [INDEX], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  let out = '', err = '';
  child.stdout.on('data', (d) => { out += d; });
  child.stderr.on('data', (d) => { err += d; });
  const ready = await new Promise((resolve) => {
    const iv = setInterval(() => { if (/listening on/.test(out)) { clearInterval(iv); resolve('up'); } }, 25);
    child.on('exit', (code) => { clearInterval(iv); resolve(`exit:${code}`); });
    setTimeout(() => { clearInterval(iv); resolve('timeout'); }, 15000);
  });
  return {
    port, child, ready, out: () => out, err: () => err,
    stop: async () => { if (child.exitCode === null) { child.kill('SIGTERM'); await Promise.race([once(child, 'exit'), new Promise((r) => setTimeout(r, 3000))]); if (child.exitCode === null) child.kill('SIGKILL'); } },
  };
}
const get = (port, path, { method = 'GET', headers = {}, body } = {}) =>
  fetch(`http://127.0.0.1:${port}${path}`, { method, headers, body }).then(async (r) => ({
    status: r.status, headers: r.headers, text: await r.text() }));
const j = (r) => { try { return JSON.parse(r.text); } catch { return null; } };

const PROD = {
  NODE_ENV: 'production', PUBLIC_BASE_URL: 'https://api.example.com', TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1',
};

// ---- A · refuses to start --------------------------------------------------
{
  const a = await boot({ NODE_ENV: 'production', PUBLIC_BASE_URL: undefined, TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1' });
  check('A boot', 'production without PUBLIC_BASE_URL exits 2', a.ready, 'exit:2');
  check('A boot', '...and says why on stderr', /transport check failed: PUBLIC_BASE_URL required/.test(a.err()), 'true');
  await a.stop();
  const b = await boot({ ...PROD, TRUST_PROXY: undefined });
  check('A boot', 'production without TRUST_PROXY=1 exits 2', b.ready, 'exit:2');
  const c = await boot({ ...PROD, PUBLIC_BASE_URL: 'http://api.example.com' });
  check('A boot', 'production with an http:// PUBLIC_BASE_URL exits 2', c.ready, 'exit:2');
  const d = await boot({ ...PROD, DATABASE_URL: 'postgres://u:p@db.example.net:5432/x' });
  check('A boot', 'production with a remote DB and no sslmode exits 2', d.ready, 'exit:2');
  const e = await boot({ ...PROD, DEV_LOGIN: '1' });
  check('A boot', 'production with DEV_LOGIN=1 still exits 2', e.ready, 'exit:2');
  const f = await boot({ NODE_ENV: 'development' });
  check('A boot', 'development with none of the new variables still boots', f.ready, 'up');
  await f.stop();
}

// ---- B..E · a correctly configured production process ---------------------
const prod = await boot(PROD);
check('B tls', 'a correctly configured production process boots', prod.ready, 'up');
const P = prod.port;
const XFP = { 'x-forwarded-proto': 'https', 'x-forwarded-for': '198.51.100.77' };
{
  const plain = await get(P, '/v1/me');
  check('B tls', 'plain HTTP to a normal route: 400 https_required (never content)', `${plain.status}/${j(plain)?.error}`, '400/https_required');
  check('B tls', '...with no HSTS (it would be ignored over http)', plain.headers.has('strict-transport-security'), 'false');
  const plainPost = await get(P, '/v1/auth/session/refresh', { method: 'POST', body: '{"deviceId":"x","deviceCredential":"y"}' });
  check('B tls', 'plain HTTP POST is refused before its body is processed', `${plainPost.status}/${j(plainPost)?.error}`, '400/https_required');
  const viaProxyHttp = await get(P, '/v1/me', { headers: { 'x-forwarded-proto': 'http' } });
  check('B tls', 'a proxy reporting http is refused too', j(viaProxyHttp)?.error, 'https_required');
  const ok = await get(P, '/v1/me', { headers: XFP });
  check('B tls', 'a proxy reporting https is served (401 no_session without a token)', `${ok.status}/${j(ok)?.error}`, '401/no_session');
  const hz = await get(P, '/healthz');
  check('B tls', 'the loopback /healthz probe (Docker healthcheck) works over plain HTTP', `${hz.status}/${j(hz)?.status}`, '200/ok');
  const hzProxied = await get(P, '/healthz', { headers: { 'x-forwarded-for': '198.51.100.77' } });
  check('B tls', 'a /healthz that came through a proxy over http is refused', j(hzProxied)?.error, 'https_required');
  const m = await get(P, '/internal/metrics');
  check('B tls', 'the loopback metrics scrape works', m.status, 200);
  const mp = await get(P, '/internal/metrics', { headers: XFP });
  check('B tls', '/internal/metrics through the proxy is a generic 404 (never public)', `${mp.status}/${j(mp)?.error}`, '404/not_found');
  const dl = await get(P, '/v1/auth/dev-login', { method: 'POST', headers: XFP, body: '{"userId":"x"}' });
  check('B tls', 'dev-login does not exist in production', `${dl.status}/${j(dl)?.error}`, '404/not_found');
  const ws = new WebSocket(`ws://127.0.0.1:${P}/v1/game-tables/t_x/socket`, ['olive.v1', 'a.b']);
  const wsr = await new Promise((r) => { ws.on('error', () => r('refused')); ws.on('open', () => r('open')); });
  check('B tls', 'a plain-http WebSocket upgrade is destroyed', wsr, 'refused');
}

// ---- C · headers + CORS ------------------------------------------------------
{
  const r = await get(P, '/v1/me', { headers: XFP });
  const h = r.headers;
  check('C headers', 'HSTS: 2 years, includeSubDomains, no preload by default', h.get('strict-transport-security'), 'max-age=63072000; includeSubDomains');
  check('C headers', 'nosniff', h.get('x-content-type-options'), 'nosniff');
  check('C headers', 'frame deny', h.get('x-frame-options'), 'DENY');
  check('C headers', 'referrer none', h.get('referrer-policy'), 'no-referrer');
  check('C headers', 'CSP default-src none', h.get('content-security-policy'), "default-src 'none'; frame-ancestors 'none'");
  check('C headers', 'authenticated-surface JSON is no-store', h.get('cache-control'), 'no-store');
  check('C headers', 'JSON is utf-8', h.get('content-type'), 'application/json; charset=utf-8');
  const cors = await get(P, '/v1/me', { headers: { ...XFP, origin: 'https://evil.example' } });
  check('C cors', 'a cross-origin request gets no access-control-allow-origin', cors.headers.has('access-control-allow-origin'), 'false');
  const pre = await get(P, '/v1/me', { method: 'OPTIONS', headers: { ...XFP, origin: 'https://evil.example', 'access-control-request-method': 'GET' } });
  check('C cors', 'a CORS preflight is a generic 404 with no allow headers',
    `${pre.status}/${pre.headers.has('access-control-allow-origin')}/${pre.headers.has('access-control-allow-methods')}`, '404/false/false');
  const nf = await get(P, '/nope', { headers: XFP });
  check('C headers', 'even a 404 carries the security headers', `${nf.headers.get('x-frame-options')}/${nf.headers.get('cache-control')}`, 'DENY/no-store');
}

// ---- D · fingerprinting ------------------------------------------------------
{
  const unknown = await get(P, '/definitely/not/a/route', { headers: XFP });
  const wrongMethod = await get(P, '/v1/me', { method: 'DELETE', headers: XFP });
  const trace = await get(P, '/v1/me', { method: 'PROPFIND', headers: XFP });
  const slash = await get(P, '/v1/me/', { headers: XFP });
  check('D fp', 'an unknown path is 404 {"error":"not_found"}', `${unknown.status}/${unknown.text}`, '404/{"error":"not_found"}');
  check('D fp', 'a known path with the wrong method is the SAME 404 (no 405 that confirms the route)', unknown.text === wrongMethod.text && wrongMethod.status === 404, 'true');
  check('D fp', 'an exotic method is the same 404', trace.text === unknown.text && trace.status === 404, 'true');
  check('D fp', 'a trailing slash is the same 404', slash.text === unknown.text && slash.status === 404, 'true');
  const raw = await new Promise((resolve) => {
    const s = net.connect(P, '127.0.0.1', () => s.write('GET /..%2f..%2f..%2fetc%2fpasswd HTTP/1.1\r\nHost: x\r\nx-forwarded-proto: https\r\nConnection: close\r\n\r\n'));
    let d = ''; s.on('data', (x) => { d += x; }); s.on('close', () => resolve(d)); s.on('error', () => resolve(d));
  });
  check('D fp', 'a path-traversal attempt is a generic 4xx with no file content', /^HTTP\/1\.1 4\d\d/.test(raw) && !/root:|\/bin\//.test(raw), 'true');
  check('D fp', 'no Server banner', unknown.headers.has('server'), 'false');
  check('D fp', 'no X-Powered-By', unknown.headers.has('x-powered-by'), 'false');
  const badJson = await get(P, '/v1/auth/webauthn/login/verify', { method: 'POST', headers: XFP, body: '{bad' });
  check('D fp', 'malformed JSON is a clean 400', `${badJson.status}/${j(badJson)?.error}`, '400/bad_json');
  const huge = await get(P, '/v1/auth/webauthn/login/challenge', { method: 'POST', headers: XFP, body: 'x'.repeat(40_000) });
  check('D fp', 'an oversize unauthenticated body is a clean 413', `${huge.status}/${j(huge)?.error}`, '413/payload_too_large');
  const bodies = [unknown, wrongMethod, badJson, huge].map((r) => r.text).join('\n');
  check('D fp', 'no response contains a stack trace, file path or module name', /\bat .*\.(mjs|js|ts):\d+|node_modules|node:internal|\\server\\|\/app\//.test(bodies), 'false');
  const hz = await get(P, '/healthz');
  check('D fp', 'healthz up: exactly {"status":"ok"}', hz.text, '{"status":"ok"}');
  const down = await boot({ NODE_ENV: 'development', DATABASE_URL: 'postgres://nobody:nopass@127.0.0.1:9/none' });
  const dz = await get(down.port, '/healthz');
  check('D fp', 'healthz with the DB down: 503 (probes key on it)', dz.status, 503);
  check('D fp', '...and the SAME shape, a single "status" key, no reason', Object.keys(j(dz)).join(), 'status');
  check('D fp', '...and its value does not name the database', /db|database|postgres|sql/i.test(j(dz).status), 'false');
  await down.stop();
}

// ---- E · what the process prints ---------------------------------------------
{
  await get(P, '/v1/children/11111111-1111-4111-8111-111111111111/now?secret=SNOOPQUERY', { headers: { ...XFP, authorization: 'Bearer SNOOPTOKEN.abcdefghijklmnopqrstuvwxyz' } });
  await get(P, '/v1/auth/session/refresh', { method: 'POST', headers: XFP, body: JSON.stringify({ deviceId: 'SNOOPDEVICE', deviceCredential: 'SNOOPCRED' }) });
  await new Promise((r) => setTimeout(r, 200));
  const log = prod.out() + prod.err();
  check('E logs', 'the process logged request lines', /"msg":"request"/.test(log), 'true');
  check('E logs', 'no log line contains the proxy-reported client address', /198\.51\.100\.77/.test(log), 'false');
  check('E logs', 'no log line contains the loopback peer address', /127\.0\.0\.1:\d|::1|"ip"/.test(log.replace(/listening on :\d+/, '')), 'false');
  check('E logs', 'no log line contains a query string or a token or a posted body', /SNOOP/.test(log), 'false');
  const lines = log.split('\n').filter((l) => l.startsWith('{'));
  check('E logs', 'every JSON log line has only the fixed keys',
    lines.every((l) => { const k = Object.keys(JSON.parse(l)).sort().join(','); return k === 'id,level,method,ms,msg,route,status,ts' || /level/.test(k); }), 'true');
  const metrics = j(await get(P, '/internal/metrics'));
  check('E logs', 'metrics list route TEMPLATES, never a concrete child id', Object.keys(metrics.routes).some((k) => /11111111-1111/.test(k)), 'false');
  check('E logs', 'metrics contain no address-shaped string', /\b\d{1,3}(\.\d{1,3}){3}\b/.test(JSON.stringify(metrics)), 'false');
}
await prod.stop();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
