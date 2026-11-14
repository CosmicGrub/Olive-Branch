#!/usr/bin/env node
// OLIVE BRANCH — server entrypoint. The first thing in this repository that
// actually listens on a port and serves real client requests against real
// Postgres. MASTERFILE §3.2, §7.
//
// LOGIN IS A DEV-ONLY SHORTCUT, DELIBERATELY, NOT A DESIGN DECISION PRESENTED
// AS FINISHED. auth.ts's own header describes the real ceremonies: guardians
// via WebAuthn/passkey, children via a device-bound token + PIN. Neither
// ceremony is implemented anywhere in this codebase yet (no endpoint issues a
// WebAuthn challenge, no client holds a device-bound token) -- building
// either for real is its own substantial piece of work. What exists here is
// enough to prove the rest of the stack (session -> auth -> RLS-scoped
// Postgres query -> response) end to end: POST /v1/auth/dev-login with a
// bare {userId} or {childId} that must already exist in the database, no
// credential of any kind checked. This must never reach anything but a local
// dev database, and is fenced behind DEV_LOGIN=1 for exactly that reason.
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { issueSession, verifyAssertion, newChallenge } from '../packages/auth/src/auth.mjs';
import { Api, readRequestBody, MAX_UNAUTH_BODY_BYTES } from '../packages/api/src/api.mjs';
import { createPool, dbPort, withSystemSession, createChallenge, consumeChallenge,
         webauthnCredentialById, updateWebauthnSignCount, mediaUploadFor } from '../packages/db/src/pool.mjs';
import { registerRoutes, RP_ID, RP_ORIGIN, defaultMediaStorage } from './routes.mjs';
import { serveSignedMedia } from './signed_media.mjs';
import { registerGameTableRoutes, attachGameSocketServer, deriveGameTableSecret } from './game_tables.mjs';
import { createAuthLimiter, createWriteLimiter } from './rate_limit.mjs';
import { createNetIdentity } from './netid.mjs';
import { checkBootTransport, httpsRequired, securityHeaders } from './transport.mjs';
import { errorLine } from './safe_log.mjs';
import { checkBootSecrets } from './secrets.mjs';
import { checkRuntimeRole } from './db_role.mjs';
import { Metrics, requestIdFor, accessLogLine, isInternalRequest } from './observability.mjs';
import { createShutdown, DEFAULT_SHUTDOWN_DEADLINE_MS } from './shutdown.mjs';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PORT = Number(process.env.PORT ?? 8080);
const DATABASE_URL = process.env.DATABASE_URL;
const DEV_LOGIN = process.env.DEV_LOGIN === '1';

// Audit G-02/G-06 — dev-login is the credential-free shortcut this file's header
// describes; the real session path is POST /v1/auth/session/refresh (routes.mjs).
// Fail CLOSED: a process that says it is production but was started with
// DEV_LOGIN=1 (a copy-pasted dev env file, a compose override) refuses to boot
// rather than serve a route that mints a session for any user id with no
// credential at all.
if (DEV_LOGIN && process.env.NODE_ENV === 'production') {
  console.error('DEV_LOGIN=1 is not allowed with NODE_ENV=production');
  process.exit(2);
}
if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }
// S-B13 -- SESSION_SECRET / MEDIA_SIGNING_SECRET must be real keys (valid hex,
// >= 32 bytes, not a placeholder) outside NODE_ENV=development|test. See
// server/secrets.mjs for the why.
const boot = checkBootSecrets(process.env);
for (const w of boot.warnings) console.warn(`WARNING: ${w}`);
if (boot.problems.length) {
  for (const p of boot.problems) console.error(`secret check failed: ${p}`);
  process.exit(2);
}

// Server-snoop hardening: a production process must be configured as the HTTPS
// back end of a TLS-terminating proxy (PUBLIC_BASE_URL, TRUST_PROXY and
// TRUST_PROXY_HOPS) or it refuses to start. See server/transport.mjs.
const bootTransport = checkBootTransport(process.env);
for (const w of bootTransport.warnings) console.warn(`WARNING: ${w}`);
if (bootTransport.problems.length) {
  for (const p of bootTransport.problems) console.error(`transport check failed: ${p}`);
  process.exit(2);
}
const netId = createNetIdentity();

const pool = createPool(DATABASE_URL);
// S-B11 -- refuse to run as a role that owns the schema / bypasses RLS (server/db_role.mjs).
const bootRole = await checkRuntimeRole(pool, process.env);
for (const w of bootRole.warnings) console.warn(`WARNING: ${w}`);
if (bootRole.problems.length) {
  for (const p of bootRole.problems) console.error(`database role check failed: ${p}`);
  process.exit(2);
}
const secret = boot.sessionSecret;
// S-B16 -- two-key rotation: SESSION_SECRET signs, SESSION_SECRET_PREVIOUS only verifies.
const sessionKeys = { current: secret, previous: boot.previousSessionSecret };
// S-B14 strictIds: a malformed uuid path parameter is a 400, never a Postgres
// cast error (500). S-B6 writeLimiter: per-principal throttle on authenticated writes.
const api = new Api(sessionKeys, dbPort(pool), () => Date.now(),
  { strictIds: true, writeLimiter: createWriteLimiter() });
registerRoutes(api, pool);

// ---- network play (checkers, live) — MASTERFILE §5.14, §5.17, §5.19 ------
// In-memory only (packages/game-sync/src/table.ts's T7): no table, token, or
// move ever touches Postgres or disk. A dropped connection ends the game;
// see game_tables.mjs's own header for why that is a deliberate simplicity
// choice, not an oversight.
const gameTableSecret = deriveGameTableSecret(secret);
const gameTables = new Map();
registerGameTableRoutes(api, { secret: gameTableSecret, tables: gameTables });

async function devLogin(rawBody) {
  if (!DEV_LOGIN) return { status: 404, body: { error: 'not_found' } };
  let body;
  try { body = JSON.parse(rawBody || '{}'); }
  catch { return { status: 400, body: { error: 'bad_json' } }; }
  const { userId = null, childId = null } = body;
  if (!userId && !childId) return { status: 400, body: { error: 'userId_or_childId_required' } };

  return dbPort(pool).withSession({ roleName: 'system', userId: null, childId: null }, async (q) => {
    if (childId) {
      const rows = await q(`SELECT id FROM child WHERE id = $1`, [childId]);
      if (!rows.length) return { status: 404, body: { error: 'child_not_found' } };
      const token = issueSession(sessionKeys,
        { userId: null, roleName: 'child', childId, escalated: false }, Date.now());
      return { status: 200, body: { token } };
    }
    const rows = await q(`SELECT id, deactivated_at FROM app_user WHERE id = $1`, [userId]);
    if (!rows.length) return { status: 404, body: { error: 'user_not_found' } };
    // MASTERFILE §2.10/§2.11/P8 — "what goes: the deleting guardian's
    // login/session". This is the one real login/session-issuing path that
    // exists in this codebase today (see this file's own header: no real
    // PIN/WebAuthn login endpoint is implemented anywhere yet, so there is no
    // second login path to gate the same way). pool.ts's deactivateAccount()
    // already removes this user's pin_credential/webauthn_credential rows,
    // which would make a REAL PIN/WebAuthn login fail on its own the moment
    // one exists (nothing left to verify against) — this check is what closes
    // the gap for the login path that actually exists right now.
    if (rows[0].deactivated_at) {
      return { status: 403, body: { error: 'account_deactivated' } };
    }
    const token = issueSession(sessionKeys,
      { userId, roleName: 'guardian', childId: null, escalated: false }, Date.now());
    return { status: 200, body: { token } };
  });
}

/**
 * WebAuthn LOGIN — the real, production-safe replacement for dev-login above,
 * not itself dev-only. Lives here rather than server/routes.mjs's
 * api.register() calls for the same structural reason dev-login does: it
 * ESTABLISHES a session, so there is no pre-existing one for api.handle() to
 * authenticate first.
 *
 * The challenge/verify pair takes a `userId` hint rather than implementing a
 * discoverable-credential (resident-key) flow: this app already knows its
 * small, fixed set of real accounts per family (the same household that
 * shares a kiosk device), which is exactly dev-login's own justification for
 * accepting a bare id instead of a full identity-lookup UI. That is a real,
 * deliberate scope decision recorded here, not a shortcut hiding a gap — a
 * resident-key/usernameless flow is a genuine follow-up, not silently
 * assumed unnecessary.
 */
async function webauthnLoginChallenge(rawBody) {
  let body;
  try { body = JSON.parse(rawBody || '{}'); }
  catch { return { status: 400, body: { error: 'bad_json' } }; }
  const { userId } = body ?? {};
  if (typeof userId !== 'string' || !userId) {
    return { status: 400, body: { error: 'userId_required' } };
  }
  // Not a uuid -> cannot name an account; skip the query (a bare uuid-cast
  // error from Postgres would 500 and be an oracle of its own).
  const exists = UUID_RE.test(userId)
    ? await withSystemSession(pool, (q) => q(`SELECT id FROM app_user WHERE id = $1`, [userId]))
    : [];
  // P-08 -- UNIFORM response: this endpoint is unauthenticated, so a 404
  // `user_not_found` for an unknown id (and 200 for a real one) is an account
  // oracle -- anyone could enumerate which userIds hold accounts. An unknown
  // id now gets the same 200 shape with a fresh, correctly-formed challenge
  // that is simply never stored. It can never verify (consumeChallenge finds
  // no row -> the SAME 401 challenge_expired a wrong/expired challenge for a
  // real user gets), so nothing is gained by probing and nothing real leaks.
  if (!exists.length) {
    return { status: 200, body: { challenge: newChallenge(), rpId: RP_ID } };
  }
  const challenge = await createChallenge(pool, userId, 'login');
  return { status: 200, body: { challenge, rpId: RP_ID } };
}

async function webauthnLoginVerify(rawBody) {
  let body;
  try { body = JSON.parse(rawBody || '{}'); }
  catch { return { status: 400, body: { error: 'bad_json' } }; }
  const { userId, credentialId, clientDataJSON, authenticatorData, signature } = body ?? {};
  if (!userId || !credentialId || !clientDataJSON || !authenticatorData || !signature) {
    return { status: 400, body: { error: 'bad_request' } };
  }

  // SEC-01 follow-up (round-2 audit's adversarial verify) — devLogin() above
  // has always checked deactivated_at before issuing a token; this, the
  // OTHER real login path, did not. Checked early, before spending the
  // single-use challenge (consumeChallenge below) or running the signature
  // verification: on a deactivated account there is nothing further worth
  // doing. An unrecognized userId falls through unchanged to the existing
  // challenge-lookup failure below (401 challenge_expired) rather than a new
  // branch here — a user_not_found leak this early would tell an
  // unauthenticated caller something a login endpoint shouldn't. Complements
  // storeWebauthnCredential()'s own atomic registration gate (pool.ts) — that
  // one stops a NEW credential from being minted after deactivation; this one
  // stops an OLDER credential, registered before deactivation, from still
  // being usable to log in afterward. Either alone would close the exploit
  // the round-2 audit found; both together match devLogin's own belt-and-
  // suspenders posture (existence check AND deactivated_at check) rather
  // than leaning on just one.
  const existing = await withSystemSession(pool,
    (q) => q(`SELECT deactivated_at FROM app_user WHERE id = $1`, [userId]));
  if (existing.length && existing[0].deactivated_at) {
    // S-B15 -- UNIFORM with an unknown user and a spent/expired challenge: this
    // endpoint is unauthenticated, so a distinct 403 `account_deactivated`
    // would tell anyone holding a userId whether that account is deactivated.
    // The deactivated owner still cannot sign in (no token is ever issued).
    return { status: 401, body: { error: 'challenge_expired' } };
  }

  let clientData;
  try { clientData = JSON.parse(Buffer.from(clientDataJSON, 'base64url').toString('utf8')); }
  catch { return { status: 400, body: { error: 'type_mismatch' } }; }

  // Atomic single-use consume BEFORE the signature check — a challenge that
  // fails verification is still spent, so a captured-but-failed attempt
  // cannot be retried against a fresh signature attempt using the same
  // challenge. See pool.ts's consumeChallenge() for the single-UPDATE
  // atomicity this relies on.
  const consumed = await consumeChallenge(pool, userId, 'login', clientData.challenge ?? '');
  if (!consumed) return { status: 401, body: { error: 'challenge_expired' } };

  const credential = await webauthnCredentialById(pool, credentialId);
  if (!credential || credential.userId !== userId) {
    return { status: 401, body: { error: 'unknown_credential' } };
  }

  const now = Date.now();
  const result = verifyAssertion({
    assertion: { credentialId, clientDataJSON, authenticatorData, signature },
    credential,
    expectedChallenge: clientData.challenge ?? '',
    expectedOrigin: RP_ORIGIN,
    expectedRpIdHash: createHash('sha256').update(RP_ID, 'utf8').digest(),
    // challengeIssuedAt: now — this repo enforces the challenge TTL and
    // single-use exactly once, inside consumeChallenge()'s own atomic UPDATE
    // (which already applies auth.ts's own 5-minute default, see pool.ts's
    // CHALLENGE_TTL_MS). Passing `now` here makes verifyAssertion()'s OWN,
    // independent TTL check a deliberate no-op rather than a second, weaker
    // copy of the same rule that could silently drift out of sync with the
    // DB-side constant.
    challengeIssuedAt: now,
    now,
  });
  if (!result.ok) {
    // Denial names the real reason (auth.ts's own AuthFailure), matching
    // this codebase's "denial names the reason" convention rather than a
    // generic 'invalid' — see packages/api/test/stack.test.mjs's P6/P7 cases.
    return { status: 401, body: { error: result.reason } };
  }

  // A real compare-and-swap, not a bare write — see pool.ts's own comment on
  // updateWebauthnSignCount(). `false` here means a concurrent request for
  // this same credential already advanced sign_count to (or past) this exact
  // value first: the specific race a cloned authenticator used at the same
  // moment as the real one would produce. Denying the SECOND request to
  // finish is the whole point — a session must never be issued off the losing
  // side of that race.
  const advanced = await updateWebauthnSignCount(pool, credentialId, result.newSignCount);
  if (!advanced) {
    return { status: 401, body: { error: 'signcount_replay' } };
  }
  const token = issueSession(sessionKeys,
    { userId, roleName: 'guardian', childId: null, escalated: false }, now);
  return { status: 200, body: { token } };
}

// ---- observability + abuse limits (audit P-07 server half, P-08) ----------
const metrics = new Metrics();
const authLimiter = createAuthLimiter();
const ACCESS_LOG = process.env.ACCESS_LOG !== '0';
const ACCESS_LOG_HEALTHZ = process.env.ACCESS_LOG_HEALTHZ === '1';
// The three raw pre-session login routes (dispatched here, outside Api).
const RAW_AUTH_PATHS = new Set([
  '/v1/auth/dev-login',
  '/v1/auth/webauthn/login/challenge',
  '/v1/auth/webauthn/login/verify',
]);

/** Fixed, attacker-proof label for the access log / counters. */
function routeLabel(method, pathname, url) {
  if (pathname === '/healthz') return '/healthz';
  if (pathname === '/internal/metrics') return '/internal/metrics';
  if (pathname.startsWith('/media/')) return '/media/:key';
  if (RAW_AUTH_PATHS.has(url)) return url;
  return api.routeTemplate(method, url) ?? 'unmatched';
}

/** userId/childId named in a pre-session login body, for the per-identifier bucket. */
function loginIdentifier(raw) {
  try {
    const b = JSON.parse(raw || '{}');
    const id = b?.userId ?? b?.childId;
    return typeof id === 'string' && id ? id : null;
  } catch { return null; }
}

const server = createServer(async (req, res) => {
  const startedAt = performance.now();
  const method = req.method ?? 'GET';
  const url = req.url ?? '/';
  const pathname = url.split('?')[0];
  const id = requestIdFor(req);
  const label = routeLabel(method, pathname, url);
  res.setHeader('x-request-id', id);
  // Baseline security headers on EVERY response, including the signed-media
  // handler that writes its own head (writeHead's explicit values win).
  for (const [k, v] of Object.entries(securityHeaders(req))) res.setHeader(k, v);
  res.on('finish', () => {
    const ms = performance.now() - startedAt;
    metrics.record({ method, route: label, status: res.statusCode, ms });
    if (ACCESS_LOG && (label !== '/healthz' || ACCESS_LOG_HEALTHZ)) {
      console.log(accessLogLine({ id, method, route: label, status: res.statusCode, ms }));
    }
  });

  const send = (out, extraHeaders = {}) => {
    res.writeHead(out.status, {
      // charset=utf-8 explicit, not implied: RFC 2616's default charset for
      // an unlabelled response is ISO-8859-1/latin1, and at least one real
      // client in this codebase (package:http, used by court_export.dart's
      // live path) honors that default literally -- an em dash in a denial
      // message (server/routes.mjs's EXPORT_DENIAL_MESSAGES) is exactly the
      // kind of content that would otherwise round-trip corrupted, found
      // while wiring the certified-export denial copy for real.
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      ...extraHeaders,
    });
    res.end(JSON.stringify(out.body));
  };

  try {
    // Server-snoop hardening: in production nothing is served that did not
    // arrive over TLS (the loopback /healthz probe is the lone exemption).
    if (httpsRequired(req, process.env, pathname)) {
      metrics.inc('https_required_total');
      return send({ status: 400, body: { error: 'https_required' } }, { connection: 'close' });
    }

    // Docker healthcheck target (docker-compose.dev.yml / .prod.yml's
    // `server` service) — see this pass's CHANGELOG entry for why a real
    // HTTP check matters here: `depends_on: condition: service_healthy`
    // is only honest if "healthy" means the server can actually reach
    // Postgres, not just that the process bound a port. A bare `SELECT 1`
    // is the cheapest real proof of that — no session, no RLS context, no
    // app-data read, just "is this connection pool actually usable right
    // now." Unauthenticated deliberately, same posture as any other
    // liveness probe: it reveals only up/down, nothing about any family's
    // data. Bounded to 3 s (P-01): with the pool exhausted, pool.query()
    // would otherwise wait for a free slot and the probe would hang with it
    // instead of reporting the outage it exists to report.
    if (method === 'GET' && url === '/healthz') {
      try {
        await Promise.race([
          pool.query('SELECT 1'),
          new Promise((_, rej) => setTimeout(() => rej(new Error('healthz timeout')), 3000).unref()),
        ]);
        return send({ status: 200, body: { status: 'ok' } });
      } catch (e) {
        console.error(errorLine(e, { msg: 'healthz: database unreachable' }));
        // Same shape as the 200: an unauthenticated caller learns up/down and
        // nothing about WHY (the 503 status is what probes key on).
        return send({ status: 503, body: { status: 'unavailable' } });
      }
    }

    // In-process counters — internal callers only (see isInternalRequest).
    // A refused caller gets the same 404 any unknown path would.
    if (method === 'GET' && pathname === '/internal/metrics') {
      if (!isInternalRequest(req)) return send({ status: 404, body: { error: 'not_found' } });
      return send({ status: 200, body: metrics.snapshot({
        pool: { total: pool.totalCount, idle: pool.idleCount, waiting: pool.waitingCount },
        game_tables_open: gameTables.size,
      }) });
    }

    if (method === 'GET' && pathname.startsWith('/media/')) {
      return await serveSignedMedia(url, res, defaultMediaStorage,
        async (key) => (await mediaUploadFor(pool, key))?.mime ?? null);
    }

    // P-08 -- the whole /v1/auth/ surface is unauthenticated (or, for
    // webauthn register, only just authenticated): throttle per client IP
    // BEFORE spending anything on it, body included.
    // S-B1/S-B14 -- the pre-session pairing and invite routes are brute-force
    // and DB-amplification surfaces of their own: same per-IP throttle.
    const isAuthPath = pathname.startsWith('/v1/auth/')
      || pathname.startsWith('/v1/device-pairing/')
      || pathname.startsWith('/v1/guardian-invites/');
    if (isAuthPath) {
      const ip = authLimiter.checkIp(netId.anonKey(req));
      if (!ip.ok) {
        metrics.inc('rate_limited_total');
        return send({ status: 429, body: { error: 'rate_limited' } },
          { 'retry-after': String(ip.retryAfterSec) });
      }
    }

    // P-05 + P-08 -- byte-exact body, byte-counted cap. The three raw login
    // routes and every request without a verifying session get the small
    // unauthenticated cap; only a verified session gets the 40 MiB one.
    const limit = RAW_AUTH_PATHS.has(url)
      ? MAX_UNAUTH_BODY_BYTES : api.bodyLimitFor(method, url, req.headers);
    const read = await readRequestBody(req, limit);
    if (!read.ok) {
      if (read.reason === 'aborted') { req.destroy(); return; }
      metrics.inc('body_too_large_total');
      // Drain (discard, never buffer) the rest of the upload so the close
      // after the 413 is a clean FIN rather than an RST that can destroy the
      // 413 before the client reads it.
      req.resume();
      return send({ status: 413, body: { error: 'payload_too_large' } }, { connection: 'close' });
    }
    const raw = read.body;

    if (method === 'POST' && RAW_AUTH_PATHS.has(url)) {
      const ident = loginIdentifier(raw);
      if (ident) {
        const r = authLimiter.checkIdentifier(ident, netId.anonKey(req));
        if (!r.ok) {
          metrics.inc('rate_limited_total');
          return send({ status: 429, body: { error: 'rate_limited' } },
            { 'retry-after': String(r.retryAfterSec) });
        }
      }
      // Literal `req.url === '...'` comparisons, kept in this exact shape on
      // purpose: packages/api/test/contract.test.mjs finds the raw
      // pre-session routes by scanning this file's source for them.
      if (req.url === '/v1/auth/dev-login') return send(await devLogin(raw));
      if (req.url === '/v1/auth/webauthn/login/challenge') return send(await webauthnLoginChallenge(raw));
      if (req.url === '/v1/auth/webauthn/login/verify') return send(await webauthnLoginVerify(raw));
    }
    send(await api.handle(method, url, req.headers, raw));
  } catch (e) {
    console.error(errorLine(e, { msg: 'request failed' }));
    if (!res.headersSent) send({ status: 500, body: { error: 'internal' } });
  }
});

// Node's own upgrade event on the SAME http.Server and SAME port — no second
// listener, no LAN-broadcast/discovery mechanism of any kind. Every table
// connection is relayed through this one authenticated process.
const { wss, stopSweep } = attachGameSocketServer(server, {
  secret: gameTableSecret, tables: gameTables,
  upgradeAllowed: (req) => !httpsRequired(req, process.env, '/ws'),
});

server.listen(PORT, () => {
  console.log(`olive-branch server listening on :${PORT}` + (DEV_LOGIN ? ' (DEV_LOGIN enabled)' : ''));
});

// ---- graceful shutdown (audit P-14) -----------------------------------------
// See shutdown.mjs for the full why. Idempotent: signals arriving while a
// shutdown is already running share its promise, so pool.end() runs once.
const shutdown = createShutdown({
  server, wss, pool, stopTimers: [stopSweep],
  deadlineMs: Number(process.env.SHUTDOWN_DEADLINE_MS) > 0
    ? Number(process.env.SHUTDOWN_DEADLINE_MS) : DEFAULT_SHUTDOWN_DEADLINE_MS,
  log: (line) => console.log(line),
});
const onSignal = (sig) => {
  shutdown(sig).then(() => process.exit(0), (e) => { console.error(errorLine(e, { msg: 'shutdown failed' })); process.exit(1); });
};
process.on('SIGINT', () => onSignal('SIGINT'));
process.on('SIGTERM', () => onSignal('SIGTERM'));

// A rejected promise nobody awaited must not take every family's session
// down with it (Node's default is to crash the process), but it must never be
// silent either: log it as one structured line and count it.
process.on('unhandledRejection', (reason) => {
  metrics.inc('unhandled_rejection_total');
  console.error(errorLine(reason, { msg: 'unhandledRejection' }));
});
// An uncaught exception IS undefined state: log it, then shut down cleanly
// (so the pool drains and websockets get a close frame) and exit non-zero so
// the orchestrator restarts a fresh process.
process.on('uncaughtException', (err) => {
  console.error(errorLine(err, { msg: 'uncaughtException' }));
  shutdown('uncaughtException').finally(() => process.exit(1));
});
