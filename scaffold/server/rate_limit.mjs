// OLIVE BRANCH — in-process token buckets for the unauthenticated /v1/auth/*
// surface (audit P-08). Side-effect-free, clock-injectable, so the policy is
// unit-testable without sleeping.
//
// WHY: nothing throttled POST /v1/auth/webauthn/login/{challenge,verify} or
// dev-login. Each call is a DB round trip (and, for `challenge`, an INSERT
// that nothing used to purge), so an anonymous caller could grind the pool
// and fill auth_challenge for free, or hammer one account's login.
//
// Two independent dimensions, BOTH must have a token:
//   - per client IP        (one noisy host cannot starve everyone)
//   - per identifier       (the userId/childId in the body: a distributed
//                           attacker cannot hammer one account either)
//
// State is per process and in memory: a restart resets it (acceptable for an
// abuse throttle; the real credential checks remain the security boundary),
// and a single-replica deployment (docker-compose.prod.yml) needs nothing
// more. The map is bounded: when it exceeds `maxKeys`, buckets that have
// fully refilled (idle callers) are dropped first, then the oldest.

export class TokenBuckets {
  /**
   * @param {{capacity:number, refillPerSec:number, maxKeys?:number, now?:()=>number}} o
   */
  constructor({ capacity, refillPerSec, maxKeys = 10_000, now = () => Date.now() }) {
    this.capacity = capacity;
    this.refillPerSec = refillPerSec;
    this.maxKeys = maxKeys;
    this.now = now;
    this.buckets = new Map(); // key -> { tokens, lastMs }
  }

  /** Consumes one token for `key`. { ok, retryAfterSec } — retryAfterSec only when !ok. */
  take(key) {
    const t = this.now();
    const b = this.buckets.get(key) ?? { tokens: this.capacity, lastMs: t };
    const elapsedSec = Math.max(0, (t - b.lastMs) / 1000);
    const tokens = Math.min(this.capacity, b.tokens + elapsedSec * this.refillPerSec);
    // Re-insert so Map iteration order == least-recently-used first.
    this.buckets.delete(key);
    if (tokens < 1) {
      this.buckets.set(key, { tokens, lastMs: t });
      this._evict();
      return { ok: false, retryAfterSec: Math.max(1, Math.ceil((1 - tokens) / this.refillPerSec)) };
    }
    this.buckets.set(key, { tokens: tokens - 1, lastMs: t });
    this._evict();
    return { ok: true, retryAfterSec: 0 };
  }

  _evict() {
    if (this.buckets.size <= this.maxKeys) return;
    const t = this.now();
    for (const [k, b] of this.buckets) {
      if (this.buckets.size <= this.maxKeys) return;
      const full = b.tokens + ((t - b.lastMs) / 1000) * this.refillPerSec >= this.capacity;
      if (full) this.buckets.delete(k);
    }
    for (const k of this.buckets.keys()) {
      if (this.buckets.size <= this.maxKeys) return;
      this.buckets.delete(k); // oldest first
    }
  }

  get size() { return this.buckets.size; }
}

function posNum(raw, fallback) {
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/**
 * The /v1/auth/* policy. Defaults are generous for a real person (a login is
 * 2 requests) and hopeless for a script: 30-request burst then 30/min per
 * IP; 10-request burst then 10/min per identifier.
 * Env: AUTH_RATE_IP_CAPACITY, AUTH_RATE_IP_PER_MIN, AUTH_RATE_ID_CAPACITY,
 * AUTH_RATE_ID_PER_MIN (invalid/non-positive falls back to the default).
 */
export function createAuthLimiter({ env = process.env, now } = {}) {
  const ipCap = posNum(env.AUTH_RATE_IP_CAPACITY, 30);
  const ipPerMin = posNum(env.AUTH_RATE_IP_PER_MIN, 30);
  const idCap = posNum(env.AUTH_RATE_ID_CAPACITY, 10);
  const idPerMin = posNum(env.AUTH_RATE_ID_PER_MIN, 10);
  const byIp = new TokenBuckets({ capacity: ipCap, refillPerSec: ipPerMin / 60, now });
  const byId = new TokenBuckets({ capacity: idCap, refillPerSec: idPerMin / 60, now });
  return {
    byIp, byId,
    checkIp: (ip) => byIp.take(`ip:${ip}`),
    // Identifier is attacker-controlled text: clamp length so a 16 KB "id"
    // cannot be used to bloat the key space.
    checkIdentifier: (id) => byId.take(`id:${String(id).slice(0, 128)}`),
  };
}

/**
 * The caller's address. `X-Forwarded-For` is honoured ONLY when TRUST_PROXY=1
 * (a deployment that really sits behind a reverse proxy it controls — then the
 * RIGHTMOST entry is the address that proxy actually saw, the only one the
 * client cannot forge). Otherwise the socket address is authoritative and the
 * header is ignored, so a direct caller cannot rotate a fake XFF to dodge the
 * per-IP bucket.
 */
export function clientIp(req, env = process.env) {
  if (env.TRUST_PROXY === '1') {
    const xff = req.headers['x-forwarded-for'];
    if (typeof xff === 'string' && xff.trim()) {
      const parts = xff.split(',').map((s) => s.trim()).filter(Boolean);
      if (parts.length) return parts[parts.length - 1];
    }
  }
  return req.socket?.remoteAddress ?? 'unknown';
}
