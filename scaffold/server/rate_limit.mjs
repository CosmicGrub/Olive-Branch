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
    // S-B15: keyed on (identifier, caller IP), not the identifier alone. Keyed
    // on the id alone, anyone who knew a co-guardian's userId could hold that
    // bucket at zero from their OWN address and lock the real owner out of
    // login. With the IP in the key the attacker only ever drains their own
    // bucket. (The per-IP bucket above still bounds one address across ids.)
    checkIdentifier: (id, ip = '') => byId.take(`id:${String(id).slice(0, 128)}|${String(ip).slice(0, 64)}`),
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

// ---------------------------------------------------------------------------
// Round-2 security audit (S-B1, S-B6, S-B15)
// ---------------------------------------------------------------------------

/**
 * A global fixed-window MISS budget. Used for the one credential the server
 * cannot attribute a wrong guess to: a typed 6-digit device-pairing code
 * matches no row at all, so there is no per-code or per-account counter to
 * lock. This counts every miss across ALL callers; once `limit` misses land in
 * the current `windowMs`, `check()` reports blocked until the window rolls over
 * and the redeem route answers 429 for everyone.
 *
 * The trade, stated plainly: an attacker who burns the budget can make a real
 * pairing wait up to a minute (a nuisance, visible, and no worse than a per-IP
 * flood), but can no longer search the 10^6 code space: at the default 20
 * misses/min a live code survives a 10-minute attack with ~99.98% probability.
 */
export class MissBudget {
  constructor({ limit, windowMs = 60_000, now = () => Date.now() }) {
    this.limit = limit; this.windowMs = windowMs; this.now = now;
    this.windowStart = now(); this.misses = 0;
  }
  _roll() {
    const t = this.now();
    if (t - this.windowStart >= this.windowMs) { this.windowStart = t; this.misses = 0; }
    return t;
  }
  /** { blocked, retryAfterSec } */
  check() {
    const t = this._roll();
    if (this.misses < this.limit) return { blocked: false, retryAfterSec: 0 };
    return { blocked: true,
      retryAfterSec: Math.max(1, Math.ceil((this.windowStart + this.windowMs - t) / 1000)) };
  }
  hit() { this._roll(); this.misses += 1; }
}

/** MissBudget for device-pairing redeem. Env: PAIRING_MISS_BUDGET_PER_MIN. */
export function createPairingMissBudget({ env = process.env, now } = {}) {
  return new MissBudget({ limit: posNum(env.PAIRING_MISS_BUDGET_PER_MIN, 20), now });
}

/**
 * Per-principal limiter for AUTHENTICATED WRITE routes (S-B6): a valid but
 * hostile or buggy session could otherwise issue unbounded POST/PUT/DELETEs.
 * Burst 60, then 60/min per principal by default; env WRITE_RATE_CAPACITY /
 * WRITE_RATE_PER_MIN. The returned function takes the verified principal and
 * answers { ok, retryAfterSec } (the Api calls it for every non-GET route).
 */
export function createWriteLimiter({ env = process.env, now } = {}) {
  const cap = posNum(env.WRITE_RATE_CAPACITY, 60);
  const perMin = posNum(env.WRITE_RATE_PER_MIN, 60);
  const buckets = new TokenBuckets({ capacity: cap, refillPerSec: perMin / 60, now });
  const limiter = (principal) =>
    buckets.take(principal.userId ? `u:${principal.userId}` : `c:${principal.childId}`);
  limiter.buckets = buckets;
  return limiter;
}

/**
 * Per-key in-flight cap (the S-B6 upload semaphore): a base64 media body costs
 * ~3x its size in memory while it is decoded, so one principal may have only
 * `max` such requests running at once; the rest get 429 immediately instead of
 * queueing (queueing would only hold the memory longer).
 */
export class InFlightLimiter {
  constructor({ max }) { this.max = max; this.active = new Map(); }
  /** Returns a release() function, or null when the key is at its cap. */
  acquire(key) {
    const n = this.active.get(key) ?? 0;
    if (n >= this.max) return null;
    this.active.set(key, n + 1);
    let released = false;
    return () => {
      if (released) return;
      released = true;
      const m = (this.active.get(key) ?? 1) - 1;
      if (m <= 0) this.active.delete(key); else this.active.set(key, m);
    };
  }
  count(key) { return this.active.get(key) ?? 0; }
}

export function createUploadLimiter({ env = process.env } = {}) {
  return new InFlightLimiter({ max: posNum(env.UPLOAD_MAX_IN_FLIGHT_PER_PRINCIPAL, 2) });
}
