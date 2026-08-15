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
import { issueSession, verifyAssertion } from '../packages/auth/src/auth.mjs';
import { Api } from '../packages/api/src/api.mjs';
import { createPool, dbPort, withSystemSession, createChallenge, consumeChallenge,
         webauthnCredentialById, updateWebauthnSignCount } from '../packages/db/src/pool.mjs';
import { registerRoutes, RP_ID, RP_ORIGIN } from './routes.mjs';

const PORT = Number(process.env.PORT ?? 8080);
const DATABASE_URL = process.env.DATABASE_URL;
const SESSION_SECRET = process.env.SESSION_SECRET;
const DEV_LOGIN = process.env.DEV_LOGIN === '1';

if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }
if (!SESSION_SECRET) { console.error('SESSION_SECRET required'); process.exit(2); }

const pool = createPool(DATABASE_URL);
const secret = Buffer.from(SESSION_SECRET, 'utf8');
const api = new Api(secret, dbPort(pool));
registerRoutes(api, pool);

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
      const token = issueSession(secret,
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
    const token = issueSession(secret,
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
  const exists = await withSystemSession(pool,
    (q) => q(`SELECT id FROM app_user WHERE id = $1`, [userId]));
  if (!exists.length) return { status: 404, body: { error: 'user_not_found' } };
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
  const token = issueSession(secret,
    { userId, roleName: 'guardian', childId: null, escalated: false }, now);
  return { status: 200, body: { token } };
}

const server = createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => { raw += c; if (raw.length > 2_000_000) req.destroy(); });
  req.on('end', async () => {
    const send = (out) => {
      res.writeHead(out.status, {
        'content-type': 'application/json',
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      });
      res.end(JSON.stringify(out.body));
    };
    try {
      if (req.method === 'POST' && req.url === '/v1/auth/dev-login') {
        return send(await devLogin(raw));
      }
      if (req.method === 'POST' && req.url === '/v1/auth/webauthn/login/challenge') {
        return send(await webauthnLoginChallenge(raw));
      }
      if (req.method === 'POST' && req.url === '/v1/auth/webauthn/login/verify') {
        return send(await webauthnLoginVerify(raw));
      }
      send(await api.handle(req.method ?? 'GET', req.url ?? '/', req.headers, raw));
    } catch (e) {
      console.error(e);
      send({ status: 500, body: { error: 'internal' } });
    }
  });
});

server.listen(PORT, () => {
  console.log(`olive-branch server listening on :${PORT}` + (DEV_LOGIN ? ' (DEV_LOGIN enabled)' : ''));
});

process.on('SIGINT', () => { server.close(() => pool.end().then(() => process.exit(0))); });
process.on('SIGTERM', () => { server.close(() => pool.end().then(() => process.exit(0))); });
