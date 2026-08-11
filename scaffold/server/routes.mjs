// OLIVE BRANCH — real route handlers, registered on packages/api/src/api.ts's
// Api instance. MASTERFILE §7.
//
// Scoped deliberately narrow for this pass: enough of a real, working slice
// to prove genuine end-to-end wiring (client -> HTTP -> auth -> RLS-scoped
// Postgres query -> real data), not full coverage of every documented
// endpoint. `/now` resolves a child's real zone from child_tz_interval,
// falling back to child.home_tz, exactly as MASTERFILE §6.1's childZoneAt()
// describes -- that function was previously only prose, never code, since
// time.ts's exports are all pure (no DB access). Day-part classification
// (school/bedtime/etc.) is NOT wired yet -- a real follow-up, not silently
// glossed over.
import { createHash, timingSafeEqual } from 'node:crypto';
import { DateTime } from 'luxon';
import { activeCustodyOrderFor, guardiansOfChild, setPinCredential,
         attemptPinFor, createChallenge, consumeChallenge,
         storeWebauthnCredential, availabilityFor,
         setAvailabilityWindows } from '../packages/db/src/pool.mjs';
import { sleepsUntilSideChange } from '../packages/custody/src/schedule.mjs';
import { hashPin } from '../packages/auth/src/auth.mjs';
import { parseAttestationObject, extractCredentialPublicKey } from '../packages/auth/src/attestation.mjs';

/**
 * LOCAL DEV/TEST ONLY — same honesty convention server/index.mjs's own
 * dev-login header already uses for a placeholder that must not survive to
 * production unexamined. 'olivebranch.local' is not a real, resolvable
 * production domain; RP_ID/RP_ORIGIN below MUST become the actual deployed
 * domain before this ships, or every real WebAuthn ceremony will fail its
 * own rpId/origin check against a host nobody ever served this app from.
 * Exported so server/index.mjs's pre-session WebAuthn LOGIN routes (which
 * cannot go through api.register(), see that file's own header) use the
 * exact same string rather than a second, driftable copy.
 */
export const RP_ID = 'olivebranch.local';
export const RP_ORIGIN = `https://${RP_ID}`;

const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * Validates the PUT /v1/me/availability body shape before it ever reaches
 * pool.mjs's setAvailabilityWindows() — a 400 with a specific reason here is
 * more useful than a Postgres CHECK-constraint or RLS error surfacing as a
 * bare 500. Returns a string reason on failure, null on a valid array.
 */
function invalidAvailabilityBody(body) {
  if (!Array.isArray(body)) return 'body_must_be_array';
  for (const w of body) {
    if (!w || typeof w !== 'object') return 'window_must_be_object';
    if (!Number.isInteger(w.weekday) || w.weekday < 0 || w.weekday > 6) return 'bad_weekday';
    if (typeof w.startLocal !== 'string' || !HHMM.test(w.startLocal)) return 'bad_startLocal';
    if (typeof w.endLocal !== 'string' || !HHMM.test(w.endLocal)) return 'bad_endLocal';
    if (w.endLocal <= w.startLocal) return 'endLocal_before_startLocal';
    if (w.note !== undefined && w.note !== null && typeof w.note !== 'string') return 'bad_note';
  }
  return null;
}

/**
 * @param {import('../packages/api/src/api.ts').Api} api
 * @param {import('pg').Pool} pool raw pool, needed for activeCustodyOrderFor()
 *   — it runs its own withSystemSession (see pool.ts), independent of the
 *   caller-scoped session api.handle() already opened for this request.
 */
export function registerRoutes(api, pool) {
  api.register({
    method: 'GET', path: '/v1/me', action: null,
    handler: async (c, q) => {
      // Her own name, not an id (§8.1) -- resolved for real here so a live
      // client never has to hardcode "Ivy" the way the demo build does.
      const displayName = c.principal.roleName === 'child'
        ? (await q(`SELECT display_name FROM child WHERE id = $1`, [c.principal.childId]))[0]?.display_name
        : (await q(`SELECT display_name FROM app_user WHERE id = $1`, [c.principal.userId]))[0]?.display_name;
      return { body: {
        userId: c.principal.userId,
        childId: c.principal.childId,
        roleName: c.principal.roleName,
        escalated: c.principal.escalated,
        displayName: displayName ?? null,
      } };
    },
  });

  api.register({
    // No dedicated Action exists for "view her current status/time" in
    // family-graph/src/authorize.ts's Action union — another real gap this
    // pass surfaces rather than papering over with an invented string `can()`
    // was never taught to recognize. calendar.view is the closest existing
    // fit (schedule/status-adjacent) until a real §7 action is specified.
    method: 'GET', path: '/v1/children/:childId/now', action: 'calendar.view',
    handler: async (c, q) => {
      const nowUtc = DateTime.utc();
      const interval = await q(
        `SELECT tz FROM child_tz_interval
          WHERE child_id = $1 AND valid @> $2::timestamptz
          ORDER BY confidence DESC LIMIT 1`,
        [c.childId, nowUtc.toJSDate()],
      );
      let tz = interval[0]?.tz;
      if (!tz) {
        const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [c.childId]);
        if (!child.length) return { status: 404, body: { error: 'child_not_found' } };
        tz = child[0].home_tz;
      }
      const local = nowUtc.setZone(tz);
      // §8.2.5 — "3 sleeps until Dad's week" is counted on HER local day
      // boundaries (child-local), never the order's zone or the server's.
      const nowLocalDate = local.toISODate();
      const order = await activeCustodyOrderFor(pool, c.childId, nowLocalDate);
      // Honest absence: a child with no active custody order gets null here,
      // never a guessed/fabricated countdown (db/migrations/0007's own
      // reasoning; see custody_order.test.mjs's NOORDER fixture).
      const sleepsUntilHandover = order
        ? sleepsUntilSideChange(order, nowLocalDate)?.sleeps ?? null
        : null;
      return { body: {
        childLocalTime: local.toFormat('h:mm a'),
        zoneAbbr: local.toFormat('ZZZZ'),
        zone: tz,
        sleepsUntilHandover,
      } };
    },
  });

  api.register({
    method: 'GET', path: '/v1/children/:childId/inbox', action: 'message',
    handler: async (c, q) => {
      const rows = await q(
        `SELECT di.id, di.payload_kind, di.sender_id, di.state,
                di.materialized_at::text, u.display_name AS sender_name
           FROM delivery_intent di
           JOIN app_user u ON u.id = di.sender_id
          WHERE di.child_id = $1 AND di.state IN ('delivered','opened')
          ORDER BY di.materialized_at DESC NULLS LAST
          LIMIT 50`,
        [c.childId],
      );
      return { body: { messages: rows } };
    },
  });

  // ===========================================================================
  // REAL AUTHENTICATION — replaces the hardcoded, unauthenticated '1273'
  // guardian PIN (client/lib/main.dart's `_demoGuardianPin`). §7.1, §8.1, §8.3.
  // ===========================================================================

  // Child-side kiosk unlock: the child's device holds a child session; typing
  // a code here checks it against every LIVE guardian of that exact child,
  // never against a single "the" PIN. `action: null` + identityScopedByHandler
  // — see api.ts's own comment on that field — because the decision here is
  // "is this session literally this child", not a guardianship-edge decision
  // `can()` was built to answer (a child holds no edge to herself).
  api.register({
    method: 'POST', path: '/v1/children/:childId/kiosk-pin/verify',
    action: null, identityScopedByHandler: true,
    // See api.ts's Route.skipOuterSession doc comment — this handler runs
    // every DB call scoped to a GUARDIAN's own session (attemptPinFor et al.),
    // never the calling child's, so the outer withSession() api.handle() would
    // otherwise open is pure dead weight — and, under concurrency, the exact
    // self-deadlock this flag exists to close (confirmed live: 10-15
    // concurrent requests here froze the whole server before this fix).
    skipOuterSession: true,
    handler: async (c) => {
      if (c.principal.roleName !== 'child' || c.principal.childId !== c.childId) {
        return { status: 403, body: { error: 'not_this_child' } };
      }
      const pin = c.body?.pin;
      if (typeof pin !== 'string') return { status: 400, body: { error: 'pin_required' } };

      const guardians = await guardiansOfChild(pool, c.childId);
      // Deliberately NOT short-circuited on the first match: every guardian
      // gets the same treatment (attemptPinFor(): load credential, skip if
      // locked, verify, record the attempt, all as ONE atomic, row-locked
      // step — see pool.ts's own comment on why that atomicity, not just the
      // per-guardian loop shape, is what actually defends the lockout under
      // concurrent guessing) regardless of whether an earlier guardian in the
      // list already matched, so response latency is not a function of WHICH
      // guardian's PIN was tried, or of whether one matched at all. The one
      // accepted, DOCUMENTED gap: a LOCKED guardian's scrypt verification is
      // skipped entirely rather than run-and-discarded, so total latency
      // still varies with how many of a child's guardians are currently
      // locked out. A full constant-time guarantee across all N guardians
      // would mean running scrypt against every guardian unconditionally,
      // including ones a lock has already made unmatchable — real, avoidable
      // cost bought for a narrower leak (lockout counts, not identities) than
      // the one this design already closes (which specific guardian's PIN,
      // or whether any guardian has a PIN configured at all).
      let matched = false;
      for (const g of guardians) {
        const r = await attemptPinFor(pool, g.userId, pin);
        if (r.matched) matched = true;
      }
      // Same shape whether the PIN was wrong, no guardian has one set yet, or
      // every guardian is currently locked out — a network trace cannot tell
      // these apart, matching auth.ts's own posture on its primitives.
      return { body: { ok: matched } };
    },
  });

  // Guardian sets/replaces her own PIN. No :childId in the path, so this is
  // an ordinary action:null identity route (same shape as GET /v1/me above) —
  // no A1 exception needed.
  api.register({
    method: 'POST', path: '/v1/me/pin', action: null,
    // See api.ts's Route.skipOuterSession doc comment — setPinCredential runs
    // its own guardian-scoped session; the outer one would sit idle.
    skipOuterSession: true,
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'guardian_session_required' } };
      }
      const pin = c.body?.pin;
      if (typeof pin !== 'string') return { status: 400, body: { error: 'pin_required' } };
      let hash;
      try { hash = hashPin(pin); }
      // hashPin's own 4-8-digit validation throw surfaces as a 400, not a 500
      // — a malformed PIN is caller error, not server error.
      catch { return { status: 400, body: { error: 'invalid_pin_format' } }; }
      await setPinCredential(pool, c.principal.userId, hash);
      return { body: { ok: true } };
    },
  });

  // WebAuthn REGISTRATION challenge — guardian session required. (LOGIN's two
  // routes live in server/index.mjs: they establish identity, so they run
  // before any session exists and cannot go through api.register() at all —
  // see that file's own header.)
  api.register({
    method: 'POST', path: '/v1/auth/webauthn/register/challenge', action: null,
    // See api.ts's Route.skipOuterSession doc comment.
    skipOuterSession: true,
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'guardian_session_required' } };
      }
      const challenge = await createChallenge(pool, c.principal.userId, 'register');
      return { body: { challenge, rpId: RP_ID, userId: c.principal.userId } };
    },
  });

  api.register({
    // MASTERFILE §9, MARKUP screen 'availability' — "when he can actually be
    // reached, honestly rendered." No dedicated Action exists for this in
    // family-graph/src/authorize.ts's Action union (same real gap the /now
    // route's own comment calls out); calendar.view is the closest existing
    // fit — schedule/reachability-adjacent, already granted to every adult
    // role that should plausibly see it, and (per Api.handle's own child
    // branch) a same-family child session passes through regardless of the
    // specific action chosen, so the child sees her own family's windows too.
    method: 'GET', path: '/v1/children/:childId/availability', action: 'calendar.view',
    handler: async (c) => {
      const windows = await availabilityFor(pool, c.childId);
      return { body: { windows } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/auth/webauthn/register/verify', action: null,
    // See api.ts's Route.skipOuterSession doc comment.
    skipOuterSession: true,
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'guardian_session_required' } };
      }
      const { clientDataJSON, attestationObject } = c.body ?? {};
      if (typeof clientDataJSON !== 'string' || typeof attestationObject !== 'string') {
        return { status: 400, body: { error: 'bad_request' } };
      }
      let clientData;
      try { clientData = JSON.parse(Buffer.from(clientDataJSON, 'base64url').toString('utf8')); }
      catch { return { status: 400, body: { error: 'bad_client_data' } }; }
      if (clientData.type !== 'webauthn.create') {
        return { status: 400, body: { error: 'type_mismatch' } };
      }
      if (clientData.origin !== RP_ORIGIN) {
        return { status: 400, body: { error: 'origin_mismatch' } };
      }
      // Atomic single-use consume — see pool.ts's consumeChallenge() for why
      // this is one UPDATE, not a check then a write.
      const consumed = await consumeChallenge(
        pool, c.principal.userId, 'register', clientData.challenge ?? '');
      if (!consumed) return { status: 400, body: { error: 'challenge_mismatch' } };

      let fmt, authData;
      try { ({ fmt, authData } = parseAttestationObject(attestationObject)); }
      catch { return { status: 400, body: { error: 'bad_attestation_object' } }; }

      // WebAuthn L2 §7.1 step 13 — the rpIdHash inside authData must be
      // sha256(rpId), checked here (not attestation.ts, which is pure binary
      // parsing — see its own header) with the SAME constant-time compare
      // auth.ts's own verifyAssertion() uses for the login half of this same
      // check, so registration and login apply the identical standard.
      const expectedRpIdHash = createHash('sha256').update(RP_ID, 'utf8').digest();
      const gotRpIdHash = authData.subarray(0, 32);
      if (gotRpIdHash.length !== expectedRpIdHash.length ||
          !timingSafeEqual(gotRpIdHash, expectedRpIdHash)) {
        return { status: 400, body: { error: 'rpid_mismatch' } };
      }

      let credentialId, publicKeyPem;
      try { ({ credentialId, publicKeyPem } = extractCredentialPublicKey(authData)); }
      catch { return { status: 400, body: { error: 'bad_public_key' } }; }

      await storeWebauthnCredential(pool, c.principal.userId, credentialId, publicKeyPem);
      return { body: { ok: true } };
    },
  });

  api.register({
    // Identity-only (no :childId in the path) — action MUST be null per
    // Api.register's own A1 rule, matching GET /v1/me above. The guardian
    // sets HER OWN windows; guardianId is always c.principal.userId, the
    // authenticated caller, never anything the body could redirect (A3's
    // own discipline, applied here to the guardian's identity instead of a
    // child's).
    method: 'PUT', path: '/v1/me/availability', action: null,
    handler: async (c) => {
      if (c.principal.roleName !== 'guardian' || !c.principal.userId) {
        return { status: 403, body: { error: 'guardian_only' } };
      }
      const reason = invalidAvailabilityBody(c.body);
      if (reason) return { status: 400, body: { error: reason } };
      await setAvailabilityWindows(pool, c.principal.userId, c.body.map((w) => ({
        weekday: w.weekday, startLocal: w.startLocal, endLocal: w.endLocal,
        note: w.note ?? null,
      })));
      return { status: 200, body: { ok: true } };
    },
  });
}
