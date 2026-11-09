// OLIVE BRANCH — server-side observability (audit P-07, server half).
// Side-effect-free so server/index.mjs stays the only file with a listener.
//
//   1. A request id per request, echoed in the `x-request-id` response header.
//      An inbound `x-request-id` is reused ONLY if it is short and plain
//      (so a caller can correlate its own logs) -- never trusted as free text
//      that ends up in a log line.
//   2. ONE JSON line per request on stdout: ts, id, method, route, status,
//      ms. `route` is the registered TEMPLATE ('/v1/children/:childId/
//      expenses'), never the concrete URL, so no child/user id (PII) and no
//      query string ever reaches a log. Requests that match no route log
//      their fixed bucket ('/healthz', '/media/:key', '/v1/auth/*',
//      'unmatched'), never raw attacker-controlled paths.
//   3. In-process counters, exposed by GET /internal/metrics behind
//      isInternalRequest() -- never public.
import { randomUUID, timingSafeEqual } from 'node:crypto';
import { hasProxyMarker } from './transport.mjs';

const SAFE_ID = /^[A-Za-z0-9._-]{8,64}$/;

export function requestIdFor(req) {
  const inbound = req.headers['x-request-id'];
  return typeof inbound === 'string' && SAFE_ID.test(inbound) ? inbound : randomUUID();
}

/** The one-line JSON access-log record (returned as a string, caller prints it). */
export function accessLogLine({ id, method, route, status, ms, now = Date.now() }) {
  return JSON.stringify({
    ts: new Date(now).toISOString(), level: 'info', msg: 'request',
    id, method, route, status, ms: Math.round(ms * 10) / 10,
  });
}

export class Metrics {
  constructor(now = () => Date.now()) {
    this.startedAt = now();
    this.now = now;
    this.requests = 0;
    this.byStatusClass = { '2xx': 0, '3xx': 0, '4xx': 0, '5xx': 0, other: 0 };
    this.byRoute = new Map(); // "GET /v1/me" -> { count, errors, msSum, msMax }
    this.counters = new Map(); // rate_limited, body_too_large, ...
  }

  record({ method, route, status, ms }) {
    this.requests++;
    const cls = status >= 200 && status < 600 ? `${Math.floor(status / 100)}xx` : 'other';
    this.byStatusClass[cls in this.byStatusClass ? cls : 'other']++;
    const key = `${method} ${route}`;
    // Bounded: route is always a registered template or a fixed bucket, but
    // cap anyway so a bug can never turn this into an unbounded map.
    if (!this.byRoute.has(key) && this.byRoute.size >= 500) return;
    const r = this.byRoute.get(key) ?? { count: 0, errors: 0, msSum: 0, msMax: 0 };
    r.count++;
    if (status >= 500) r.errors++;
    r.msSum += ms;
    r.msMax = Math.max(r.msMax, ms);
    this.byRoute.set(key, r);
  }

  inc(name, by = 1) { this.counters.set(name, (this.counters.get(name) ?? 0) + by); }

  snapshot(extra = {}) {
    const routes = {};
    for (const [k, r] of this.byRoute) {
      routes[k] = {
        count: r.count, errors_5xx: r.errors,
        ms_avg: Math.round((r.msSum / r.count) * 10) / 10, ms_max: Math.round(r.msMax * 10) / 10,
      };
    }
    return {
      uptime_s: Math.round((this.now() - this.startedAt) / 1000),
      requests_total: this.requests,
      by_status_class: { ...this.byStatusClass },
      counters: Object.fromEntries(this.counters),
      routes,
      ...extra,
    };
  }
}

const LOOPBACK = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);

/**
 * The internal-only guard for /internal/*. Default: the TCP peer must be
 * loopback AND the request must carry no proxy headers (x-forwarded-for /
 * forwarded / x-real-ip) -- a reverse proxy on the same host connects from
 * loopback too, but it stamps those headers on public traffic, so proxied
 * requests are refused. If INTERNAL_METRICS_TOKEN is set the caller must
 * ALSO present it in `x-internal-token` (constant-time compare), which is
 * how an operator allows a scraper on another container/host to reach it.
 * A refused caller gets the same 404 an unknown path would -- the endpoint's
 * existence is not advertised.
 */
export function isInternalRequest(req, env = process.env) {
  const h = req.headers;
  // Fail closed on ANY header a proxy or CDN stamps on public traffic.
  if (hasProxyMarker(req)) return false;
  const token = env.INTERNAL_METRICS_TOKEN;
  if (token) {
    const got = String(h['x-internal-token'] ?? '');
    const a = Buffer.from(got), b = Buffer.from(token);
    return a.length === b.length && timingSafeEqual(a, b);
  }
  return LOOPBACK.has(req.socket?.remoteAddress ?? '');
}
