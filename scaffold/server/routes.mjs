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
         setAvailabilityWindows, deactivateAccount,
         rawExportBundleFor, edgesFor, childCtxFor,
         persistCapturedMessage, registerDeviceToken,
         unregisterDeviceToken,
         certifiedExportBundleFor,
         createGuardianInvite, getGuardianInvite,
         acceptGuardianInvite, revokeGuardianInvite,
         takeAndGo, themeFor, setChildTheme,
         recordCallStart, recordCallEnd,
         INVITABLE_ROLES } from '../packages/db/src/pool.mjs';
import { sleepsUntilSideChange } from '../packages/custody/src/schedule.mjs';
import { runHomeworkCapture } from '../packages/homework/src/capture-route.mjs';
import { hashPin } from '../packages/auth/src/auth.mjs';
import { parseAttestationObject, extractCredentialPublicKey } from '../packages/auth/src/attestation.mjs';
import { captureMessage } from '../packages/messaging/src/pipeline.mjs';
import { CHANNELS } from '../packages/devices/src/devices.mjs';
import { createSession, mintToken } from '../packages/session-runtime/src/rooms.mjs';
import { notifyDevices } from '../packages/transport/src/notify.mjs';

/**
 * Same fallback and env var name `tools/local-call-room-server.mjs` already
 * uses, on purpose — this route is the real, authenticated replacement for
 * that dev-only script's `/room` endpoint, not a second, independently-
 * configured path to the same self-hosted Jitsi stack. See docker-compose
 * .dev.yml's `server` service for where this gets set in the containerized
 * dev stack.
 */
const JITSI_SERVER_URL = process.env.JITSI_SERVER_URL ?? 'https://meet.jit.si';

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

// client/lib/theme.dart's ThemePalette/ThemeBrightness enums, by `.name` —
// the exact wire values db/migrations/0017_child_theme_preference.sql's own
// CHECK constraints already admit; kept here too so a bad body gets a real
// 400 with a specific reason rather than surfacing as a bare Postgres
// constraint-violation 500 (same reasoning invalidAvailabilityBody gives).
const THEME_PALETTES = new Set(
  ['classic', 'calmModern', 'warmGrounded', 'softPlayful', 'deepCozy', 'brightBold']);
const THEME_BRIGHTNESSES = new Set(['light', 'dark']);

function invalidThemeBody(body) {
  if (!body || typeof body !== 'object') return 'body_must_be_object';
  if (!THEME_PALETTES.has(body.themePalette)) return 'bad_themePalette';
  if (!THEME_BRIGHTNESSES.has(body.themeBrightness)) return 'bad_themeBrightness';
  return null;
}

const DEVICE_PLATFORMS = new Set(['android', 'ios']);

// §8.11.4 (v0.49.11) — validated against devices.ts's own CHANNELS rather
// than a third hand-typed list of the same six values; see channels.ts's
// header for what happened the last time this codebase kept two copies of
// this enum in sync by hand.
const DEVICE_CHANNELS = new Set(CHANNELS.map((c) => c.channel));

/**
 * Plain-language companions to packages/db/src/pool.ts's
 * `CertifiedExportDenial` reasons — MASTERFILE §2.11's own rule: a denial
 * must say plainly WHY, and since no payment flow exists anywhere in this
 * codebase, that upgrading is not available in this build rather than
 * rendering a paywall that has nothing real behind it.
 *
 * `tier_required` is the ONLY reason ledger.ts's authorizeExport() (line
 * ~167) ever actually returns once a guardian's certified-export request is
 * denied — it fires precisely when the rolling-12-month free allowance has
 * already been spent AND the guardian lacks Court tier (there is no separate
 * code path in authorizeExport() that returns while the allowance is still
 * available but Court tier is missing, since an available allowance always
 * authorizes for free regardless of tier). Its message below says both halves
 * of that plainly, rather than only the tier half. `annual_allowance_used` is
 * kept here because it remains part of ledger.ts's own `ExportDenial` type —
 * a future change to that pre-existing, untouched function could start
 * returning it — but no live call produces it today.
 */
const EXPORT_DENIAL_MESSAGES = {
  no_edge: 'You are not a guardian of this child.',
  edge_closed: 'Your guardianship of this child has closed.',
  edge_expired: 'Your access to this child has expired.',
  outside_validity: 'Your access to this child is not currently active.',
  restricted: 'Your access to this child is restricted.',
  role_lacks_capability: 'Your role does not include certified export.',
  scope_denied: 'Certified export is switched off for your access to this child.',
  annual_allowance_used:
    "This year's free certified export has already been used. Court tier covers "
    + 'any additional ones — there is no payment flow in this build to upgrade, '
    + 'so a Court-tier flag has to be set by an admin, by hand, until one exists.',
  tier_required:
    "This year's free certified export has already been used, and additional "
    + 'certified exports require Court tier. There is no payment flow in this build '
    + 'to upgrade — Court tier has to be set by an admin, by hand, until one exists.',
  chain_broken:
    "This child's handover log did not verify as an unbroken chain, so no certified "
    + 'export was produced. Raw export is unaffected and remains free and unlimited.',
};

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
    // MASTERFILE §2.10, §2.11, §9.8, P8 — account deletion, for real.
    // `action: null` (identity-only, same as GET /v1/me above): this is not
    // child-scoped and does not go through can()/edgesFor() at all — a
    // guardian deactivating THEIR OWN account is an identity operation, not
    // an action against a child's data. The userId acted on comes ONLY from
    // `c.principal.userId` (the verified session, A2/A3's own rule — never
    // from the request body), so there is nothing here for a request body to
    // widen. deactivateAccount() (packages/db/src/pool.mjs) additionally
    // enforces the same restriction a SECOND way, independently, via RLS
    // (0011_account_deletion.sql's app_user_self_update policy) — even a bug
    // in this handler that passed the wrong id could not reach another
    // guardian's row.
    method: 'POST', path: '/v1/me/delete', action: null,
    handler: async (c) => {
      // A child principal always has userId: null (readSession's own
      // invariant, packages/auth/src/auth.ts) — children have no login of
      // their own to delete (§11), so this is the real, structural guard,
      // not just a nicety.
      if (!c.principal.userId) {
        return { status: 400, body: { error: 'no_user_identity' } };
      }
      try {
        const result = await deactivateAccount(pool, c.principal.userId, c.principal.roleName);
        return { status: 200, body: { ok: true, ...result } };
      } catch (e) {
        if (e?.code === 'already_deactivated') {
          return { status: 409, body: { error: 'already_deactivated' } };
        }
        if (e?.code === 'account_not_found') {
          return { status: 404, body: { error: 'account_not_found' } };
        }
        throw e; // -> Api.handle's catch-all -> 500, logged there
      }
    },
  });

  // ===========================================================================
  // GUARDIAN INVITATION — real create/read/accept-decision/revoke. §11, §8.5.
  // Closes half of invitation_screen.dart's own named gap: "the API surface
  // names POST /v1/children/:id/guardianships, but no such route exists."
  // Does NOT create a `guardianship` row — see 0014_guardian_invite.sql's own
  // header for why that would fabricate an account-creation security step
  // this codebase has never built.
  // ===========================================================================

  api.register({
    method: 'POST', path: '/v1/children/:childId/guardianships',
    // No dedicated Action exists for "invite" in authorize.ts's Action union
    // (same real gap this file's own /now route already names for a
    // different action) — checked directly below rather than widening that
    // shared enum for one caller.
    action: null, identityScopedByHandler: true,
    // createGuardianInvite() opens its own correctly-scoped session; the
    // outer default would be an unused connection, same "dead weight" the
    // kiosk-pin/verify route above already documents.
    skipOuterSession: true,
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'child_cannot_invite' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };

      // The first lock: does this caller actually hold a LIVE, unrestricted
      // guardian edge to this exact child? edgesFor() returns every edge —
      // closed, expired, restricted included, per its own doc comment — so
      // every one of those is checked explicitly, not assumed away.
      const now = new Date();
      const edges = await edgesFor(pool, c.principal.userId);
      const isLiveGuardian = edges.some((e) =>
        e.childId === c.childId && e.role === 'guardian' && !e.restricted &&
        !e.closedAt && (!e.expiresAt || new Date(e.expiresAt) > now));
      if (!isLiveGuardian) return { status: 403, body: { error: 'not_a_guardian_of_child' } };

      const { role, label, invitedEmail } = c.body ?? {};
      if (typeof role !== 'string' || !INVITABLE_ROLES.includes(role)) {
        return { status: 400, body: { error: 'invalid_role' } };
      }
      if (typeof label !== 'string' || !label.trim()) {
        return { status: 400, body: { error: 'label_required' } };
      }
      if (typeof invitedEmail !== 'string' || !invitedEmail.includes('@')) {
        return { status: 400, body: { error: 'invited_email_required' } };
      }

      const result = await createGuardianInvite(
        pool, c.principal.userId, c.childId, role, label.trim(), invitedEmail);
      if (!result.ok) return { status: 400, body: { error: result.reason } };
      return { status: 201, body: { ok: true, invite: result.invite } };
    },
  });

  // The invited party has no app_user row and therefore no session — see
  // 0014's own header and getGuardianInvite()'s doc comment. The invite's
  // own long, random `id` (handed out of band: a link or code, not this
  // route's concern) is what authorizes reading it. Never lists invites.
  //
  // noSessionRequired (fixed post-merge, found by an adversarial audit of
  // this whole pass): registering this with only `action: null,
  // skipOuterSession: true` — as this route originally did — still left it
  // behind api.handle()'s unconditional Bearer-token gate, which 401'd
  // every call from the invited party this route was built for (they have
  // no session to send one from) and from api_client.dart's own
  // fetchGuardianInvite(), which deliberately sends no Authorization header
  // to match. Verified empirically before this fix: calling api.handle()
  // directly on this exact route shape returned 401 no_session, the
  // handler never reached. See api.ts's own noSessionRequired doc comment
  // for the fix and why it mirrors the webauthn-login bypass.
  api.register({
    method: 'GET', path: '/v1/guardian-invites/:inviteId', action: null,
    skipOuterSession: true, noSessionRequired: true,
    handler: async (c) => {
      const invite = await getGuardianInvite(pool, c.params.inviteId);
      if (!invite) return { status: 404, body: { error: 'not_found' } };
      return { status: 200, body: { invite } };
    },
  });

  // Same noSessionRequired fix, same reason — acceptGuardianInvite() is the
  // other half of the flow an unauthenticated invited party must be able to
  // reach; api_client.dart's acceptGuardianInvite() also sends no
  // Authorization header.
  api.register({
    method: 'POST', path: '/v1/guardian-invites/:inviteId/accept', action: null,
    skipOuterSession: true, noSessionRequired: true,
    handler: async (c) => {
      const result = await acceptGuardianInvite(pool, c.params.inviteId, new Date());
      if (!result.ok) {
        const status = result.reason === 'not_found' ? 404
          : result.reason === 'expired' ? 410 : 409;
        return { status, body: { error: result.reason } };
      }
      return { status: 200, body: { ok: true, invite: result.invite } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/guardian-invites/:inviteId/revoke', action: null,
    skipOuterSession: true,
    handler: async (c) => {
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const result = await revokeGuardianInvite(
        pool, c.params.inviteId, c.principal.userId, new Date());
      if (!result.ok) {
        const status = result.reason === 'not_found' ? 404 : 409;
        return { status, body: { error: result.reason } };
      }
      return { status: 200, body: { ok: true } };
    },
  });

  // ===========================================================================
  // CALL — real, authenticated room-coordination + ringing. §5.19, §5.21,
  // §5.25.2. The real replacement for tools/local-call-room-server.mjs's own
  // two-hardcoded-principal `/room` endpoint: a live audit of that script
  // found it has no persistence, no N-guardian support, and — separately —
  // that push.ts's `call_incoming` kind has zero real callers anywhere in
  // this codebase despite the client-side knock screen and push decoder
  // both being real, tested, and waiting for exactly this. This route closes
  // both gaps at once, since they're the same missing piece: a callee can
  // only be told to ring with a room she's actually authorized to join.
  //
  // Deliberately narrow, matching this file's own header discipline: mints
  // ONE session per call, for a live guardian calling a child she has a
  // real, unrestricted, unexpired guardian edge to. Does not attempt the
  // fuller persisted, N-guardian, group-call room-coordination service a
  // production deployment eventually needs — recorded as a real, larger
  // follow-up, not invented here. `createSession()`/`mintToken()` are pure
  // (packages/session-runtime/src/rooms.ts's own header: no DB access) —
  // this route is what gives them their first live, authenticated caller.
  // ===========================================================================

  api.register({
    method: 'POST', path: '/v1/children/:childId/calls',
    // Unlike the guardian-invitation route above, 'call' IS already a real,
    // recognized Action (authorize.ts's own can() — the exact check
    // mintToken() below runs a second time, at mint, per its own I4
    // invariant). So this route uses the ordinary generic gate rather than
    // adding a fifth action:null exception to contract.test.mjs's own
    // deliberately narrow whitelist — api.ts's own dispatcher already
    // fetches this caller's real edges and runs can('call', edges,
    // childId, ...) before this handler ever starts, on the exact same
    // authorization function mintToken() itself relies on.
    action: 'call',
    handler: async (c) => {
      // The generic gate above does NOT reject a child principal outright
      // for 'call' (it isn't a P6/P7-restricted action) — but this route's
      // whole shape is "a guardian STARTS a call, rings the child"; a child
      // hitting this route herself doesn't correspond to anything this app
      // does, so that business rule is still this handler's own to enforce.
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'child_cannot_start_call' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };

      const now = new Date();
      // mintToken() below needs this caller's real edges as an input to
      // compute their own grant (observer-only vs full-publish) — a second
      // fetch from what the outer gate already did internally, since Ctx
      // doesn't expose that result to the handler. Harmless: this caller's
      // authorization was already proven by the outer gate; this is data,
      // not a re-decision.
      const edges = await edgesFor(pool, c.principal.userId);

      // The caller's REAL ladder step for THIS child — found and fixed by a
      // live audit (2026-08-23) that this route previously hardcoded 'open'
      // here despite already having the real per-edge value in hand one
      // line above, which meant rooms.ts's own tested "supervised calls are
      // recorded and disclosed" logic (recorded: input.ladderStep ===
      // 'supervised') could never fire through this route, even for a
      // guardian whose real edge genuinely is supervised. `?? 'open'`
      // mirrors authorize.ts's own convention for a null ladderStep
      // (edgesFor() returns null, not the string 'open', for an edge with
      // no explicit contact_ladder row) — matches the outer gate's own
      // resolution of the identical value, not a fresh policy invented here.
      const realLadderStep = edges.find((e) => e.childId === c.childId)?.ladderStep ?? 'open';

      const session = createSession({
        childId: c.childId,
        kind: 'call',
        createdBy: c.principal.userId,
        // The child herself is authorized by construction (it's her call),
        // named positionally the same way local-call-room-server.mjs's own
        // dev session already does for the identical reason — a child
        // principal has no app_user row / real userId to list here, see
        // that script's own header for the fuller account of why this is
        // an accepted, pre-existing pattern, not new to this route.
        authorizedUserIds: [c.principal.userId, c.childId],
        ladderStep: realLadderStep,
      });

      const minted = mintToken(
        session,
        { userId: c.principal.userId, observerOnly: false, isChild: false, roleName: c.principal.roleName },
        edges, now,
      );
      if (!minted.ok) return { status: 403, body: { error: minted.reason } };

      // Ring the child's own device(s) — the actual gap this route closes.
      // A send failure here is reported, not thrown: the caller can still
      // join and wait (the same "call, then hope she notices" posture this
      // whole codebase had before this route existed), just without the
      // one improvement this route adds on top of that.
      const pushResults = await notifyDevices(pool, { childId: c.childId }, {
        kind: 'call_incoming',
        ref: session.id,
        callRoomHandle: session.roomName,
      });
      const rang = pushResults.some((r) => r.ok);

      // The real backing for security.ts's own RESIDUAL_RISKS claim that
      // call metadata is retained — found by the same 2026-08-23 audit to
      // have zero implementation anywhere before this. A write failure here
      // must never fail the call itself (the same posture notifyDevices()
      // above already has) — logged, not thrown, so a real database hiccup
      // degrades to "this one call goes unlogged" rather than "no one can
      // call at all".
      try {
        await recordCallStart(pool, {
          id: session.id, childId: c.childId, startedBy: c.principal.userId,
          participantIds: [c.principal.userId], roomName: session.roomName,
          ladderStep: realLadderStep, recorded: minted.token.recorded, rang,
        });
      } catch (e) {
        console.error(`[call_log] failed to record call start for session ${session.id}:`, e);
      }

      return {
        status: 201,
        body: {
          room: session.roomName,
          serverURL: JITSI_SERVER_URL,
          identity: minted.token.identity,
          displayName: 'Dad',
          rang,
          // Lets CallScreen's own hang-up path call the new end-call route
          // below on the exact session this response minted, without the
          // client needing to invent or track its own identifier.
          sessionId: session.id,
        },
      };
    },
  });

  // ===========================================================================
  // CALL END — marks call_log's own row ended. Found by the same 2026-08-23
  // audit: revokeLiveAccess()/endSession() (packages/transport/src/push.ts)
  // are the only server-side room-lifecycle functions, real and unit-tested
  // in isolation, but were never called from anywhere — no route in this
  // repo could actually end a call. This route closes the RECORD-KEEPING
  // half of that gap (call_log.ended_at becomes real, so a call's real
  // duration is honestly knowable) — it deliberately does NOT close the
  // MEDIA-REVOCATION half. revokeLiveAccess()/endSession() operate on a
  // RoomLifecyclePort (createRoom/removeParticipant/deleteRoom) shaped
  // around LiveKit's own server-side admin API; a repo-wide check found no
  // real implementation of that port exists for the self-hosted Jitsi stack
  // this app actually runs on today — only a mock, in live.test.mjs. Wiring
  // real server-side Jitsi media revocation needs a genuine Jicofo-backed
  // adapter, a separately-scoped piece of work, not invented or faked here.
  // ===========================================================================
  api.register({
    method: 'POST', path: '/v1/children/:childId/calls/:sessionId/end',
    // Same reasoning as the call-start route above: 'call' is already a
    // real, recognized Action, so the ordinary generic gate applies rather
    // than a new action:null contract.test.mjs exception. A child principal
    // ending a call she was a real party to is legitimate (unlike starting
    // one) — the generic gate's own P6/P7-only child restriction already
    // permits this; no extra child_cannot_end_call check is added here.
    action: 'call',
    handler: async (c) => {
      const ended = await recordCallEnd(pool, c.childId, c.params.sessionId);
      // Idempotent by design (recordCallEnd()'s own doc comment): both
      // parties hanging up simultaneously, or a client retry, produces two
      // calls to this route for one session — the second is a real, honest
      // 200 with ended:false, never an error.
      return { status: 200, body: { ended } };
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

  // -----------------------------------------------------------------------
  // §11 push registration. MASTERFILE §7's own action model treats these as
  // identity-only (action: null) exactly like GET /v1/me above -- a device
  // token belongs to the CALLING principal (child or guardian; see 0008's
  // own header for why both), never to a :childId in the path, so there is
  // no child-scope action to declare and A1/A3 (api.ts) don't apply here.
  //
  // registerDeviceToken()/unregisterDeviceToken() (packages/db/src/pool.mjs)
  // open their OWN session scoped to c.principal, same pattern
  // activeCustodyOrderFor() above already uses alongside this handler's own
  // `q` -- RLS's device_token_insert_own/_update_own/_delete_own policies
  // (0008) are what actually confine a write to the caller's own rows, not
  // application logic here.
  api.register({
    method: 'POST', path: '/v1/me/device-tokens', action: null,
    handler: async (c) => {
      const platform = c.body?.platform;
      const token = c.body?.token;
      // §8.11.4 (v0.49.11) — optional. Omitted entirely (undefined, not a
      // bogus value) means "this client doesn't know its real channel yet"
      // and stays that way -- registerDeviceToken()/0015 store NULL, never
      // a guessed default, for exactly that case. Only a PRESENT-but-invalid
      // value is rejected below; omission is not an error.
      const channel = c.body?.channel;
      if (!DEVICE_PLATFORMS.has(platform)) {
        return { status: 400, body: { error: 'platform_must_be_android_or_ios' } };
      }
      if (typeof token !== 'string' || token.length === 0) {
        return { status: 400, body: { error: 'token_required' } };
      }
      if (channel !== undefined && channel !== null && !DEVICE_CHANNELS.has(channel)) {
        return { status: 400, body: { error: 'channel_not_recognized' } };
      }
      try {
        const id = await registerDeviceToken(pool, c.principal, platform, token, channel ?? null);
        return { status: 200, body: { id } };
      } catch (e) {
        // SEC-01 fix — pool.ts's registerDeviceToken() refuses to mint new
        // push capacity for an already-deactivated guardian/coordinator, same
        // status/body shape as server/index.mjs's devLogin gate for the same
        // error, so a client that already handles that response handles this one.
        if (e?.code === 'account_deactivated') {
          return { status: 403, body: { error: 'account_deactivated' } };
        }
        throw e; // -> Api.handle's catch-all -> 500, logged there
      }
    },
  });

  api.register({
    method: 'DELETE', path: '/v1/me/device-tokens', action: null,
    handler: async (c) => {
      const token = c.body?.token;
      if (typeof token !== 'string' || token.length === 0) {
        return { status: 400, body: { error: 'token_required' } };
      }
      const deleted = await unregisterDeviceToken(pool, c.principal, token);
      return { status: 200, body: { deleted } };
    },
  });

  api.register({
    // db/migrations/0007_custody_order.sql, packages/db/src/pool.mjs's
    // activeCustodyOrderFor(), packages/custody/src/schedule.ts's `Order`.
    // MASTERFILE names no bespoke "family agreement" data model anywhere —
    // this route is deliberately just a read-only view of the real custody
    // order, not an invented document type. Same closest-existing-action
    // reasoning as /now above: no dedicated Action exists for "read the
    // custody order" either, and calendar.view is the same schedule-adjacent
    // fit for the same undocumented reason.
    method: 'GET', path: '/v1/children/:childId/custody-order', action: 'calendar.view',
    handler: async (c, q) => {
      // Which order is "active" is answered on a REAL date, resolved the
      // same way /now resolves hers (child_tz_interval, falling back to
      // child.home_tz) -- duplicated here rather than shared, because unlike
      // sleepsUntilSideChange's day-boundary maths, a custody_order's
      // effective_from/effective_to window is normally months or years wide,
      // so this route tolerates the small duplication rather than risk
      // changing /now's own already-relied-upon behaviour for an edge case
      // that essentially never matters here.
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
      const nowLocalDate = nowUtc.setZone(tz).toISODate();
      const order = await activeCustodyOrderFor(pool, c.childId, nowLocalDate);
      // Honest absence, not a 404 and not a fabricated schedule: a child who
      // is a real child but has no custody_order row yet gets { order: null
      // }. The exact shape activeCustodyOrderFor() returns (pattern, orderTz,
      // anchorLocalDate, exchangeTime, holidays, effectiveFrom, effectiveTo)
      // is passed straight through -- see that function's own header for why
      // that shape is what it is.
      return { body: { order } };
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
      try {
        await setPinCredential(pool, c.principal.userId, hash);
        return { body: { ok: true } };
      } catch (e) {
        // SEC-01 follow-up — pool.ts's setPinCredential() refuses a
        // deactivated guardian, same status/body shape as devLogin's own gate.
        if (e?.code === 'account_deactivated') {
          return { status: 403, body: { error: 'account_deactivated' } };
        }
        throw e; // -> Api.handle's catch-all -> 500, logged there
      }
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

      try {
        await storeWebauthnCredential(pool, c.principal.userId, credentialId, publicKeyPem);
        return { body: { ok: true } };
      } catch (e) {
        // SEC-01 follow-up — pool.ts's storeWebauthnCredential() refuses a
        // deactivated guardian, same status/body shape as devLogin's own gate.
        if (e?.code === 'account_deactivated') {
          return { status: 403, body: { error: 'account_deactivated' } };
        }
        throw e; // -> Api.handle's catch-all -> 500, logged there
      }
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

  // MASTERFILE §8.1, docs/superpowers/specs/2026-08-21-intuitivism-visual-
  // foundation-design.md — the theme customization suite's real backend.
  // `action: 'settings'` reuses the Action already declared for exactly this
  // ("a guardian configures something for this child") in family-graph/src/
  // authorize.ts's ROLE_CAPS — real, but never wired to any route until now
  // (see api_client.dart's own pre-existing, unused `settings` path
  // constant's header for the DIFFERENT, escalation-gated future use of that
  // same Action string this is NOT). Neither route sets `escalated: true`:
  // reached from guardian_more.dart's normal, already-authenticated guardian
  // navigation, not §8.3's PIN+biometric escalation flow.
  api.register({
    method: 'GET', path: '/v1/children/:childId/theme', action: 'settings',
    handler: async (c) => {
      const theme = await themeFor(pool, c.childId);
      return { body: { theme } };
    },
  });

  api.register({
    // `action: 'settings'` is in authorize.ts's WRITES list, so an
    // observer-only guardian's edge is denied here (§17.3) the same way
    // every other write already is — deliberate, not incidental: see
    // 0017_child_theme_preference.sql's own policy comment for why this
    // table's RLS stays coarser (any 'guardian'-role session with a live
    // edge) while THIS app-layer check is the finer-grained gate.
    method: 'PUT', path: '/v1/children/:childId/theme', action: 'settings',
    handler: async (c) => {
      if (c.principal.roleName !== 'guardian' || !c.principal.userId) {
        return { status: 403, body: { error: 'guardian_only' } };
      }
      const reason = invalidThemeBody(c.body);
      if (reason) return { status: 400, body: { error: reason } };
      await setChildTheme(pool, c.principal.userId, c.childId, {
        themePalette: c.body.themePalette, themeBrightness: c.body.themeBrightness,
      });
      return { status: 200, body: { ok: true } };
    },
  });

  // §9.1 / §20.2b — homework capture: real image-quality gate, real OCR, a
  // real (rule-based, non-LLM — see packages/homework/src/hints.ts's own
  // header) hint generator, all run through the existing guardHint(). No DB
  // row is written here: this route is deliberately scoped to closing the
  // "OCR: Homework capture specified, not built" gap the MASTERFILE §20.2b
  // table named. Persisting recognized problems for later retrieval (the
  // broader §7.5 GET /v1/homework/:id, POST .../annotations surface) is a
  // real, separate follow-up, not silently folded in here.
  api.register({
    method: 'POST', path: '/v1/children/:childId/homework/capture',
    // homework.annotate, not homework.view: capture PRODUCES new homework
    // content (recognized problems + hints), so it belongs with the other
    // WRITES actions in authorize.ts — an observer-only guardian correctly
    // gets P17.3's observer_readonly denial the same way homework.annotate
    // already denies any other write, rather than this route inventing its
    // own separate rule. A child capturing her OWN homework is unaffected —
    // api.ts's child branch only checks P6/P7, not ROLE_CAPS/edges.
    action: 'homework.annotate',
    // No Postgres access at all in this handler (see capture-route.ts) — see
    // Route.skipOuterSession's own doc comment in api.ts for why holding a
    // pooled connection open for a multi-second tesseract.js recognize()
    // call would be a real cost for no benefit. A1 (action declared above)
    // and A3 (childId came from the path, matched against the caller before
    // this handler ever runs) are both still enforced by api.ts regardless.
    skipOuterSession: true,
    handler: async (c) => {
      const imageB64 = c.body?.image;
      if (typeof imageB64 !== 'string' || imageB64.length === 0) {
        return { status: 400, body: { error: 'image_required' } };
      }
      let bytes;
      try {
        bytes = Buffer.from(imageB64, 'base64');
      } catch {
        return { status: 400, body: { error: 'bad_image' } };
      }
      // Note: server/index.mjs's own raw-request-body cap (2,000,000 chars,
      // shared by every route, not something this one route should quietly
      // change on its own) limits a base64-encoded photo to roughly 1.5MB of
      // real image bytes — a real constraint for a high-resolution phone
      // photo, flagged here rather than silently hit.
      if (bytes.length === 0) return { status: 400, body: { error: 'bad_image' } };
      let result;
      try {
        result = await runHomeworkCapture(bytes);
      } catch (e) {
        // decodeImage() (measure.ts) throws on anything that isn't a real
        // PNG/JPEG — an honest 400, not a 500 masquerading as a server bug.
        return { status: 400, body: { error: 'unsupported_image_format' } };
      }
      if (!result.ok) {
        // The verdict's own reason/advice, unchanged — this route invents
        // no wording of its own for a quality-gate refusal (capture.ts's
        // own header: advice is written for a child holding a tablet).
        return { status: 422, body: { ok: false, reason: result.reason, advice: result.advice } };
      }
      return { status: 200, body: result };
    },
  });

  api.register({
    // MASTERFILE §7.9 documents this exact shape: `GET .../export  full
    // portable bundle`. GET, not POST, both to match that spec and because it
    // is the only verb client/lib/api_client.dart's OliveApi has a helper for
    // today -- adding this route is what backs deletion_screen.dart's
    // previously snackbar-only "Download raw export" button (§2.11, §16.1
    // #3: free, unlimited, every tier). `export.raw` already existed in
    // family-graph/src/authorize.ts's Action union with nothing behind it.
    //
    // Certified export (§16.1 #3) is served from THIS SAME registration,
    // dispatched on `?kind=certified`, rather than a second api.register()
    // call for the identical method+path -- api.ts's register() has no
    // duplicate-route guard (it just pushes onto an array and match() takes
    // the first hit), so a second registration here would be silently
    // unreachable dead code behind this one, not an error.
    //
    // `action: null, identityScopedByHandler: true` -- same escape hatch
    // kiosk-pin/verify uses (api.ts's own comment on that field), for a
    // different reason: no single coarse action string can correctly gate
    // BOTH kinds this route now serves. `export.raw` and `export.certified`
    // are DIFFERENT ROLE_CAPS entries (authorize.ts) -- guardian holds both,
    // but coordinator holds ONLY 'export.certified', not 'export.raw'. An
    // earlier version of this route registered under `export.raw` on the
    // (wrong) assumption that it covered both roles for both kinds; it did
    // not, and silently 403'd every coordinator's certified-export request
    // with role_lacks_capability before the handler -- and therefore
    // certifiedExportBundleFor()'s own correct, permissive check below --
    // ever ran. (`export.certified` alone isn't usable as the coarse action
    // either, for the OTHER half of the same problem: can()'s
    // 'export.certified' branch hard-requires tier.court with no awareness
    // of the annual free allowance, so it would 403 every non-court-tier
    // guardian's legitimately-free first export before the handler could
    // apply the real allowance rule.) Since neither single action string is
    // correct for both kinds, this route owns its authorization entirely:
    // the child-role block below applies to both, and each kind's REAL,
    // independent check runs inside the pool function that serves it --
    // rawExportBundleFor()'s own live-guardianship query (deliberately
    // guardian-only, unchanged), and certifiedExportBundleFor()'s own
    // edgesFor()+can('export.certified', ...) call, which now actually
    // reaches a coordinator caller instead of being unreachable behind a
    // coarse gate that already denied them.
    method: 'GET', path: '/v1/children/:childId/export', action: null,
    identityScopedByHandler: true,
    handler: async (c, _q) => {
      // packages/db/src/pool.mjs's rawExportBundleFor()/certifiedExportBundleFor()
      // each run their OWN withSession/withSystemSession, independent of the
      // caller-scoped `q` this handler was already given -- the same "runs
      // its own session, separate from the request's" shape /now's handler
      // above uses for activeCustodyOrderFor(), for the same reason: the
      // pool functions need to be callable (and independently unit-
      // testable) without going through this route at all.
      if (c.principal.roleName === 'child') {
        // §21.2 rung 17 ("her own export") is real in
        // packages/maturation/src/rungs.ts's authorizeExport() but has no
        // age gate wired to THIS route, and export_record.requested_by
        // alone could not honestly name a child caller (see
        // rawExportBundleFor's own header for the full reasoning) --
        // applies to both kinds this route serves, neither of which has a
        // standalone, ad-hoc child-caller path wired HERE. A clear 501, not
        // a silent empty bundle or a fabricated ledger row.
        //
        // NO LONGER THE WHOLE STORY, as of this pass: a child's own export
        // IS real now, at majority, bundled with the guardianship closure
        // §9.8.4 requires alongside it -- POST /v1/children/:childId/
        // handover, below (§7.9's own long-named-but-unbuilt route), backed
        // by packages/db/src/pool.mjs's takeAndGo() and
        // 0016_child_take_and_go.sql's requested_by_child_id.
        // Deliberately a SEPARATE route rather than a child branch bolted
        // on here: an ad-hoc pull through THIS route would need to either
        // fabricate a majority check this route has no reason to run on
        // every call, or hand back a bundle with no export_record row at
        // all (silently dropping the audit trail every other export gets)
        // -- neither is honest. See takeAndGo()'s own header for the full
        // reasoning on why export and closure are one atomic action for her,
        // unlike the guardian's independently-optional two-button UX.
        return { status: 501, body: { error: 'child_self_export_not_implemented' } };
      }
      const kind = c.query.get('kind');
      if (kind === 'certified') {
        const result = await certifiedExportBundleFor(pool, c.principal.userId, c.childId);
        if (!result.ok) {
          return { status: 403, body: {
            error: result.reason,
            message: EXPORT_DENIAL_MESSAGES[result.reason] ?? result.reason,
            ...(result.faults ? { faults: result.faults } : {}),
          } };
        }
        return { status: 200, body: {
          kind: 'certified',
          free: result.free,
          chain: result.chain,
          attestation: result.attestation,
          bundleHash: result.bundleHash,
          exportRecordId: result.exportRecordId,
        } };
      }
      // Default: kind unspecified, or kind=raw explicitly -- the original,
      // already-shipped behavior, unchanged. Not an allowlist-and-400 on an
      // unrecognized kind: the pre-existing client contract (fetchRawExport)
      // never sends `kind` at all, and this route's own MASTERFILE spec
      // predates the `kind` param entirely -- silently defaulting to the
      // long-standing free/unlimited raw export is the honest choice here,
      // not a behavior change for every caller that isn't asking for
      // certified specifically.
      const result = await rawExportBundleFor(pool, c.principal, c.childId);
      if (!result.ok) return { status: 403, body: { error: result.reason } };
      return { body: {
        bundle: result.bundle,
        // The EXACT string bundleHash was computed over -- client/lib/
        // deletion_screen.dart hashes and persists THIS field, not a
        // client-side re-serialization of `bundle`, so "the hash on this
        // file verifies" is never a false negative caused by a JSON
        // encoder disagreeing with Node on key order or number formatting.
        bundleJson: result.serialized,
        exportRecordId: result.recordId,
        bundleHash: result.bundleHash,
      } };
    },
  });

  api.register({
    // MASTERFILE §2.10, §2.11, §9.8/§9.8.4, §7.9, §21.2 rung 17, §21.6/§21.7
    // -- the child's OWN export + majority closure, real for the first time.
    // The path itself is not new here -- `POST /v1/children/:id/handover`
    // ("majority transfer. Irreversible. §9.8.4") has been named in §7.9's
    // own API surface listing since before this pass; this registration is
    // its first real implementation, not a new path invented for it. (The
    // product-facing NAME, "take and go" -- §21.6's own row title -- is what
    // client/lib/take_and_go_screen.dart and packages/db/src/pool.mjs's
    // takeAndGo() are named after; the route itself keeps §7.9's spec name.)
    //
    // A genuine mirror of POST /v1/me/delete above: same "identity, not an
    // edge" shape as kiosk-pin/verify (a child holds no guardianship edge to
    // HERSELF, so `can()` was never the right tool here either) --
    // `action: null, identityScopedByHandler: true`, same as kiosk-pin/
    // verify and GET .../export -- and `skipOuterSession: true`, because
    // takeAndGo() (packages/db/src/pool.mjs) opens its OWN two sessions (a
    // real child-role session to read her journal, a system-role session
    // for the actual, atomic mutation -- see that function's own header for
    // why neither the outer session api.handle() would open by default, nor
    // a single session, is the right shape here).
    method: 'POST', path: '/v1/children/:childId/handover', action: null,
    identityScopedByHandler: true, skipOuterSession: true,
    handler: async (c) => {
      if (c.principal.roleName !== 'child' || c.principal.childId !== c.childId) {
        return { status: 403, body: { error: 'not_this_child' } };
      }
      try {
        const result = await takeAndGo(pool, c.childId);
        if (!result.ok) {
          // not_yet_of_age / already_handed_over / child_deceased -- a real,
          // ordinary business-rule denial (packages/archive/src/archive.ts's
          // own handover(), reused, not reimplemented), same 403 shape
          // rawExportBundleFor()/certifiedExportBundleFor() already use for
          // their own {ok:false, reason} denials just above in this file.
          return { status: 403, body: { error: result.reason } };
        }
        return { status: 200, body: { ok: true, ...result.result } };
      } catch (e) {
        // child_not_found -- genuinely should never happen for a session
        // readSession() already verified names a real child row (the same
        // "should be unreachable, asserted anyway" posture deactivateAccount()
        // takes on its own account_not_found).
        if (e?.code === 'child_not_found') {
          return { status: 404, body: { error: 'child_not_found' } };
        }
        throw e; // -> Api.handle's catch-all -> 500, logged there
      }
    },
  });

  api.register({
    // POST counterpart to GET .../inbox — records an async video message and
    // schedules it, the real backend for client/lib/receipt_screen.dart's
    // "Send one back" (see that file's header). `packages/messaging/src/
    // pipeline.ts`'s captureMessage() is the pure, already-tested decision
    // function; this handler's only jobs are (1) load the DB-shaped inputs it
    // needs, (2) run it, and (3) on `ok: true`, hand the result to
    // packages/db/src/pool.ts's persistCapturedMessage() — never insert a row
    // captureMessage() has not first validated.
    method: 'POST', path: '/v1/children/:childId/messages', action: 'message',
    handler: async (c, q) => {
      const body = c.body ?? {};
      const storageKey = typeof body.storageKey === 'string' && body.storageKey
        ? body.storageKey : null;
      const durationMs = typeof body.durationMs === 'number' ? body.durationMs : null;
      if (!storageKey || durationMs === null) {
        return { status: 400, body: { error: 'storage_key_and_duration_ms_required' } };
      }
      const captionKey = typeof body.captionKey === 'string' ? body.captionKey : undefined;
      const targetLocalDate = typeof body.targetLocalDate === 'string'
        ? body.targetLocalDate : null;
      const daypart = typeof body.daypart === 'string' ? body.daypart : 'bedtime';
      const preserve = body.preserve === true;
      const batchId = typeof body.batchId === 'string' ? body.batchId : undefined;
      const batchSeq = typeof body.batchSeq === 'number' ? body.batchSeq : undefined;

      // Sender identity is ALWAYS the authenticated principal, never the
      // body (A3's own reasoning in api.ts, extended to identity generally —
      // a body-supplied senderId would let anyone forge a message as coming
      // from any guardian). A `child` principal carries no `userId`
      // (packages/auth/src/auth.ts's VerifiedPrincipal, server/index.mjs's
      // dev-login), so `edges` below is honestly `[]` for a child caller.
      //
      // HONEST GAP this route surfaces rather than hides: `delivery_intent.
      // sender_id` is `NOT NULL REFERENCES app_user(id)`, and a child has no
      // `app_user` row — this schema has no representation for a child AS a
      // sender at all. So a `child` session hitting this route (the
      // realistic caller for "Send one back") always reaches
      // captureMessage() with empty edges and gets `not_authorized` back —
      // the exact same denial a sitter or coordinator would get (see
      // pipeline.test.mjs's M2 suite) — a real, honoured rejection, not a
      // silently faked success. Wiring a child as a genuine sender would need
      // a schema change this task did not ask for; see receipt_screen.dart's
      // header and this pass's final report for the same note.
      const senderId = c.principal.userId;
      const senderRole = c.principal.roleName;
      const edges = senderId ? await edgesFor(pool, senderId) : [];

      const ctx = await childCtxFor(pool, c.childId);
      if (!ctx) return { status: 404, body: { error: 'child_not_found' } };

      const result = captureMessage(
        {
          childId: c.childId,
          // captureMessage() never reads senderId on a denial path (it checks
          // `can()` first and returns before touching the value) — see
          // pipeline.ts. The '' fallback only ever reaches that dead branch.
          senderId: senderId ?? '',
          senderRole,
          storageKey,
          durationMs,
          captionKey,
          targetLocalDate,
          daypart,
          preserve,
          batchId,
          batchSeq,
        },
        edges, ctx, DateTime.utc(),
      );
      if (!result.ok) {
        return { status: result.reason === 'not_authorized' ? 403 : 400,
                 body: { error: result.reason } };
      }

      const persisted = await persistCapturedMessage(pool, result);
      return { status: 201, body: {
        id: persisted.intentId, artifactId: persisted.artifactId, state: 'pending' } };
    },
  });
}
