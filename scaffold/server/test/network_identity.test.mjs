/**
 * server/test/network_identity.test.mjs — the server must not learn or keep a
 * family's network identity (server-snoop hardening, spec 4.3):
 *
 *   A  address normalisation and the daily-salted pseudonym (netid.mjs)
 *   B  proxy-header parsing: hop counting, spoofing, validation
 *   C  limiters key on the pseudonym, never the address
 *   D  requests: no address / SSID / MAC / hostname / coordinates accepted
 *   E  source sweeps: no such columns, body keys, DNS or GeoIP anywhere
 *   F  the access log and metrics carry no per-family or per-network data
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import {
  normaliseAddress, expandIPv6, peerAddress, createNetIdentity, SALT_ROTATE_MS,
} from '../netid.mjs';
import { createAuthLimiter, clientIp, createWriteLimiter } from '../rate_limit.mjs';
import { accessLogLine, Metrics } from '../observability.mjs';
import { Api, findNetworkIdentityKey, NETWORK_IDENTITY_KEYS } from '../../packages/api/src/api.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const HERE = fileURLToPath(new URL('.', import.meta.url));
const SCAFFOLD = join(HERE, '..', '..');
const rd = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const req = (headers = {}, remote = '203.0.113.9') => ({ headers, socket: { remoteAddress: remote } });

// ---- A · normalisation + pseudonym ----------------------------------------
check('A anon', 'IPv4 is kept as-is for hashing', normaliseAddress('203.0.113.9'), '203.0.113.9');
check('A anon', 'IPv6 is reduced to its /64', normaliseAddress('2001:db8:1:2:aaaa:bbbb:cccc:dddd'), '2001:db8:1:2::/64');
check('A anon', 'two hosts in one /64 normalise identically',
  normaliseAddress('2001:db8:1:2::1') === normaliseAddress('2001:db8:1:2:ffff::9'), 'true');
check('A anon', 'compressed and expanded spellings agree',
  normaliseAddress('2001:db8::5') === normaliseAddress('2001:0db8:0:0:0:0:0:5'), 'true');
check('A anon', 'IPv4-mapped IPv6 is unwrapped to IPv4', normaliseAddress('::ffff:203.0.113.9'), '203.0.113.9');
check('A anon', 'a zone id is ignored', normaliseAddress('fe80::1%eth0'), 'fe80:0:0:0::/64');
check('A anon', 'garbage becomes unknown, never an exception', normaliseAddress('not-an-ip'), 'unknown');
check('A anon', 'a non-string becomes unknown', normaliseAddress(undefined), 'unknown');
check('A anon', 'expandIPv6 expands :: correctly', expandIPv6('::1').join(':'), '0:0:0:0:0:0:0:1');
{
  let t = 1_000;
  let n = 0;
  const id = createNetIdentity({ env: {}, now: () => t, randomSalt: () => Buffer.alloc(32, ++n) });
  const a = id.keyOf('203.0.113.9');
  check('A anon', 'the pseudonym is 16 bytes of base64url (22 chars)', /^[A-Za-z0-9_-]{22}$/.test(a), 'true');
  check('A anon', 'it never contains the address', a.includes('203') || a.includes('113'), 'false');
  check('A anon', 'the same address maps to the same key within a window', id.keyOf('203.0.113.9'), a);
  check('A anon', 'a different address maps to a different key', id.keyOf('203.0.113.10') === a, 'false');
  t += SALT_ROTATE_MS - 1;
  check('A anon', 'just before rotation the key is unchanged', id.keyOf('203.0.113.9'), a);
  t += 1;
  check('A anon', 'after 24 h the salt rotates: the same address is a NEW key (not linkable across days)',
    id.keyOf('203.0.113.9') === a, 'false');
  const other = createNetIdentity({ env: {}, now: () => 0 });
  check('A anon', 'two processes (random salts) disagree on the same address',
    other.keyOf('203.0.113.9') === createNetIdentity({ env: {}, now: () => 0 }).keyOf('203.0.113.9'), 'false');
}

// ---- B · proxy headers ------------------------------------------------------
check('B proxy', 'no TRUST_PROXY: the socket address, XFF ignored',
  peerAddress(req({ 'x-forwarded-for': '1.1.1.1' }), {}), '203.0.113.9');
check('B proxy', 'TRUST_PROXY=1 default 1 hop: rightmost',
  peerAddress(req({ 'x-forwarded-for': '1.1.1.1, 2.2.2.2' }), { TRUST_PROXY: '1' }), '2.2.2.2');
check('B proxy', 'a client-prepended entry cannot win at 1 hop',
  peerAddress(req({ 'x-forwarded-for': '9.9.9.9, 198.51.100.7' }), { TRUST_PROXY: '1' }), '198.51.100.7');
check('B proxy', '2 hops (CDN + ingress): the second from the right is the real client',
  peerAddress(req({ 'x-forwarded-for': '9.9.9.9, 198.51.100.7, 10.0.0.2' }), { TRUST_PROXY: '1', TRUST_PROXY_HOPS: '2' }), '198.51.100.7');
check('B proxy', 'fewer entries than hops: fall back to the socket',
  peerAddress(req({ 'x-forwarded-for': '198.51.100.7' }), { TRUST_PROXY: '1', TRUST_PROXY_HOPS: '3' }), '203.0.113.9');
check('B proxy', 'a non-IP entry is ignored, not trusted',
  peerAddress(req({ 'x-forwarded-for': 'evil.example.com' }), { TRUST_PROXY: '1' }), '203.0.113.9');
check('B proxy', 'an injection-shaped entry is ignored',
  peerAddress(req({ 'x-forwarded-for': "1.1.1.1'; DROP TABLE x;--" }), { TRUST_PROXY: '1' }), '203.0.113.9');
check('B proxy', 'an IPv6 entry is accepted', peerAddress(req({ 'x-forwarded-for': '2001:db8::7' }), { TRUST_PROXY: '1' }), '2001:db8::7');
check('B proxy', 'empty XFF falls back', peerAddress(req({ 'x-forwarded-for': '  ' }), { TRUST_PROXY: '1' }), '203.0.113.9');
check('B proxy', 'TRUST_PROXY_HOPS=0 is treated as the default (1)',
  peerAddress(req({ 'x-forwarded-for': '1.1.1.1, 2.2.2.2' }), { TRUST_PROXY: '1', TRUST_PROXY_HOPS: '0' }), '2.2.2.2');
check('B proxy', 'rate_limit.clientIp delegates to the same parser',
  clientIp(req({ 'x-forwarded-for': '1.1.1.1, 2.2.2.2' }), { TRUST_PROXY: '1' }), '2.2.2.2');
{
  const id = createNetIdentity({ env: { TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1' } });
  const spoof = (v) => id.anonKey(req({ 'x-forwarded-for': v }, '198.51.100.1'));
  check('B proxy', 'rotating a forged leading XFF entry does not change the bucket key',
    spoof('1.1.1.1, 198.51.100.7') === spoof('2.2.2.2, 198.51.100.7'), 'true');
}

// ---- C · limiters hold pseudonyms, never addresses -------------------------
{
  const id = createNetIdentity({ env: {} });
  const lim = createAuthLimiter({ env: {} });
  const r = req({}, '203.0.113.9');
  lim.checkIp(id.anonKey(r));
  lim.checkIdentifier('11111111-1111-1111-1111-111111111111', id.anonKey(r));
  const keys = [...lim.byIp.buckets.keys(), ...lim.byId.buckets.keys()].join('\n');
  check('C limiters', 'no bucket key contains the raw address', /203\.0\.113\.9|203\.0|113\.9/.test(keys), 'false');
  check('C limiters', 'the per-IP limiter still limits (30 burst then refused) on pseudonyms', (() => {
    const l = createAuthLimiter({ env: {} }); let ok = 0;
    for (let i = 0; i < 40; i++) if (l.checkIp(id.anonKey(r)).ok) ok++;
    return ok; })(), 30);
  const w = createWriteLimiter({ env: {} });
  w({ userId: 'u1', childId: null });
  check('C limiters', 'the write limiter keys on a principal id, never an address',
    [...w.buckets.buckets.keys()].every((k) => /^[uc]:/.test(k)), 'true');
}
{
  const idx = rd(join(SCAFFOLD, 'server', 'index.mjs'));
  check('C limiters', 'index.mjs no longer passes clientIp() to a limiter', /clientIp\(/.test(idx), 'false');
  check('C limiters', 'index.mjs keys limiters on netId.anonKey(req)', (idx.match(/netId\.anonKey\(req\)/g) ?? []).length, 2);
}

// ---- D · requests carry no network identity -------------------------------
{
  const f = findNetworkIdentityKey;
  check('D body', 'a clean body passes', f({ displayName: 'Aria', yearsOld: 7, nested: { a: [1, { b: 2 }] } }), 'null');
  for (const k of ['ip', 'ipAddress', 'ip_address', 'IP', 'ssid', 'SSID', 'bssid', 'mac', 'macAddress', 'mac_address',
    'hostname', 'lanIp', 'lan_address', 'latitude', 'longitude', 'lat', 'lng', 'geo', 'geolocation', 'wifiName',
    'network_name', 'remoteAddress', 'localIp', 'publicIp']) {
    check('D body', `key "${k}" is refused at the top level`, f({ [k]: 'x' }), k);
  }
  check('D body', 'refused when nested in an object', f({ a: { b: { ssid: 'HomeWiFi' } } }), 'ssid');
  check('D body', 'refused when nested in an array', f({ a: [{ ok: 1 }, { macAddress: 'aa:bb' }] }), 'macAddress');
  check('D body', 'a VALUE that looks like an address is not a key and passes (text a child typed)',
    f({ note: 'my ip is 1.2.3.4' }), 'null');
  check('D body', 'an overlong chain does not hang or throw', (() => {
    let o = {}; const root = o; for (let i = 0; i < 5000; i++) { o.n = {}; o = o.n; } return f(root); })(), 'null');
  check('D body', 'the denylist is exposed and non-trivial', NETWORK_IDENTITY_KEYS.size >= 25, 'true');

  const db = { edgesFor: async () => [], withSession: async (_p, fn) => fn(async () => []),
    isDeviceRevoked: async () => false };
  const { randomBytes } = await import('node:crypto');
  const { issueSession } = await import('../../packages/auth/src/auth.mjs');
  const secret = randomBytes(32);
  const api = new Api(secret, db, () => 1_000_000);
  let ran = 0;
  api.register({ method: 'POST', path: '/v1/test/echo', action: null, skipOuterSession: true,
    handler: async (c) => { ran++; return { status: 200, body: { ok: true } }; } });
  api.register({ method: 'POST', path: '/v1/test/open', action: null, skipOuterSession: true, noSessionRequired: true,
    handler: async () => { ran++; return { status: 200, body: { ok: true } }; } });
  const tok = issueSession(secret, { userId: 'u1', roleName: 'guardian', childId: null, escalated: false }, 1_000_000);
  const auth = { authorization: `Bearer ${tok}` };
  const bad = await api.handle('POST', '/v1/test/echo', auth, JSON.stringify({ note: 'hi', network: { ssid: 'Home' } }));
  check('D body', 'an authenticated route refuses a body with an SSID: 400 network_identity_not_accepted',
    `${bad.status}/${bad.body.error}`, '400/network_identity_not_accepted');
  check('D body', '...and the handler never ran', ran, 0);
  const bad2 = await api.handle('POST', '/v1/test/open', {}, JSON.stringify({ ipAddress: '1.2.3.4' }));
  check('D body', 'a no-session route refuses a body with an address too',
    `${bad2.status}/${bad2.body.error}`, '400/network_identity_not_accepted');
  const good = await api.handle('POST', '/v1/test/echo', auth, JSON.stringify({ note: 'hi' }));
  check('D body', 'a clean body still reaches the handler', `${good.status}/${ran}`, '200/1');
  check('D body', 'the refusal body does not echo the key (generic)', Object.keys(bad.body).join(), 'error');
}

// ---- E · source sweeps -----------------------------------------------------
{
  const walk = (dir, out = []) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (e.name === 'node_modules' || e.name === 'test' || e.name === 'client' || e.name === 'demo') continue;
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p, out); else out.push(p);
    }
    return out;
  };
  const walkHas = (p) => { try { readFileSync(p); return true; } catch { return false; } };
  // --- migrations: no column that stores network identity
  const COL_BAD = /^\s*"?(ip|ip_address|ipaddress|client_ip|remote_addr|remote_ip|ssid|bssid|mac|mac_address|hostname|host_name|lan_ip|lan_address|latitude|longitude|lat|lng|lon|geo|geolocation|geom|wifi|wifi_name|network_name|user_agent)"?\s+(text|varchar|inet|cidr|macaddr|numeric|double|real|point|geography|geometry|character|jsonb?)\b/im;
  const migs = readdirSync(join(SCAFFOLD, 'db', 'migrations')).filter((f) => f.endsWith('.sql'));
  const hits = migs.filter((f) => COL_BAD.test(rd(join(SCAFFOLD, 'db', 'migrations', f))));
  check('E sweep', `no migration (${migs.length} files) declares a network-identity column`, hits.join(',') || 'none', 'none');
  check('E sweep', 'no migration uses the inet / cidr / macaddr / geography types at all',
    migs.filter((f) => /\b(inet|cidr|macaddr8?|geography|geometry)\b/i.test(rd(join(SCAFFOLD, 'db', 'migrations', f)).replace(/--.*$/gm, ''))).join(',') || 'none', 'none');

  // --- server + packages source: no DNS / GeoIP lookups, no request-address storage
  const files = [...walk(join(SCAFFOLD, 'server')), ...walk(join(SCAFFOLD, 'packages')), ...walk(join(SCAFFOLD, 'tools'))]
    .filter((p) => /\.(mjs|ts)$/.test(p) && !p.endsWith('.test.mjs'))
    // built siblings (packages/*/src/x.mjs from x.ts) are the same source twice
    .filter((p) => !(p.endsWith('.mjs') && p.includes(join('packages', '')) && walkHas(p.replace(/\.mjs$/, '.ts'))));
  const code = (p) => rd(p).replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  const dnsHits = files.filter((p) => /from\s+['"]node:dns|from\s+['"]dns['"]|require\(['"](node:)?dns|geoip|maxmind|ip2location|ipinfo|ipapi|\bdns(?:Promises)?\.reverse\(/i
    .test(code(p)) && !p.includes('local-call-room') && !p.includes('jitsi'));
  check('E sweep', 'no server/package/tool source imports node:dns or any GeoIP / IP-info library, or reverse-resolves',
    dnsHits.map((p) => p.replace(SCAFFOLD, '')).join(',') || 'none', 'none');

  // --- routes: no c.body.<identity key> read
  const routeSrc = code(join(SCAFFOLD, 'server', 'routes.mjs')) + code(join(SCAFFOLD, 'server', 'game_tables.mjs'));
  const reads = [...routeSrc.matchAll(/(?:c\.body|body)\??\.(\w+)/g)].map((m) => m[1])
    .filter((k) => NETWORK_IDENTITY_KEYS.has(k.toLowerCase().replace(/_/g, '')));
  check('E sweep', 'no route reads a network-identity key from a request body', reads.join(',') || 'none', 'none');
  const stores = files.filter((p) => /remoteAddress|x-forwarded-for|socket\.remotePort/i.test(code(p)))
    .map((p) => p.replace(SCAFFOLD, '').replace(/\\/g, '/'));
  check('E sweep', 'only netid.mjs, transport.mjs (proxy markers), observability.mjs (internal gate) and the api denylist mention the peer address',
    stores.sort().join(','), ['/packages/api/src/api.ts', '/server/netid.mjs', '/server/observability.mjs', '/server/transport.mjs'].join(','));
  check('E sweep', 'server code never writes an address to a SQL parameter or the log',
    files.filter((p) => /\.mjs$/.test(p) && /(console\.(log|error|warn)|\bq\(|INSERT)[^;\n]*(remoteAddress|peerAddress\(|clientIp\()/.test(code(p))).length, 0);
}

// ---- F · what is logged and exposed ---------------------------------------
{
  const line = accessLogLine({ id: 'abc12345', method: 'GET', route: '/v1/children/:childId/now', status: 200, ms: 4.2, now: 0 });
  check('F logs', 'the access-log keys are fixed: ts, level, msg, id, method, route, status, ms',
    Object.keys(JSON.parse(line)).join(','), 'ts,level,msg,id,method,route,status,ms');
  const m = new Metrics();
  m.record({ method: 'GET', route: '/v1/children/:childId/now', status: 200, ms: 1 });
  const snap = m.snapshot({ pool: { total: 1, idle: 1, waiting: 0 }, game_tables_open: 0 });
  check('F logs', 'the metrics snapshot key set is aggregate-only',
    Object.keys(snap).sort().join(','), 'by_status_class,counters,game_tables_open,pool,requests_total,routes,uptime_s');
  check('F logs', 'metric routes are templates, never a concrete child id',
    Object.keys(snap.routes).every((k) => k.includes(':childId')), 'true');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
