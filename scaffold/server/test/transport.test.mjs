/**
 * server/test/transport.test.mjs — transport hardening (server-snoop hardening,
 * spec 4.1): boot assertions, "did this arrive over TLS", security headers,
 * the proxy-marker gate on /internal/*, and leak-free error logging. Pure: no
 * sockets, no database. The same behaviour against a real booted server is
 * server/test/snoop_boot_e2e.test.mjs.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  checkBootTransport, requestIsSecure, httpsRequired, securityHeaders, BASE_SECURITY_HEADERS,
  hasProxyMarker, isDirectLoopback,
} from '../transport.mjs';
import { isInternalRequest } from '../observability.mjs';
import { errorLine, redact } from '../safe_log.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const rd = (p) => readFileSync(fileURLToPath(new URL(p, import.meta.url)), 'utf8').replace(/\r\n/g, '\n');

const req = (headers = {}, remote = '203.0.113.9', encrypted = false) =>
  ({ headers, socket: { remoteAddress: remote, encrypted } });
const PROD = {
  NODE_ENV: 'production', PUBLIC_BASE_URL: 'https://api.example.com', TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1',
  DATABASE_URL: 'postgres://app_owner:x@db:5432/olive_prod',
};
const probs = (env) => checkBootTransport(env).problems;

// ---- A · boot assertions ---------------------------------------------------
check('A boot', 'a correct production env has no problems', probs(PROD).length, 0);
check('A boot', 'development is never strict', probs({ NODE_ENV: 'development' }).length, 0);
check('A boot', 'test is never strict', probs({ NODE_ENV: 'test' }).length, 0);
check('A boot', 'unset NODE_ENV (the CI image smoke test) is not strict', probs({}).length, 0);
check('A boot', 'production without PUBLIC_BASE_URL is refused',
  probs({ ...PROD, PUBLIC_BASE_URL: undefined }).some((p) => /PUBLIC_BASE_URL required/.test(p)), 'true');
check('A boot', 'PUBLIC_BASE_URL over http is refused',
  probs({ ...PROD, PUBLIC_BASE_URL: 'http://api.example.com' }).some((p) => /https/.test(p)), 'true');
check('A boot', 'PUBLIC_BASE_URL with a path is refused',
  probs({ ...PROD, PUBLIC_BASE_URL: 'https://api.example.com/v1' }).some((p) => /origin only/.test(p)), 'true');
check('A boot', 'PUBLIC_BASE_URL with embedded credentials is refused',
  probs({ ...PROD, PUBLIC_BASE_URL: 'https://u:p@api.example.com' }).some((p) => /origin only/.test(p)), 'true');
check('A boot', 'PUBLIC_BASE_URL that is not a URL is refused',
  probs({ ...PROD, PUBLIC_BASE_URL: 'not a url' }).length > 0, 'true');
check('A boot', 'production without TRUST_PROXY=1 is refused',
  probs({ ...PROD, TRUST_PROXY: undefined }).some((p) => /TRUST_PROXY=1/.test(p)), 'true');
check('A boot', 'TRUST_PROXY_HOPS must be set',
  probs({ ...PROD, TRUST_PROXY_HOPS: undefined }).some((p) => /TRUST_PROXY_HOPS/.test(p)), 'true');
check('A boot', 'TRUST_PROXY_HOPS 0 is refused', probs({ ...PROD, TRUST_PROXY_HOPS: '0' }).length > 0, 'true');
check('A boot', 'TRUST_PROXY_HOPS 5 is refused (more than any real chain)', probs({ ...PROD, TRUST_PROXY_HOPS: '5' }).length > 0, 'true');
check('A boot', 'TRUST_PROXY_HOPS 2 is accepted', probs({ ...PROD, TRUST_PROXY_HOPS: '2' }).length, 0);
check('A boot', 'a remote database without sslmode is refused',
  probs({ ...PROD, DATABASE_URL: 'postgres://u:p@db.example.net:5432/x' }).some((p) => /sslmode/.test(p)), 'true');
check('A boot', 'a remote database with sslmode=require is still refused (no server identity check)',
  probs({ ...PROD, DATABASE_URL: 'postgres://u:p@db.example.net:5432/x?sslmode=require' }).length > 0, 'true');
check('A boot', 'a remote database with sslmode=verify-full is accepted',
  probs({ ...PROD, DATABASE_URL: 'postgres://u:p@db.example.net:5432/x?sslmode=verify-full' }).length, 0);
check('A boot', 'the compose service name db is local', probs({ ...PROD, DATABASE_URL: 'postgres://u:p@db:5432/x' }).length, 0);
check('A boot', 'localhost is local', probs({ ...PROD, DATABASE_URL: 'postgres://u:p@localhost:5432/x' }).length, 0);
check('A boot', 'a short INTERNAL_METRICS_TOKEN is refused',
  probs({ ...PROD, INTERNAL_METRICS_TOKEN: 'short' }).some((p) => /INTERNAL_METRICS_TOKEN/.test(p)), 'true');
check('A boot', 'a 32+ char INTERNAL_METRICS_TOKEN is accepted',
  probs({ ...PROD, INTERNAL_METRICS_TOKEN: 'a'.repeat(32) }).length, 0);
{
  const soft = checkBootTransport({ NODE_ENV: 'production', ALLOW_INSECURE_TRANSPORT: '1' });
  check('A boot', 'ALLOW_INSECURE_TRANSPORT=1 downgrades the transport problems to warnings',
    `${soft.problems.length}/${soft.warnings.length > 0}`, '0/true');
}

// ---- B · did it arrive over TLS -------------------------------------------
check('B secure', 'a TLS socket is secure', requestIsSecure(req({}, '1.2.3.4', true), {}), 'true');
check('B secure', 'plain socket, no proxy trust: not secure even with X-Forwarded-Proto: https',
  requestIsSecure(req({ 'x-forwarded-proto': 'https' }), {}), 'false');
check('B secure', 'TRUST_PROXY=1 and XFP https: secure',
  requestIsSecure(req({ 'x-forwarded-proto': 'https' }), { TRUST_PROXY: '1' }), 'true');
check('B secure', 'TRUST_PROXY=1 and XFP http: not secure',
  requestIsSecure(req({ 'x-forwarded-proto': 'http' }), { TRUST_PROXY: '1' }), 'false');
check('B secure', 'TRUST_PROXY=1 and no XFP: not secure', requestIsSecure(req(), { TRUST_PROXY: '1' }), 'false');
check('B secure', 'XFP is case-insensitive', requestIsSecure(req({ 'x-forwarded-proto': 'HTTPS' }), { TRUST_PROXY: '1' }), 'true');
check('B secure', 'a client cannot forge https by prepending (hops=1 reads the rightmost)',
  requestIsSecure(req({ 'x-forwarded-proto': 'https, http' }), { TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1' }), 'false');
check('B secure', 'two hops: the entry two from the right decides',
  requestIsSecure(req({ 'x-forwarded-proto': 'https, http' }), { TRUST_PROXY: '1', TRUST_PROXY_HOPS: '2' }), 'true');
check('B secure', 'fewer XFP entries than hops: not secure',
  requestIsSecure(req({ 'x-forwarded-proto': 'https' }), { TRUST_PROXY: '1', TRUST_PROXY_HOPS: '2' }), 'false');

// ---- C · plain HTTP is never served in production -------------------------
check('C https', 'dev: nothing is required', httpsRequired(req(), { NODE_ENV: 'development' }, '/v1/me'), 'false');
check('C https', 'prod, plain, public: required', httpsRequired(req(), PROD, '/v1/me'), 'true');
check('C https', 'prod, via proxy over https: ok', httpsRequired(req({ 'x-forwarded-proto': 'https' }), PROD, '/v1/me'), 'false');
check('C https', 'prod, via proxy over http: required', httpsRequired(req({ 'x-forwarded-proto': 'http' }), PROD, '/v1/me'), 'true');
check('C https', 'prod: the in-container loopback /healthz probe is exempt',
  httpsRequired(req({}, '127.0.0.1'), PROD, '/healthz'), 'false');
check('C https', 'prod: a PUBLIC /healthz over http is not exempt', httpsRequired(req({}, '203.0.113.9'), PROD, '/healthz'), 'true');
check('C https', 'prod: a loopback /healthz carrying proxy headers (a proxy on the host) is not exempt',
  httpsRequired(req({ 'x-forwarded-for': '1.2.3.4' }, '127.0.0.1'), PROD, '/healthz'), 'true');
check('C https', 'prod: the loopback /internal/metrics scrape is exempt too',
  httpsRequired(req({}, '127.0.0.1'), PROD, '/internal/metrics'), 'false');
check('C https', 'prod: loopback is NOT exempt for any other path', httpsRequired(req({}, '127.0.0.1'), PROD, '/v1/me'), 'true');
check('C https', 'ALLOW_INSECURE_TRANSPORT=1 lifts it (a lab box)',
  httpsRequired(req(), { ...PROD, ALLOW_INSECURE_TRANSPORT: '1' }, '/v1/me'), 'false');

// ---- D · headers -----------------------------------------------------------
{
  const h = securityHeaders(req({ 'x-forwarded-proto': 'https' }), PROD);
  check('D headers', 'HSTS on a secure request, 2 years, includeSubDomains, no preload by default',
    h['strict-transport-security'], 'max-age=63072000; includeSubDomains');
  check('D headers', 'preload only when the operator opts in',
    securityHeaders(req({ 'x-forwarded-proto': 'https' }), { ...PROD, HSTS_PRELOAD: '1' })['strict-transport-security'],
    'max-age=63072000; includeSubDomains; preload');
  check('D headers', 'no HSTS on a plain request (it would be ignored and misleading)',
    'strict-transport-security' in securityHeaders(req(), PROD), 'false');
  check('D headers', 'nosniff', h['x-content-type-options'], 'nosniff');
  check('D headers', 'frame deny', h['x-frame-options'], 'DENY');
  check('D headers', 'referrer none', h['referrer-policy'], 'no-referrer');
  check('D headers', 'CSP is default-src none + frame-ancestors none', h['content-security-policy'], "default-src 'none'; frame-ancestors 'none'");
  check('D headers', 'no-store by default', h['cache-control'], 'no-store');
  check('D headers', 'CORP same-site', h['cross-origin-resource-policy'], 'same-site');
  check('D headers', 'no CORS header is ever part of the set',
    Object.keys({ ...BASE_SECURITY_HEADERS, ...h }).some((k) => k.startsWith('access-control-')), 'false');
  check('D headers', 'no server banner or framework header is part of the set',
    Object.keys(h).some((k) => ['server', 'x-powered-by'].includes(k)), 'false');
}
{
  const src = rd('../index.mjs') + rd('../routes.mjs') + rd('../game_tables.mjs') + rd('../signed_media.mjs');
  check('D headers', 'no source file sets an access-control-* header (CORS stays closed)', /access-control-/i.test(src), 'false');
  check('D headers', 'no source file sets x-powered-by or a Server banner', /x-powered-by|['"]server['"]\s*:/i.test(src), 'false');
  check('D headers', 'index.mjs applies the security headers to every response',
    /securityHeaders\(req\)/.test(rd('../index.mjs')), 'true');
  check('D headers', 'index.mjs refuses non-TLS requests via httpsRequired before routing',
    /httpsRequired\(req, process\.env, pathname\)/.test(rd('../index.mjs')), 'true');
  check('D headers', 'index.mjs refuses to boot on transport problems',
    /checkBootTransport\(process\.env\)[\s\S]{0,300}process\.exit\(2\)/.test(rd('../index.mjs')), 'true');
}

// ---- E · the internal gate fails closed on any proxy marker --------------
{
  const loop = (headers = {}) => req(headers, '127.0.0.1');
  check('E internal', 'a bare loopback request is internal', isInternalRequest(loop(), {}), 'true');
  for (const h of ['x-forwarded-for', 'x-forwarded-proto', 'x-forwarded-host', 'forwarded', 'x-real-ip', 'via',
    'cf-connecting-ip', 'true-client-ip', 'x-original-forwarded-for', 'x-envoy-external-address', 'x-client-ip',
    'fastly-client-ip', 'x-cluster-client-ip']) {
    check('E internal', `a loopback request stamped ${h} is NOT internal`, isInternalRequest(loop({ [h]: '1' }), {}), 'false');
  }
  check('E internal', 'a non-loopback peer is not internal', isInternalRequest(req({}, '10.0.0.5'), {}), 'false');
  check('E internal', 'with INTERNAL_METRICS_TOKEN the right token passes',
    isInternalRequest(req({ 'x-internal-token': 'a'.repeat(32) }, '10.0.0.5'), { INTERNAL_METRICS_TOKEN: 'a'.repeat(32) }), 'true');
  check('E internal', 'the wrong token does not',
    isInternalRequest(req({ 'x-internal-token': 'b'.repeat(32) }, '10.0.0.5'), { INTERNAL_METRICS_TOKEN: 'a'.repeat(32) }), 'false');
  check('E internal', 'hasProxyMarker is false on a clean request', hasProxyMarker(loop()), 'false');
  check('E internal', 'isDirectLoopback is true on a clean loopback request', isDirectLoopback(loop()), 'true');
}

// ---- F · leak-free error logging ------------------------------------------
{
  const pgErr = Object.assign(new Error(
    'duplicate key value violates unique constraint "app_user_email_key"'), {
    code: '23505', name: 'error',
    detail: 'Key (email)=(mom@example.com) already exists.',
    where: 'child 7d3b1f10-1a2b-4c3d-8e9f-0a1b2c3d4e5f', stack: 'Error: x\n    at secret/path.js:1:1',
  });
  const line = errorLine(pgErr, { env: {}, now: 0 });
  const o = JSON.parse(line);
  check('F log', 'one JSON line with ts, level, msg, name, code, message', Object.keys(o).sort().join(','), 'code,level,message,msg,name,ts');
  check('F log', 'the pg code is kept for triage', o.code, '23505');
  check('F log', 'the pg `detail` (key values) never appears', /mom@example\.com|Key \(email\)/.test(line), 'false');
  check('F log', 'the pg `where` never appears', /7d3b1f10/.test(line), 'false');
  check('F log', 'no stack by default', 'stack' in o, 'false');
  check('F log', 'LOG_STACKS=1 adds a redacted stack', 'stack' in JSON.parse(errorLine(pgErr, { env: { LOG_STACKS: '1' } })), 'true');
  check('F log', 'a thrown string is handled', JSON.parse(errorLine('boom', { env: {} })).message, 'boom');
  check('F log', 'a null error is handled', JSON.parse(errorLine(null, { env: {} })).message, 'null');
  check('F log', 'long messages are truncated to 300', JSON.parse(errorLine(new Error('word '.repeat(2000)), { env: {} })).message.length, 300);
  check('F log', 'uuids are redacted', redact('child 7d3b1f10-1a2b-4c3d-8e9f-0a1b2c3d4e5f missing'), 'child <id> missing');
  check('F log', 'emails are redacted', redact('for mom@example.com'), 'for <email>');
  check('F log', 'IPv4 addresses are redacted', redact('from 203.0.113.9 refused'), 'from <addr> refused');
  check('F log', 'IPv6 addresses are redacted', redact('from 2001:db8::1 refused'), 'from <addr> refused');
  check('F log', 'bearer tokens are redacted', redact('Authorization: Bearer abc.def.ghi'), 'Authorization: Bearer <redacted>');
  check('F log', 'query strings are redacted', redact('GET /x?token=abc&sig=def failed'), 'GET /x?<redacted> failed');
  check('F log', 'long token-like strings are redacted', redact('key ' + 'A'.repeat(40)), 'key <token>');
}
{
  const idx = rd('../index.mjs');
  check('F log', 'index.mjs has no bare console.error(e) of a whole error object',
    /console\.error\((?:e|err|reason)\)/.test(idx), 'false');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
