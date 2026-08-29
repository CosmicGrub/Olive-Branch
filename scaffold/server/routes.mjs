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
import { createHash, timingSafeEqual, randomUUID, randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { DateTime } from 'luxon';
import { activeCustodyOrderFor, guardiansOfChild, parentGuardiansOfChild, setPinCredential,
         attemptPinFor, createChallenge, consumeChallenge,
         storeWebauthnCredential, availabilityFor,
         setAvailabilityWindows, deactivateAccount,
         rawExportBundleFor, edgesFor, childCtxFor,
         persistCapturedMessage, mediaArtifactFor, registerDeviceToken,
         unregisterDeviceToken,
         certifiedExportBundleFor,
         createGuardianInvite, getGuardianInvite,
         acceptGuardianInvite, revokeGuardianInvite, bootstrapGuardianInvite,
         takeAndGo, themeFor, setChildTheme,
         recordCallStart, recordCallEnd,
         appendHandoverNote, handoverNotesFor,
         expensesFor, proposeExpense, resolveExpense,
         medicationsFor, dosesForDate, recordDose, medicalRecordFor, setMedicalRecord,
         bagItemsFor, setBagItemStatus, runningLateLogFor, logRunningLate,
         arrivalEventFor, recordExchangeArrival,
         careNotesFor, writeCareNoteRow,
         lettersFor, sealLetterRow, openLetterRow, deleteLetterRow,
         INVITABLE_ROLES } from '../packages/db/src/pool.mjs';
import { sleepsUntilSideChange, sideOn, freeGuardianNow } from '../packages/custody/src/schedule.mjs';
import { runHomeworkCapture } from '../packages/homework/src/capture-route.mjs';
import { hashPin } from '../packages/auth/src/auth.mjs';
import { parseAttestationObject, extractCredentialPublicKey } from '../packages/auth/src/attestation.mjs';
import { captureMessage } from '../packages/messaging/src/pipeline.mjs';
import { CHANNELS } from '../packages/devices/src/devices.mjs';
import { createSession, mintToken } from '../packages/session-runtime/src/rooms.mjs';
import { notifyDevices } from '../packages/transport/src/notify.mjs';
import { FilesystemStorage } from '../packages/storage/src/storage.mjs';

/**
 * MASTERFILE §20.2b's own gap, closed here: "`StoragePort` has no
 * production implementation anywhere in this codebase (MemoryStorage is
 * test-only)." `FilesystemStorage` (packages/storage/src/storage.ts) was
 * real and real-tested (packages/storage/test/storage.test.mjs) before this
 * pass — nothing wired it to an HTTP path or gave it a persistent root to
 * write under. `MEDIA_STORAGE_ROOT` is that root: a real, self-hosted-
 * deployment volume, not a cloud account (see storage.ts's own header on
 * why a cloud provider is explicitly out of scope). Defaults to
 * `scaffold/data/media` — resolved from THIS file's own location, not
 * `process.cwd()`, so it lands in the same place regardless of the
 * directory `node server/index.mjs` happens to be launched from. Gitignored
 * (see repo-root .gitignore's own entry) — real family media has no
 * business in source control, even accidentally.
 */
const DEFAULT_MEDIA_STORAGE_ROOT =
  join(dirname(fileURLToPath(import.meta.url)), '..', 'data', 'media');
// Exported (not just module-private) so server/index.mjs's own raw
// GET /media/:key signed-URL route (outside api.ts's session-based JSON
// dispatch entirely — a signed URL carries no session) can verify and read
// against the EXACT SAME instance registerRoutes() wires POST/GET
// .../media into, rather than a second, independently-constructed
// FilesystemStorage that would hold its own independent secret and could
// never verify a URL the first instance minted.
//
// Real bug, found by this project's own post-tier audit: FilesystemStorage's
// own signing secret used to default to a fresh randomBytes(32) EVERY
// process start, with nothing anywhere reading a configured value — fine
// within one running process (mint and verify always agree with each other
// here), but every real server restart (a routine `restart: always`
// recovery, an OOM kill under docker-compose.prod.yml's 512m limit, a
// rolling redeploy) silently invalidated every outstanding signed URL still
// inside its 5-minute TTL, and structurally forbids ever scaling `server`
// past one replica (two processes would each mint a different secret and
// neither could verify the other's URLs). MEDIA_SIGNING_SECRET, hex-encoded
// (same `openssl rand -hex 32` convention SESSION_SECRET already uses),
// makes the secret survive a restart and be shared across replicas when
// set; falling back to a fresh random secret when unset keeps a bare local
// dev run working exactly as before, at the same "URLs won't survive a
// restart" cost that already existed for every deployment before this fix.
const mediaSigningSecret = process.env.MEDIA_SIGNING_SECRET
  ? Buffer.from(process.env.MEDIA_SIGNING_SECRET, 'hex')
  : randomBytes(32);
export const defaultMediaStorage = new FilesystemStorage(
  process.env.MEDIA_STORAGE_ROOT ?? DEFAULT_MEDIA_STORAGE_ROOT, mediaSigningSecret);

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

/**
 * The real "her frame" relative label GET .../inbox's real caller needs —
 * client/lib/inbox_screen.dart's own InboxMessage.deliveredAtLabel doc
 * comment specifies this exact shape ("7:04 AM" today, "Yesterday, 7:58 PM",
 * "2 days ago, 6:10 PM" — relative wording only, never a calendar date,
 * §8.2.5's "sleeps, not dates" rule). Computed server-side, matching /now's
 * own established pattern of doing zone math once here and handing the
 * client an already-formatted string — no timezone-conversion package
 * exists in client/pubspec.yaml, and this codebase's own precedent (every
 * *_route.mjs handler that touches a child's local time) is that this kind
 * of conversion belongs on this side of the wire, not the client's.
 */
function relativeInboxLabel(materializedAtIso, tz, nowUtc) {
  const at = DateTime.fromISO(materializedAtIso, { zone: 'utc' }).setZone(tz);
  const now = nowUtc.setZone(tz);
  const timeLabel = at.toFormat('h:mm a');
  if (!at.isValid || !now.isValid) return timeLabel;
  const daysAgo = Math.round(now.startOf('day').diff(at.startOf('day'), 'days').days);
  if (daysAgo <= 0) return timeLabel;
  if (daysAgo === 1) return `Yesterday, ${timeLabel}`;
  return `${daysAgo} days ago, ${timeLabel}`;
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
 * @param {import('../packages/storage/src/storage.ts').StoragePort} [storage]
 *   Injectable so a test can point real disk I/O at a throwaway temp
 *   directory (mirrors storage.test.mjs's own `fs.mkdtemp` pattern) instead
 *   of this module's real, persistent `MEDIA_STORAGE_ROOT`. Every real call
 *   site (server/index.mjs) leaves this at its default.
 */
export function registerRoutes(api, pool, storage = defaultMediaStorage) {
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

  // The account-creation gap CHANGELOG v0.49.9 found and explicitly declined
  // to invent an answer for: guardian_setup.dart's passkey registration has
  // ALWAYS required an already-authenticated guardian session, and nowhere
  // did a brand-new guardian ever acquire one. This route closes exactly
  // that and nothing more — it does NOT touch WebAuthn registration itself
  // (POST .../webauthn/register/challenge and .../verify above are
  // completely unchanged) and does NOT create a guardianship row (see
  // 0014/0020_guardian_invite_bootstrap.sql's own headers for why that
  // stays a real, separate, still-open gap).
  //
  // noSessionRequired, same reason as GET/accept above: the caller has no
  // app_user row yet, so there is nothing for them to hold a session token
  // TO. Unlike GET/accept, this route requires the invite to have ALREADY
  // been accepted (bootstrapGuardianInvite() checks accepted_at, not just
  // existence) — the invite's own unguessable id, ONE STEP FURTHER along
  // this same flow, is what stands in for a credential here.
  api.register({
    method: 'POST', path: '/v1/guardian-invites/:inviteId/bootstrap', action: null,
    skipOuterSession: true, noSessionRequired: true,
    handler: async (c) => {
      const displayName = c.body?.displayName;
      if (typeof displayName !== 'string' || !displayName.trim()) {
        return { status: 400, body: { error: 'display_name_required' } };
      }
      const result = await bootstrapGuardianInvite(
        pool, c.params.inviteId, displayName.trim(), new Date());
      if (!result.ok) {
        const status = result.reason === 'not_found' ? 404
          : result.reason === 'expired' ? 410 : 409;
        return { status, body: { error: result.reason } };
      }
      // Mints exactly what guardian_setup.dart's real passkey registration
      // needs and nothing else: an ordinary guardian session with NO
      // guardianship edge to any child (none was created — see above), so
      // every OTHER route that checks edgesFor() still refuses this
      // session exactly as it would refuse any guardian with zero edges.
      const token = api.issueSessionToken(
        { userId: result.userId, roleName: 'guardian', childId: null, escalated: false });
      return { status: 201, body: { ok: true, token, userId: result.userId, childId: result.childId } };
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

      // The caller's REAL observer-tier flag for THIS child — the sibling of
      // realLadderStep two lines up, and the same hardcode bug: this route
      // minted `observerOnly: false` unconditionally instead of reading the
      // real per-edge value already sitting in `edges`, found by a live
      // audit (2026-08-24) that ladderStep's own fix (v0.49.35) fixed six
      // lines away but missed here. rooms.ts's deriveGrant() computes
      // `canPublish: !principal.observerOnly` from exactly this field — §17.3
      // /I4 require an observer-only guardian to get `canPublish: false`
      // ("a parent whose camera and microphone are live in the room IS
      // participating"), and the old `false` constant made that impossible
      // to compute correctly for any caller. `?? true` is deliberately NOT
      // realLadderStep's `?? 'open'` pattern: that default is a documented
      // business rule for a genuinely absent contact_ladder row, sourced
      // from authorize.ts's own convention. There is no equivalent "no edge
      // means full publish" rule anywhere in this codebase, and the outer
      // gate having already run can('call', ...) means this .find() should
      // never actually miss — so if it somehow does, §5.18's fail-closed
      // convention (pool.ts:75) applies: default to the MORE restrictive
      // reading (observer-only, no publish), never the less restrictive one.
      const realObserverOnly = edges.find((e) => e.childId === c.childId)?.observerOnly ?? true;

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
        { userId: c.principal.userId, observerOnly: realObserverOnly, isChild: false, roleName: c.principal.roleName },
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
    // GET /v1/children/:childId/presence — "who is free to be called right
    // now" on ChildHome. Design spec's §0: the brief this route was
    // originally scoped from assumed a Side→guardian mapping already
    // existed; it did not (no table anywhere mapped schedule.ts's abstract
    // 'A'|'B' to a real app_user.id) until
    // db/migrations/0024_custody_order_side_guardians.sql, added alongside
    // this route specifically to make the exclusion below possible. Same
    // closest-existing-action reasoning as /now and /custody-order above:
    // no dedicated Action exists for this either, and calendar.view is the
    // same schedule/status-adjacent fit for the same undocumented gap.
    method: 'GET', path: '/v1/children/:childId/presence', action: 'calendar.view',
    handler: async (c, q) => {
      // Real bug, found by this project's own post-tier audit: calendar.view
      // alone is far wider than this route was ever meant to admit — it is
      // also held by sitter/coordinator/caseworker/trusted_adult, none of
      // whom this feature's own design intended as callers (ChildHome, and
      // by extension the child herself, is the sole real consumer this was
      // built for). A live, NAMED-PARENT reachability signal ("Dad is free
      // right now, until 4:15 PM") is materially more sensitive than the
      // static schedule/pattern data calendar.view otherwise gates — this
      // narrows the caller to exactly the child herself, or a real
      // parent-role guardian (the SAME role parentGuardiansOfChild() below
      // already restricts the response's own candidate list to, per §5.27.2
      // "only a parent... not a stepparent, a caregiver... or a
      // coordinator" — that principle previously governed who could be
      // SHOWN, not who could ASK).
      // Fetched once, reused below for both this gate and Step 2's own
      // candidate list — the same 'guardian'-role query, not two.
      const parents = await parentGuardiansOfChild(pool, c.childId);
      const isChildSelf = c.principal.roleName === 'child' && c.principal.childId === c.childId;
      if (!isChildSelf
        && !(c.principal.userId && parents.some(g => g.userId === c.principal.userId))) {
        return { status: 403, body: { error: 'not_a_parent_of_child' } };
      }

      // Same tz-resolution block as /now and /custody-order, duplicated a
      // third time rather than shared — matching those two routes' own
      // explicit "small duplication, not worth a shared helper here"
      // comments.
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
      const nowLocalDate = local.toISODate();
      // 24h, comparison-only — HH:mm sorts/compares identically to
      // chronological order, the same technique freeGuardianNow()'s own
      // sort already relies on (schedule.ts).
      const nowLocalHHMM = local.toFormat('HH:mm');
      // Sun=0..Sat=6, matching packages/delivery-engine/src/materialize.ts's
      // own convention and 0010_availability.sql's weekday column — NOT
      // Luxon's native 1=Monday..7=Sunday ISO weekday.
      const nowWeekday = local.weekday % 7;

      // Step 1 — who is on duty, honestly (design spec §0/§3). A NULL side-
      // guardian column (legacy row, or simply no order at all) means the
      // on-duty exclusion is SKIPPED, not guessed: every live co-guardian
      // stays a candidate, matching activeCustodyOrderFor()'s own "honest
      // null, never a guess" discipline.
      const order = await activeCustodyOrderFor(pool, c.childId, nowLocalDate);
      let onDutyGuardianId = null;
      if (order) {
        const side = sideOn(order, nowLocalDate).side;
        onDutyGuardianId = side === 'A'
          ? (order.sideAGuardianId ?? null)
          : (order.sideBGuardianId ?? null);
      }

      // Step 2 — candidates: PARENTS only (§5.27.2), on-duty guardian
      // excluded. An only-guardian family (or a family where the only other
      // guardian happens to be on duty) naturally falls through to
      // `{ free: null }` below via this list being empty — no special case
      // needed, and no distinguishable state that would leak "you only have
      // one parent" through this card (§5.27.3's sibling concern). `parents`
      // is the SAME list already fetched above for the caller gate.
      const candidates = parents.filter(g => g.userId !== onDutyGuardianId);
      if (!candidates.length) return { body: { free: null } };

      // Step 3/4 — active windows now, tie-break via freeGuardianNow()'s own
      // ported prioritise()-style sort (packages/custody/src/schedule.ts).
      const windows = await availabilityFor(pool, c.childId);
      const winner = freeGuardianNow(candidates, windows, nowWeekday, nowLocalHHMM);
      if (!winner) return { body: { free: null } };

      // §1 — theirLocalTime/freeUntilHerTime are BOTH rendered in the
      // child's own resolved zone (the same one /now resolves for her),
      // never a per-guardian zone: this app has no per-guardian timezone
      // (confirmed: no `tz` column on app_user, and custody_order.order_tz
      // is a single order-wide zone documented as "the child's
      // primary-residence zone at entry" — not a location for any specific
      // adult, and actively the wrong proxy for THIS guardian specifically,
      // since by construction (Step 2's on-duty exclusion) she is the one
      // NOT currently at the child's home). Reusing the child's own zone is
      // the least-invented option available, not a claim that it is
      // accurate for a genuinely cross-timezone family.
      const childLocalEndOf = DateTime.fromISO(
        `${nowLocalDate}T${winner.endLocal}`, { zone: tz },
      ).toFormat('h:mm a');

      return { body: { free: {
        guardianId: winner.guardianId,
        name: winner.guardianName,
        theirLocalTime: local.toFormat('h:mm a'),
        freeUntilHerTime: `${childLocalEndOf} her time`,
      } } };
    },
  });

  // The response's top-level key is `entries`, not `messages` — a real,
  // previously undiscovered bug, found only while writing this route's
  // first-ever HTTP-level test (server/test/inbox_route.test.mjs, added
  // alongside db/migrations/0023_message_media_delivery_rls.sql). `messages`
  // is on `packages/globalaudit/src/globalaudit.ts`'s own
  // GLOBAL_CHILD_FORBIDDEN list ("adult plumbing that should never be
  // rendered to her") — banned there for an unrelated reason (some other
  // module's own pressure-framing leak, per that file's own comments), but
  // `Api.handle()`'s global child-payload sweep (wired in v0.49.37) checks
  // every key name in EVERY response served to a `child` principal, with no
  // per-route exemption by default. That meant every real child session
  // hitting her own inbox — the actual, load-bearing call
  // `client/lib/child_home_live.dart`'s home screen makes on every load —
  // 500'd with `child_payload_leak` in real production, silently, since the
  // sweep first shipped. A guardian's own read was never affected (the
  // sweep only inspects responses to a `child` principal), which is exactly
  // why nothing caught this: every existing manual/device check of this
  // route was a guardian request. Renamed rather than exempted via
  // skipChildPayloadSweep — the field ITSELF is not adult plumbing (it is
  // exactly, legitimately hers), only its old NAME collided; renaming keeps
  // the sweep's real protection live for every other field this route ever
  // returns, instead of turning it off for the whole route.
  api.register({
    method: 'GET', path: '/v1/children/:childId/inbox', action: 'message',
    handler: async (c, q) => {
      // to_char(... AT TIME ZONE 'UTC', ...), not a bare ::text cast — the
      // same DateStyle bug this codebase has already found and fixed twice
      // (runRematerializeSweep's own to_char() fix, tools/scheduler.mjs; the
      // reap-media job's identical fix, same file). Was harmless here only
      // because nothing had ever actually parsed materialized_at client-side
      // before — deliveredAtLabel below is this route's first real reader of
      // it, so the cast needed to be right before it became load-bearing.
      const rows = await q(
        `SELECT di.id, di.payload_kind, di.sender_id, di.state,
                to_char(di.materialized_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
                  AS materialized_at,
                u.display_name AS sender_name
           FROM delivery_intent di
           JOIN app_user u ON u.id = di.sender_id
          WHERE di.child_id = $1 AND di.state IN ('delivered','opened')
          ORDER BY di.materialized_at DESC NULLS LAST
          LIMIT 50`,
        [c.childId],
      );

      // Her frame first, always (this route's own receiving screen, receipt_
      // screen.dart's header, quoting pipeline.ts's openReceipt(): "a receipt
      // renders in HER frame... not the capture zone"). Zone resolution
      // duplicated from /now and /custody-order rather than shared — same
      // precedent those two routes already set for each other (custody-
      // order's own comment: "this route tolerates the small duplication
      // rather than risk changing /now's own already-relied-upon behaviour").
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
        tz = child[0]?.home_tz ?? 'UTC';
      }

      const entries = rows.map((r) => ({
        ...r,
        deliveredAtLabel: r.materialized_at
          ? relativeInboxLabel(r.materialized_at, tz, nowUtc) : '',
      }));
      return { body: { entries } };
    },
  });

  // POST /v1/children/:childId/inbox/:id/opened — real bug, found by this
  // project's own post-tier audit: MASTERFILE §7.3 declared this route as
  // part of the API surface ("POST /v1/inbox/:id/opened — receipt, recorded
  // in child-local time") for as long as this document has had an API
  // reference section, but it was never built. inbox_screen.dart's own
  // _open() only ever flipped `watched` in LOCAL widget state
  // (setState(() => _messages[i] = m.markWatched())) — real, but invisible
  // to the server, so nothing persisted past that one screen instance. This
  // stayed harmless while the inbox was demo-only; it stopped being
  // harmless the moment GET .../inbox and receipt_screen.dart's live caller
  // (both this same tier) made the whole path genuinely live — every
  // previously-watched message re-materializes as "New" and the unread
  // badge never actually clears, on every fresh load.
  //
  // Real path shape deviates from MASTERFILE §7.3's own bare
  // /v1/inbox/:id/opened — child-scoped under /v1/children/:childId/..., the
  // same convention every other real child-facing route this codebase has
  // ever actually built uses (A3's own childId-match check needs a childId
  // in the path to check against); MASTERFILE corrected to match, not left
  // silently stale a second time.
  api.register({
    method: 'POST', path: '/v1/children/:childId/inbox/:messageId/opened', action: 'message',
    handler: async (c, q) => {
      // Real authorization, narrower than the outer action check alone:
      // "opened" means SHE watched it — a guardian's own read of the same
      // inbox (action: 'message' admits her too, same as the GET route
      // above) must never be able to mark a receipt watched on the child's
      // behalf. This is deliberately an in-handler check, not a capability
      // list entry — the same pattern already established at this file's
      // other identity-scoped-beyond-action routes.
      if (c.principal.roleName !== 'child' || c.principal.childId !== c.childId) {
        return { status: 403, body: { error: 'child_session_required' } };
      }
      // delivered -> opened only. A row still 'pending'/'ready' has not
      // reached her yet regardless of what the client claims; an already-
      // 'opened' row makes this a safe no-op (real re-opens, offline-queued
      // duplicate calls); 'expired'/'revoked' must never be resurrected into
      // 'opened' by a stale client request racing a server-side sweep.
      const updated = await q(
        `UPDATE delivery_intent SET state = 'opened'
          WHERE id = $1 AND child_id = $2 AND state = 'delivered'
          RETURNING id`,
        [c.params.messageId, c.childId],
      );
      if (updated.length) return { status: 200, body: { ok: true } };
      // Idempotent success for a row already 'opened' — distinguished from
      // a genuine not-found/wrong-state so a client retry (or two tabs
      // racing) never sees a false error for something that already
      // happened.
      const already = await q(
        `SELECT 1 FROM delivery_intent WHERE id = $1 AND child_id = $2 AND state = 'opened'`,
        [c.params.messageId, c.childId],
      );
      if (already.length) return { status: 200, body: { ok: true } };
      return { status: 404, body: { error: 'message_not_found_or_not_yet_delivered' } };
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
          // Real call metadata (0018_call_log.sql, packages/db/src/pool.mjs's
          // certifiedExportBundleFor()) -- included here deliberately, not
          // left for the client to fetch separately: `bundleHash` below is
          // computed over {chain, attestation, callLog} together, so a
          // response that dropped this field on the way out would silently
          // stop matching its own advertised hash. See MASTERFILE §16.1 #3's
          // own v0.49.15 note on the exact class of bug this avoids -- a
          // real field the backend already computed, never wired to the one
          // response that was supposed to carry it.
          callLog: result.callLog,
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
    // §20.5 — her own complete take-and-go bundle real-500'd the moment the
    // global child-payload sweep first shipped: it legitimately includes
    // her own message log (`rungs.ts`'s NOT_HERS_TO_DELETE — "she can have
    // a copy of everything"), which the sweep correctly bans from a curated
    // UI surface but this route is not one. See `Api`'s own
    // `skipChildPayloadSweep` doc comment for the full reasoning.
    skipChildPayloadSweep: true,
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

  // GET/POST /v1/children/:childId/handover-notes — the parent-to-parent
  // handover log, real for the first time. Found by this project's own
  // post-tier audit: message_log (db/migrations/0006_court_tier.sql) has
  // had real RLS, a real append-only trigger, and a real hash-chain
  // enforcement trigger since v0.something-early, and certifiedExport
  // BundleFor() has been able to READ and verify it since v0.14.0 — but
  // nothing anywhere ever WROTE a row. handover_notes.dart's own UI is
  // pure in-memory local state with zero network calls (confirmed by
  // grepping the file for any http/OliveApi/api. reference — none exist).
  // Court export's own "the message log backs a certified export" claim
  // had no real data behind it in production until this pair of routes.
  //
  // Path deliberately NOT /v1/children/:childId/handover — that path is
  // already the real §9.8.4 majority take-and-go route just above, an
  // entirely different feature this codebase happens to also call
  // "handover." No MASTERFILE §7 row currently declares this route at all
  // (a real, disclosed gap in that section's own aspirational sketch, per
  // its own new scoping note) — named to match handover_notes.dart's own
  // client-facing name, not retrofitted to a stale declaration.
  api.register({
    method: 'GET', path: '/v1/children/:childId/handover-notes', action: 'message',
    handler: async (c, q) => {
      // Real bug in this route's own first draft, found by its own first
      // test: handoverNotesFor() reads via a SYSTEM-scoped session
      // (message_log's own log_no_child RLS policy only excludes the
      // 'child' role — 'system' passes it freely), so without this guard a
      // child session reaches the outer action:'message' gate exactly the
      // same way she legitimately does for her OWN inbox (can()'s real
      // behavior for a child principal — see the presence route above),
      // and the system-scoped read behind it would hand her the real
      // parent-to-parent log content regardless. "Not the child's... it's
      // the parents'" (handover_notes.dart's own header) has to be
      // enforced HERE, explicitly — the DB policy alone does not reach a
      // system-role read.
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_the_childs_channel' } };
      }
      const entries = await handoverNotesFor(pool, c.childId);
      // whenLabel: this codebase's own established convention (relativeInboxLabel
      // above, /now's local-time fields) is that ALL timezone-aware display
      // formatting happens HERE, once, server-side -- client/pubspec.yaml has
      // no timezone/intl package at all. Unlike relativeInboxLabel's "sleeps,
      // not dates" wording (§8.2.5, child-facing), this content is strictly
      // guardian-facing (the 403 above enforces that), so there's no reason
      // to avoid a real calendar date -- format matches handover_notes.dart's
      // own pre-existing demo fixture shape ("Jul 28, 4:12 PM") exactly, so
      // wiring this in doesn't change what a guardian who's used the demo
      // already expects to see. Resolved the same way /now resolves hers
      // (child_tz_interval, falling back to child.home_tz) -- duplicated
      // here rather than shared, matching this file's own existing precedent
      // for that block (see the comment at the exchange route above).
      let tz;
      {
        const interval = await q(
          `SELECT tz FROM child_tz_interval
            WHERE child_id = $1 AND valid @> now()
            ORDER BY confidence DESC LIMIT 1`,
          [c.childId],
        );
        tz = interval[0]?.tz;
        if (!tz) {
          const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [c.childId]);
          tz = child[0]?.home_tz ?? 'UTC';
        }
      }
      return { body: { entries: entries.map(e => ({
        seq: e.seq, authorId: e.authorId, authorName: e.authorName, at: e.at, body: e.body,
        whenLabel: DateTime.fromISO(e.at, { zone: 'utc' }).setZone(tz).toFormat('MMM d, h:mm a'),
      })) } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/children/:childId/handover-notes', action: 'message',
    handler: async (c, q) => {
      // Real guard, not just relying on the RLS backstop: message_log's own
      // log_no_child policy (0006_court_tier.sql) would correctly refuse a
      // child-role write at the DB layer too (current_role_name() IS
      // DISTINCT FROM 'child' — FORCE RLS, no owner bypass), but a clear
      // 403 here is a better failure mode than letting a request reach a
      // raw Postgres permission error. A child session passes the outer
      // action:'message' capability check (can()'s own real behavior for a
      // child principal — see this file's own precedent at the presence
      // route above), so this cannot be left to the outer gate alone.
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_the_childs_channel' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const body = typeof c.body?.body === 'string' ? c.body.body.trim() : '';
      if (!body) return { status: 400, body: { error: 'empty_body' } };
      const entry = await appendHandoverNote(
        pool, c.principal.roleName, c.principal.userId, c.childId, body);
      // whenLabel here too, same reasoning as the GET handler just above --
      // a caller that just posted needs a real display label for the entry
      // it immediately renders, and this route is the ONLY place that entry
      // exists yet (a client that instead re-fetched the whole list just to
      // get a label would trade one honest round trip for two, and would
      // flash the loading state across the entries this guardian can
      // already see). Duplicated rather than shared with GET's own block --
      // matches this file's own stated convention for this exact query
      // (see the GET handler's comment just above).
      let tz;
      {
        const interval = await q(
          `SELECT tz FROM child_tz_interval
            WHERE child_id = $1 AND valid @> now()
            ORDER BY confidence DESC LIMIT 1`,
          [c.childId],
        );
        tz = interval[0]?.tz;
        if (!tz) {
          const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [c.childId]);
          tz = child[0]?.home_tz ?? 'UTC';
        }
      }
      return { status: 201, body: {
        ok: true, seq: entry.seq, authorId: entry.authorId, at: entry.at, body: entry.body,
        whenLabel: DateTime.fromISO(entry.at, { zone: 'utc' }).setZone(tz).toFormat('MMM d, h:mm a'),
      } };
    },
  });

  // GET/POST /v1/children/:childId/expenses, POST .../expenses/:expenseId/
  // accept|dispute|reimburse — real for the first time. Found by this
  // project's own coordination-layer audit, same pass that closed the
  // handover log: `expense` (db/migrations/0006_court_tier.sql) has had
  // real FORCE RLS (`expense_no_child`) since it was first migrated, and
  // family-graph/src/authorize.ts already had `expense.view`/
  // `expense.create` in its Action union with a real, unconditional P6
  // block ("a child role never sees a financial surface") — but nothing
  // anywhere ever wrote or read a row. `expenses_screen.dart`'s own client
  // UI was pure in-memory local state with zero network calls.
  //
  // Path shape deliberately child-scoped throughout (`/v1/children/:childId/
  // expenses/:expenseId/accept`), not MASTERFILE §7.7's own bare
  // `/v1/expenses/:id/accept` sketch — every real route this codebase has
  // ever registered is child-scoped (api.ts's own A3 discipline: `childId`
  // from the path only), and a bare id path would need `action: null` +
  // `identityScopedByHandler` plus a hand-rolled childId lookup before
  // `can()` could even run, for no real benefit over just keeping the same
  // shape `handoverNotes`'s own precedent already established. Same "named
  // to match what actually got built, not retrofitted to a stale
  // declaration" reasoning that route's own comment gives.
  const EXPENSE_CATEGORIES = new Set(
    ['medical', 'school', 'activity', 'clothing', 'childcare', 'other']);

  function invalidExpenseBody(body) {
    if (!body || typeof body !== 'object') return 'body_must_be_object';
    if (typeof body.description !== 'string' || !body.description.trim()) {
      return 'bad_description';
    }
    if (!Number.isInteger(body.amountCents) || body.amountCents <= 0) return 'bad_amountCents';
    if (!EXPENSE_CATEGORIES.has(body.category)) return 'bad_category';
    if (typeof body.incurredOn !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(body.incurredOn)) {
      return 'bad_incurredOn';
    }
    if (!Number.isInteger(body.payerSharePercent)
        || body.payerSharePercent < 0 || body.payerSharePercent > 100) {
      return 'bad_payerSharePercent';
    }
    if (body.receiptKey !== undefined && body.receiptKey !== null
        && typeof body.receiptKey !== 'string') {
      return 'bad_receiptKey';
    }
    return null;
  }

  function expenseToWire(e) {
    return {
      id: e.id, paidById: e.paidById, paidByName: e.paidByName,
      description: e.description,
      amountCents: e.amountCents, category: e.category, incurredOn: e.incurredOn,
      receiptKey: e.receiptKey, payerSharePercent: e.splitRule?.payerSharePercent ?? null,
      status: e.status, createdAt: e.createdAt,
    };
  }

  api.register({
    method: 'GET', path: '/v1/children/:childId/expenses', action: 'expense.view',
    handler: async (c) => {
      // Real, explicit guard on top of RLS — same reasoning the
      // handover-notes GET route's own comment gives: expensesFor() reads
      // via a SYSTEM-scoped session, which expense_no_child's RLS does not
      // block ('system' passes it freely, only 'child' is excluded), and
      // can()'s own P6_child_financial block already refuses a child at the
      // outer gate regardless — this is belt-and-suspenders, not the only
      // lock, matching this file's own established posture everywhere else.
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'P6_child_financial' } };
      }
      const entries = await expensesFor(pool, c.childId);
      return { body: { entries: entries.map(expenseToWire) } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/children/:childId/expenses', action: 'expense.create',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'P6_child_financial' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const reason = invalidExpenseBody(c.body);
      if (reason) return { status: 400, body: { error: reason } };
      const e = await proposeExpense(pool, c.principal.roleName, c.principal.userId, c.childId, {
        description: c.body.description.trim(),
        amountCents: c.body.amountCents, category: c.body.category,
        incurredOn: c.body.incurredOn, receiptKey: c.body.receiptKey ?? null,
        payerSharePercent: c.body.payerSharePercent,
      });
      return { status: 201, body: expenseToWire(e) };
    },
  });

  // One registration per verb rather than a shared `:action` path param —
  // matches this file's own consistent one-block-per-route style (see the
  // handover-notes pair just above) over introducing a new dispatch shape
  // for three routes that differ only in which string they pass through.
  for (const action of ['accept', 'dispute', 'reimburse']) {
    api.register({
      method: 'POST', path: `/v1/children/:childId/expenses/:expenseId/${action}`,
      action: 'expense.resolve',
      handler: async (c) => {
        if (c.principal.roleName === 'child') {
          return { status: 403, body: { error: 'P6_child_financial' } };
        }
        if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
        const e = await resolveExpense(pool, c.principal.roleName, c.principal.userId,
          c.childId, c.params.expenseId, action);
        // Honest 404 — a wrong/foreign expenseId (see resolveExpense()'s own
        // doc comment for why the child_id check inside that query is the
        // real lateral-privilege boundary here), never a silent 200.
        if (!e) return { status: 404, body: { error: 'expense_not_found' } };
        return { body: expenseToWire(e) };
      },
    });
  }

  // GET .../medications, POST .../medications/:medicationId/doses,
  // GET/PUT .../emergency-card — real for the first time. Found by this
  // project's own coordination-layer audit, same pass that closed the
  // handover log and expenses: medication.view/medication.log/
  // emergency_card.view already existed in family-graph/src/authorize.ts's
  // Action union with real ROLE_CAPS (guardian/step_parent/sitter/
  // foster_parent/caseworker, each narrower than the last — sitter can log
  // a dose but never edit the emergency card; step_parent can view meds but
  // never log one) — but no table, route, or pool.ts function existed for
  // either feature. meds_care.dart/emergency_card.dart were pure hardcoded
  // client state with zero network calls.
  //
  // Child-local date resolution duplicated per this file's own established
  // convention (see the handover-notes GET/POST pair's identical comment)
  // rather than shared — doseKey()'s own doc comment (meds_care.dart,
  // packages/care/src/care.ts) is explicit that dose collisions are keyed
  // on the CHILD's local day, never the server's or a client device's.
  async function resolveChildLocalDate(q, childId) {
    const interval = await q(
      `SELECT tz FROM child_tz_interval
        WHERE child_id = $1 AND valid @> now()
        ORDER BY confidence DESC LIMIT 1`,
      [childId],
    );
    let tz = interval[0]?.tz;
    if (!tz) {
      const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [childId]);
      tz = child[0]?.home_tz ?? 'UTC';
    }
    return DateTime.utc().setZone(tz).toISODate();
  }

  api.register({
    method: 'GET', path: '/v1/children/:childId/medications', action: 'medication.view',
    handler: async (c, q) => {
      // Explicit guard, not just relying on the outer gate: api.ts's own
      // child-principal path only auto-refuses P6_child_financial/
      // P7_journal_never (see that file's own authorize block) -- every
      // OTHER action, medication.view included, passes the outer gate for
      // a child session by design (a real child-facing route needs to
      // reach ITS OWN handler that way). §9.6's own "invisible to the
      // child at every depth" has to be enforced HERE, explicitly, same
      // pattern the handover-notes/expenses routes above already establish.
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      const localDate = await resolveChildLocalDate(q, c.childId);
      const [medications, doses] = await Promise.all([
        medicationsFor(pool, c.childId),
        dosesForDate(pool, c.childId, localDate),
      ]);
      return { body: {
        localDate,
        medications: medications.map(m => ({
          id: m.id, name: m.name, dose: m.dose, slots: m.slots,
          isPrn: m.isPrn, minGapHours: m.minGapHours,
        })),
        doses: doses.map(d => ({
          id: d.id, medicationId: d.medicationId, localDate: d.localDate, slot: d.slot,
          administeredAt: d.administeredAt, byUserId: d.byUserId, byUserName: d.byUserName,
          status: d.status,
        })),
      } };
    },
  });

  const DOSE_STATUSES = new Set(['given', 'skipped', 'refused', 'missed']);

  api.register({
    method: 'POST', path: '/v1/children/:childId/medications/:medicationId/doses',
    action: 'medication.log',
    handler: async (c, q) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const slot = typeof c.body?.slot === 'string' ? c.body.slot.trim() : '';
      if (!slot) return { status: 400, body: { error: 'slot_required' } };
      const status = c.body?.status ?? 'given';
      if (!DOSE_STATUSES.has(status)) return { status: 400, body: { error: 'bad_status' } };
      const localDate = await resolveChildLocalDate(q, c.childId);
      const result = await recordDose(
        pool, c.principal.roleName, c.principal.userId, c.childId,
        c.params.medicationId, localDate, slot, status);
      if (!result.ok) {
        // Named the parent and the local time, nothing more — §9.6.1's own
        // "no blame framing" rule, the exact same shape AlreadyAdministered
        // (care.ts, meds_care.dart) already gives the demo path.
        return { status: 409, body: {
          error: 'already_administered', by: result.blockedBy, atIso: result.blockedAtIso,
        } };
      }
      return { status: 201, body: {
        id: result.dose.id, medicationId: result.dose.medicationId,
        localDate: result.dose.localDate, slot: result.dose.slot,
        administeredAt: result.dose.administeredAt, status: result.dose.status,
      } };
    },
  });

  function medicalRecordToWire(r) {
    return {
      bloodType: r.bloodType, allergies: r.allergies, conditions: r.conditions,
      pediatricianName: r.pediatricianName, pediatricianPractice: r.pediatricianPractice,
      pediatricianPhone: r.pediatricianPhone, insuranceProvider: r.insuranceProvider,
      insuranceMemberId: r.insuranceMemberId,
      guardians: r.guardians.map(g => ({ userId: g.userId, name: g.name, phone: g.phone })),
      medications: r.medications.map(m => ({
        id: m.id, name: m.name, dose: m.dose, slots: m.slots, isPrn: m.isPrn,
      })),
    };
  }

  api.register({
    method: 'GET', path: '/v1/children/:childId/emergency-card', action: 'emergency_card.view',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      const record = await medicalRecordFor(pool, c.childId);
      return { body: medicalRecordToWire(record) };
    },
  });

  api.register({
    method: 'PUT', path: '/v1/children/:childId/emergency-card', action: 'emergency_card.edit',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const body = c.body ?? {};
      if (body.allergies !== undefined && !Array.isArray(body.allergies)) {
        return { status: 400, body: { error: 'bad_allergies' } };
      }
      if (body.conditions !== undefined && !Array.isArray(body.conditions)) {
        return { status: 400, body: { error: 'bad_conditions' } };
      }
      await setMedicalRecord(pool, c.principal.roleName, c.principal.userId, c.childId, {
        bloodType: body.bloodType ?? null, allergies: body.allergies ?? [],
        conditions: body.conditions ?? [], pediatricianName: body.pediatricianName ?? null,
        pediatricianPractice: body.pediatricianPractice ?? null,
        pediatricianPhone: body.pediatricianPhone ?? null,
        insuranceProvider: body.insuranceProvider ?? null,
        insuranceMemberId: body.insuranceMemberId ?? null,
      });
      const record = await medicalRecordFor(pool, c.childId);
      return { body: medicalRecordToWire(record) };
    },
  });

  // GET/POST .../exchange/bag-items, GET/POST .../exchange/running-late,
  // GET/POST .../exchange/arrival — real for the first time, same
  // coordination-layer audit that closed the handover log, expenses, and
  // medications/emergency-card. exchange_screen.dart's bag manifest/
  // running-late log/arrival sections have real, already-ported pure logic
  // (packages/care/src/care.ts's manifestOrder/recordArrival/auditArrival)
  // but no table, route, or pool.ts function existed for any of it.
  //
  // action: 'calendar.view'/'calendar.edit' — no dedicated Action exists for
  // "the exchange" in family-graph/src/authorize.ts's Action union (a real,
  // disclosed gap, same reasoning as the pre-existing GET .../now and
  // GET .../custody-order routes above, which hit the identical gap for
  // schedule-adjacent reads and made the same closest-existing-action
  // choice). This screen is guardian-shell-only (exchange_screen.dart's own
  // file header), so every route below still carries its own explicit
  // child-role guard exactly like the handover-notes/expenses/medications
  // routes above — the outer gate in api.ts only auto-refuses a child
  // principal for P6_child_financial/P7_journal_never, and calendar.view/
  // calendar.edit are neither.
  api.register({
    method: 'GET', path: '/v1/children/:childId/exchange/bag-items', action: 'calendar.view',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      const items = await bagItemsFor(pool, c.childId);
      return { body: { items } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/children/:childId/exchange/bag-items/:itemId',
    action: 'calendar.edit',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const body = c.body ?? {};
      if (body.sent !== undefined && typeof body.sent !== 'boolean') {
        return { status: 400, body: { error: 'bad_sent' } };
      }
      if (body.returned !== undefined && typeof body.returned !== 'boolean') {
        return { status: 400, body: { error: 'bad_returned' } };
      }
      const item = await setBagItemStatus(
        pool, c.principal.roleName, c.principal.userId, c.childId, c.params.itemId,
        { sent: body.sent, returned: body.returned });
      if (!item) return { status: 404, body: { error: 'bag_item_not_found' } };
      return { body: item };
    },
  });

  api.register({
    method: 'GET', path: '/v1/children/:childId/exchange/running-late', action: 'calendar.view',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      const entries = await runningLateLogFor(pool, c.childId);
      return { body: { entries } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/children/:childId/exchange/running-late', action: 'calendar.edit',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const etaMinutes = c.body?.etaMinutes;
      if (typeof etaMinutes !== 'number' || !Number.isFinite(etaMinutes) || etaMinutes <= 0) {
        return { status: 400, body: { error: 'eta_minutes_must_be_positive' } };
      }
      const entry = await logRunningLate(
        pool, c.principal.roleName, c.principal.userId, c.childId, Math.round(etaMinutes));
      return { status: 201, body: entry };
    },
  });

  api.register({
    method: 'GET', path: '/v1/children/:childId/exchange/arrival', action: 'calendar.view',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      const event = await arrivalEventFor(pool, c.childId);
      return { body: { event } };
    },
  });

  api.register({
    // No location parameter is ever read off c.body here — P3 (§9.7.2),
    // structurally: there is nothing to smuggle a coordinate through even if
    // a future edit wanted to. `scheduled_at` is computed server-side by
    // recordExchangeArrival() itself, from the child's real active custody
    // order — never trusted from the client, same discipline
    // resolveChildLocalDate() already established for medication doses above.
    method: 'POST', path: '/v1/children/:childId/exchange/arrival', action: 'calendar.edit',
    handler: async (c, q) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const localDate = await resolveChildLocalDate(q, c.childId);
      const result = await recordExchangeArrival(
        pool, c.principal.roleName, c.principal.userId, c.childId, localDate);
      if (!result.ok) {
        // Honest absence — no active custody order to compute a scheduled
        // time from, never a guessed/fabricated one (same posture the /now
        // route above takes for sleepsUntilHandover).
        return { status: 409, body: { error: result.error } };
      }
      return { status: 201, body: result.event };
    },
  });

  // GET/POST .../care-notes — real for the first time, same
  // coordination-layer audit that closed the handover log, expenses,
  // medications/emergency-card, and the exchange. care_note.dart's own
  // writeCareNote()/CARE_NOTE_TTL_DAYS/CARE_NOTE_BANNED are a real,
  // already-tested pure port of packages/guardian/src/guardian.ts's §12.5
  // section, reused directly here (writeCareNoteRow(), packages/db/src/
  // pool.ts) rather than re-implemented — the tone guard runs BEFORE a row
  // is ever written, matching that file's own "enforced before a note is
  // ever created" posture.
  //
  // `care_note.view`/`care_note.write` are new Actions
  // (family-graph/src/authorize.ts) — guardian-only routes, same
  // explicit-child-guard requirement as every other coordination route in
  // this file: the outer gate only auto-refuses a child for P6/P7, and
  // care_note.view/write are neither.
  api.register({
    method: 'GET', path: '/v1/children/:childId/care-notes', action: 'care_note.view',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      const entries = await careNotesFor(pool, c.childId);
      return { body: { entries } };
    },
  });

  const CARE_KINDS = new Set(['sleep', 'appetite', 'mood', 'health', 'school', 'social', 'other']);

  api.register({
    method: 'POST', path: '/v1/children/:childId/care-notes', action: 'care_note.write',
    handler: async (c) => {
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'not_a_child_surface' } };
      }
      if (!c.principal.userId) return { status: 400, body: { error: 'no_user_identity' } };
      const rawItems = Array.isArray(c.body?.items) ? c.body.items : null;
      if (!rawItems || !rawItems.length) return { status: 400, body: { error: 'items_required' } };
      const items = [];
      for (const it of rawItems) {
        const kind = it?.kind;
        const note = typeof it?.note === 'string' ? it.note : '';
        if (!CARE_KINDS.has(kind)) return { status: 400, body: { error: 'bad_kind' } };
        items.push({ kind, note });
      }
      const result = await writeCareNoteRow(
        pool, c.principal.roleName, c.principal.userId, c.childId, items);
      if (!result.ok) {
        // Same §9.6.1-style "name the reason, nothing else" posture every
        // other real rejection in this file already has -- 'found' names
        // WHICH banned phrase, never a rewritten/sanitized version of her text.
        return { status: 400, body: { error: result.reason, found: result.found } };
      }
      return { status: 201, body: {
        id: result.entry.id, items: result.entry.items,
        createdAt: result.entry.createdAt, expiresAt: result.entry.expiresAt,
      } };
    },
  });

  // GET/POST .../letters, POST .../letters/:letterId/open,
  // DELETE .../letters/:letterId — real for the first time, same
  // coordination-layer audit. letters_screen.dart's own sealLetter()/
  // openLetter()/deleteLetter()/lettersDue() are a real, already-tested
  // pure port of packages/maturation/src/maturation.ts's §21.4/§21.8
  // section -- see db/migrations/0028's own header, and pool.ts's own
  // LetterMeta/sealLetterRow/openLetterRow/deleteLetterRow doc comments,
  // for the full account of what is and is not reused verbatim.
  //
  // `letter` is a new Action deliberately listed in NO role's ROLE_CAPS
  // (family-graph/src/authorize.ts) -- structurally unreachable via any
  // guardian edge. Every route below still carries its own explicit
  // `roleName !== 'child'` guard anyway, the INVERSE of every other
  // coordination route in this file (which excludes the child) -- this is
  // the one child-owned, guardian-excluded feature in this whole file, and
  // the guard reads that way on purpose. `letter_owner_only` (0028) is the
  // real backstop underneath even this: a bug in this route-level check
  // would still be caught at the RLS layer, the same "second lock, not the
  // only one" posture authorize.ts's own file header describes.
  api.register({
    method: 'GET', path: '/v1/children/:childId/letters', action: 'letter',
    handler: async (c) => {
      if (c.principal.roleName !== 'child') {
        return { status: 403, body: { error: 'not_a_guardian_surface' } };
      }
      const letters = await lettersFor(pool, c.childId);
      return { body: { letters } };
    },
  });

  api.register({
    method: 'POST', path: '/v1/children/:childId/letters', action: 'letter',
    handler: async (c, q) => {
      if (c.principal.roleName !== 'child') {
        return { status: 403, body: { error: 'not_a_guardian_surface' } };
      }
      const body = typeof c.body?.body === 'string' ? c.body.body.trim() : '';
      const openAtAge = c.body?.openAtAge;
      if (!body) return { status: 400, body: { error: 'body_required' } };
      if (typeof openAtAge !== 'number' || !Number.isInteger(openAtAge)) {
        return { status: 400, body: { error: 'open_at_age_required' } };
      }
      const localDate = await resolveChildLocalDate(q, c.childId);
      const result = await sealLetterRow(pool, c.childId, openAtAge, body, localDate);
      if (!result.ok) {
        // Honest refusal, real reasons — 'child_not_found' is only
        // reachable if the session's own childId somehow names no real row
        // (defensive; the outer gate already validated a real edge/identity).
        return { status: 400, body: { error: result.reason } };
      }
      return { status: 201, body: {
        id: result.letter.id, writtenAtAge: result.letter.writtenAtAge,
        openAtAge: result.letter.openAtAge, writtenAt: result.letter.writtenAt,
        openedAt: null,
      } };
    },
  });

  api.register({
    // §21.4's real invariant: NOBODY can open a sealed letter early, not
    // even her. currentAge is computed server-side inside openLetterRow()
    // itself from her real birth_date -- this route never reads an age off
    // the request at all, structurally, so there is nothing here a future
    // edit could even try to trust from the client.
    method: 'POST', path: '/v1/children/:childId/letters/:letterId/open', action: 'letter',
    handler: async (c, q) => {
      if (c.principal.roleName !== 'child') {
        return { status: 403, body: { error: 'not_a_guardian_surface' } };
      }
      const localDate = await resolveChildLocalDate(q, c.childId);
      const result = await openLetterRow(pool, c.childId, c.params.letterId, localDate);
      if (!result.ok) {
        if (result.reason === 'not_found') return { status: 404, body: { error: 'letter_not_found' } };
        return { status: 409, body: { error: result.reason, yearsLeft: result.yearsLeft } };
      }
      return { body: {
        id: result.letter.id, writtenAtAge: result.letter.writtenAtAge,
        openAtAge: result.letter.openAtAge, writtenAt: result.letter.writtenAt,
        openedAt: result.letter.openedAt, body: result.letter.body,
      } };
    },
  });

  api.register({
    // §2.10 — she can delete without ever having read it; it is hers. The
    // only early exit this file ever offers on a letter — read never is.
    method: 'DELETE', path: '/v1/children/:childId/letters/:letterId', action: 'letter',
    handler: async (c) => {
      if (c.principal.roleName !== 'child') {
        return { status: 403, body: { error: 'not_a_guardian_surface' } };
      }
      const deleted = await deleteLetterRow(pool, c.childId, c.params.letterId);
      if (!deleted) return { status: 404, body: { error: 'letter_not_found' } };
      return { body: { deleted: true } };
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
      // from any guardian, and a body-supplied childId would let anyone
      // attribute a send to a different child). A `child` principal carries
      // no `userId` at all (packages/auth/src/auth.ts's VerifiedPrincipal,
      // server/index.mjs's dev-login) — she has an app_user row nowhere —
      // so `edges` stays honestly `[]` for her, and her identity is instead
      // her OWN `childId`, taken from the verified session/path exactly the
      // way api.ts's outer gateway already required it to match
      // (`principal.childId !== childId` → 403 `wrong_child`, before this
      // handler even runs).
      //
      // 0021_child_message_sender.sql is what makes this representable at
      // all: `delivery_intent.sender_id` used to be `NOT NULL REFERENCES
      // app_user(id)`, and a child has no `app_user` row, so every child-
      // originated capture was structurally unrepresentable and honestly
      // refused (`not_authorized`) — see that migration's own header, and
      // pipeline.test.mjs's M8 suite, for the full history of that gap and
      // the real success path that replaces it.
      const senderId = c.principal.userId;
      const senderRole = c.principal.roleName;
      const senderChildId = senderRole === 'child' ? c.principal.childId : null;
      const edges = senderId ? await edgesFor(pool, senderId) : [];

      const ctx = await childCtxFor(pool, c.childId);
      if (!ctx) return { status: 404, body: { error: 'child_not_found' } };

      const result = captureMessage(
        {
          childId: c.childId,
          senderId,
          senderRole,
          senderChildId,
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
        const status = result.reason === 'not_authorized' ||
          result.reason === 'child_sender_mismatch' ? 403 : 400;
        return { status, body: { error: result.reason } };
      }

      const persisted = await persistCapturedMessage(pool, result);
      return { status: 201, body: {
        id: persisted.intentId, artifactId: persisted.artifactId, state: 'pending' } };
    },
  });

  // ===========================================================================
  // REAL OBJECT STORAGE — MASTERFILE §20.2b: "packages/storage/src/storage.ts's
  // StoragePort has no production implementation anywhere in this codebase
  // ... receipt_screen.dart's real camera capture never uploads the recorded
  // bytes; media_artifact.storage_key is a locally-meaningful reference only."
  // These two routes are the real upload/download half of that gap.
  // FilesystemStorage itself (this module's own `storage` param, defaulting
  // to `defaultMediaStorage` above) was already real and already tested —
  // this is its first real caller.
  // ===========================================================================

  // Uploads the REAL bytes client/lib/receipt_screen.dart's camera capture
  // records, returning the REAL storage key FilesystemStorage assigned —
  // meant to be fed straight into the POST .../messages route just above as
  // its `storageKey`, a genuinely separate step from persisting the
  // media_artifact/delivery_intent rows (captureMessage()'s own pipeline
  // still decides whether a capture is ALLOWED; this route only ever
  // decides whether bytes can be WRITTEN, the same separation the pipeline
  // already draws between "persist" and "validate").
  //
  // `action: 'message'` — the identical gate POST .../messages already runs
  // (api.ts's A1 declared-action + A3 childId-from-path), not a second,
  // parallel check invented for this one route. `skipOuterSession: true`
  // for the same reason routes.mjs's homework-capture route already gives:
  // this handler does real, possibly-slow disk I/O and touches Postgres
  // not at all, so holding the outer `db.withSession()` connection open
  // for its whole duration would be pure waste (see api.ts's own doc
  // comment on that flag for the real, live-reproduced pool-deadlock this
  // avoids under concurrency).
  api.register({
    method: 'POST', path: '/v1/children/:childId/media', action: 'message',
    skipOuterSession: true,
    handler: async (c) => {
      const b64 = c.body?.bytes;
      if (typeof b64 !== 'string' || b64.length === 0) {
        return { status: 400, body: { error: 'bytes_required' } };
      }
      let bytes;
      try {
        bytes = Buffer.from(b64, 'base64');
      } catch {
        return { status: 400, body: { error: 'bad_bytes' } };
      }
      // An empty capture is refused HERE, not left to surface later as a
      // confusing captureMessage() `empty_recording` denial against a
      // storageKey that turned out to point at a zero-byte file.
      if (bytes.length === 0) return { status: 400, body: { error: 'bad_bytes' } };

      // children/<childId>/messages/<uuid> — mirrors the real nested-key
      // shape storage.test.mjs's own "Q nested keys" group already proves
      // FilesystemStorage handles (list()-by-prefix, no cross-child leakage).
      // childId comes from the verified path (A3), never the body — the
      // same identity discipline every other write in this file follows.
      const key = `children/${c.childId}/messages/${randomUUID()}`;
      const put = await storage.put(key, bytes);
      return { status: 201, body: { storageKey: put.key, etag: put.etag } };
    },
  });

  // Reads back the REAL bytes a prior POST .../media wrote, once they are
  // attached to a real, persisted media_artifact row (POST .../messages'
  // own job, above) — the real counterpart to GET .../inbox for the
  // ACTUAL payload an inbox entry only ever named a reference to.
  //
  // `action: 'message'` — the SAME gate GET .../inbox and POST .../messages
  // already run, per this task's own instruction not to build a separate,
  // weaker check. `mediaArtifactFor()` (pool.ts) is the real authorization
  // BOUNDARY underneath that gate: media_artifact carries no row-level
  // security of its own (see persistCapturedMessage()'s header), so the
  // `WHERE id = $1 AND child_id = $2` that function runs is what actually
  // stops a caller who is authorized for THIS child from reading a
  // DIFFERENT child's artifact merely by guessing its uuid — the exact
  // "child-authorization boundary" concern this pass was asked to hold.
  // `skipOuterSession: true` for the same reason the upload route above
  // does: this handler runs its OWN system-scoped query
  // (mediaArtifactFor()'s own withSystemSession) plus real disk I/O, never
  // the outer caller-scoped `q`.
  //
  // Returns the real bytes base64-encoded in the JSON body — the same
  // convention this whole API already uses in the other direction
  // (captureHomework's `image` field) — rather than a raw byte stream or a
  // real signed-URL-serving `/media/:key` endpoint. `StoragePort.signedUrl()`
  // exists and is real-tested (storage.test.mjs), but nothing in this
  // codebase serves the URL it produces — building that (an unauthenticated,
  // signature-verified byte-serving path OUTSIDE api.ts's session-based JSON
  // contract entirely) is real, separate follow-up work, not silently
  // folded in here. This route is deliberately the SESSION-authenticated
  // read path the task asked for, not the differently-authorized signed-URL
  // one.
  api.register({
    method: 'GET', path: '/v1/children/:childId/messages/:artifactId/media',
    action: 'message', skipOuterSession: true,
    handler: async (c) => {
      const artifact = await mediaArtifactFor(pool, c.childId, c.params.artifactId);
      if (!artifact) return { status: 404, body: { error: 'artifact_not_found' } };
      const bytes = await storage.get(artifact.storageKey);
      // A row that outlived its blob — the reaper's own "row survives so the
      // blob stays discoverable" tombstone case (storage.ts's reap()), or a
      // capture that persisted its row before this pass existed and never
      // had real bytes behind it at all. Either way: an honest 404, not a
      // 500 or an empty-but-200 body pretending there was something there.
      if (!bytes) return { status: 404, body: { error: 'media_not_found' } };
      return { body: { bytes: bytes.toString('base64'), kind: artifact.kind } };
    },
  });
}
