// OLIVE BRANCH — transport hardening (server-snoop hardening, spec section 4.1).
//
// The server does NOT terminate TLS; production is a reverse proxy (see
// docs/operators/proxy-and-tls.md) in front of a loopback-bound port. What the
// server CAN do is refuse to run, or to serve content, in a shape where the
// proxy is missing or misconfigured. Everything here is pure and takes `env`
// and `req` so it is unit-testable with no sockets.
import { isIP } from 'node:net';

const LOCAL_DB_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '[::1]', 'db']);

const isProd = (env) => env.NODE_ENV === 'production';

function hops(env) {
  const n = Number(env.TRUST_PROXY_HOPS);
  return Number.isInteger(n) && n >= 1 && n <= 4 ? n : null;
}

/**
 * Boot-time assertions about the deployment shape. Returns
 * { problems: string[], warnings: string[] }; the caller exits 2 on problems.
 * Only NODE_ENV=production is strict. ALLOW_INSECURE_TRANSPORT=1 downgrades
 * the transport problems to warnings (a lab box); docker-compose.prod.yml pins
 * it to a literal "0" so an operator's .env cannot turn it on.
 */
export function checkBootTransport(env = process.env) {
  const problems = [], warnings = [];
  if (!isProd(env)) return { problems, warnings };
  const soft = env.ALLOW_INSECURE_TRANSPORT === '1';
  const bad = (msg) => (soft ? warnings : problems).push(msg);

  const base = env.PUBLIC_BASE_URL;
  if (!base) {
    bad('PUBLIC_BASE_URL required in production (the https:// origin clients use, e.g. https://api.example.com)');
  } else {
    let u = null;
    try { u = new URL(base); } catch { /* handled below */ }
    if (!u || u.protocol !== 'https:') bad('PUBLIC_BASE_URL must be an https:// URL');
    else if (u.pathname !== '/' || u.search || u.hash || u.username || u.password) {
      bad('PUBLIC_BASE_URL must be an origin only (no path, query, fragment or credentials)');
    }
  }
  if (env.TRUST_PROXY !== '1') {
    bad('TRUST_PROXY=1 required in production: the server sits behind a TLS-terminating proxy and must read X-Forwarded-Proto');
  } else if (hops(env) === null) {
    bad('TRUST_PROXY_HOPS must be an integer 1-4 (how many trusted proxies sit in front of the server)');
  }

  // Database link: a remote host must be verified TLS.
  const dbUrl = env.DATABASE_URL;
  if (dbUrl) {
    try {
      const u = new URL(dbUrl);
      const host = u.hostname.replace(/^\[|\]$/g, '');
      const local = LOCAL_DB_HOSTS.has(host) || host === '' || u.pathname.startsWith('/var/run');
      const mode = u.searchParams.get('sslmode');
      if (!local && mode !== 'verify-full' && mode !== 'verify-ca') {
        bad('DATABASE_URL points at a non-local host without sslmode=verify-full (or verify-ca)');
      }
    } catch { /* an unparseable URL fails later, loudly, in pg */ }
  }

  const tok = env.INTERNAL_METRICS_TOKEN;
  if (tok && tok.length < 32) problems.push('INTERNAL_METRICS_TOKEN must be at least 32 characters');
  if (env.HSTS_PRELOAD === '1' && !soft) {
    warnings.push('HSTS_PRELOAD=1: preload is effectively irreversible for the domain; make sure every subdomain is https-only');
  }
  return { problems, warnings };
}

const PROXY_MARKERS = [
  'x-forwarded-for', 'x-forwarded-proto', 'x-forwarded-host', 'forwarded', 'x-real-ip', 'via',
  'cf-connecting-ip', 'true-client-ip', 'x-original-forwarded-for', 'x-envoy-external-address',
  'x-client-ip', 'fastly-client-ip', 'x-cluster-client-ip',
];

/** Any header a proxy or CDN stamps on public traffic. */
export function hasProxyMarker(req) {
  const h = req.headers ?? {};
  return PROXY_MARKERS.some((k) => h[k] !== undefined);
}

const LOOPBACK = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);

/** A direct loopback caller with no proxy headers: the in-container healthcheck, a dev curl. */
export function isDirectLoopback(req) {
  return LOOPBACK.has(req.socket?.remoteAddress ?? '') && !hasProxyMarker(req);
}

/**
 * Did this request really arrive over TLS? With TRUST_PROXY=1 the answer is the
 * X-Forwarded-Proto entry TRUST_PROXY_HOPS from the right (the one the
 * outermost trusted proxy appended). Otherwise only a TLS socket counts.
 */
export function requestIsSecure(req, env = process.env) {
  if (req.socket?.encrypted === true) return true;
  if (env.TRUST_PROXY !== '1') return false;
  const raw = req.headers?.['x-forwarded-proto'];
  if (typeof raw !== 'string' || !raw.trim()) return false;
  const parts = raw.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  const n = hops(env) ?? 1;
  if (parts.length < n) return false;
  return parts[parts.length - n] === 'https';
}

/**
 * In production every request must have come over TLS. The only exemption is a
 * direct loopback /healthz (Docker's in-container probe). The answer is a
 * generic 400, never a redirect: redirecting an API call to https would make a
 * client re-send a POST body (and its bearer token) after it already crossed
 * the wire in cleartext.
 */
export function httpsRequired(req, env = process.env, pathname = '') {
  if (!isProd(env) || env.ALLOW_INSECURE_TRANSPORT === '1') return false;
  if (requestIsSecure(req, env)) return false;
  if ((pathname === '/healthz' || pathname === '/internal/metrics') && isDirectLoopback(req)) return false;
  return true;
}

/** Headers for every response. HSTS is added by securityHeaders() only on secure requests. */
export const BASE_SECURITY_HEADERS = Object.freeze({
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'no-referrer',
  'content-security-policy': "default-src 'none'; frame-ancestors 'none'",
  'cross-origin-resource-policy': 'same-site',
  'permissions-policy': 'interest-cohort=(), geolocation=(), camera=(), microphone=()',
  'cache-control': 'no-store',
});

export function securityHeaders(req, env = process.env) {
  const out = { ...BASE_SECURITY_HEADERS };
  if (requestIsSecure(req, env)) {
    out['strict-transport-security'] = env.HSTS_PRELOAD === '1'
      ? 'max-age=63072000; includeSubDomains; preload'
      : 'max-age=63072000; includeSubDomains';
  }
  return out;
}

/** True for a literal IP host (used by docs/tests to flag raw-IP PUBLIC_BASE_URL). */
export const isIpHost = (host) => isIP(host.replace(/^\[|\]$/g, '')) !== 0;
