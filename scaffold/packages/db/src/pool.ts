import pg from 'pg';
import { DateTime } from 'luxon';
import type { VerifiedPrincipal, Credential } from '../../auth/src/auth.ts';
import { newChallenge, verifyPin } from '../../auth/src/auth.ts';
import { can, type Edge, type Deny } from '../../family-graph/src/authorize.ts';
import type { DbPort, Query } from '../../api/src/api.ts';
import type { Order } from '../../custody/src/schedule.ts';
import {
  verifyChain, certify, authorizeExport,
  type LogEntry, type Attestation, type ChainFault, type ExportDenial,
} from '../../ledger/src/ledger.ts';
import { sha256Hex } from '../../ledger/src/sha256.ts';
import type { ArtifactRow, IntentRow } from '../../messaging/src/pipeline.ts';
import type { ChildCtx } from '../../delivery-engine/src/materialize.ts';
import type { Platform } from '../../transport/src/push.ts';
import type { Channel } from '../../devices/src/devices.ts';
import {
  handover, type Child as HandoverChild, type Artifact as HandoverArtifact,
  type HandoverDenial,
} from '../../archive/src/archive.ts';

/**
 * MASTERFILE §5.18 — session context, and §5.17 — the second lock.
 *
 * This did not exist anywhere in the repository before now: `packages/api`
 * defined the `DbPort` interface and every test exercised it against a hand-
 * written fake (see stack.test.mjs). This file is the first real
 * implementation, against a real Postgres connection.
 *
 * The GUCs `app.role`, `app.child_id`, `app.user_id` are written in EXACTLY
 * ONE place: `withSession()` below. A second writer turns P6/P7 into
 * parameter-tampering bugs, per §5.18's own wording -- so nothing else in
 * this codebase should ever call `set_config('app.role', ...)` directly.
 */

export function createPool(connectionString: string): pg.Pool {
  return new pg.Pool({ connectionString });
}

/**
 * `set_config(..., is_local => true)` — transaction-scoped, unwinds on COMMIT
 * *and* ROLLBACK. A plain `SET` persists on a pooled connection, so the next
 * request handled by that same physical connection would inherit this
 * request's child context: a cross-tenant read with no code path that looks
 * wrong. Every GUC write below goes through set_config with true, on the same
 * client the whole transaction runs on, never a bare `SET`.
 *
 * Bound parameters, never interpolation — the security context is the last
 * place to accept string concatenation.
 */
export async function withSession<T>(
  pool: pg.Pool,
  principal: Pick<VerifiedPrincipal, 'roleName' | 'userId' | 'childId'>,
  fn: (q: Query) => Promise<T>,
): Promise<T> {
  // Context originates from a verified principal. A child role with no
  // childId, or a non-child/non-system role with no userId, throws rather
  // than matching nothing.
  if (principal.roleName === 'child' && !principal.childId) {
    throw new Error('withSession: child principal missing childId');
  }
  if (principal.roleName !== 'child' && principal.roleName !== 'system' && !principal.userId) {
    throw new Error(`withSession: ${principal.roleName} principal missing userId`);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SELECT set_config('app.role', $1, true)`, [principal.roleName]);
    // Accessors on the DB side (current_child()/current_user_id()) are
    // wrapped as NULLIF(current_setting(...,true),'')::uuid specifically
    // because the bare cast raises on an empty string -- so an unconditional
    // set_config with '' for the absent side (rather than skipping the call)
    // is required, not optional, or a pool that always sets both GUCs turns
    // fail-closed into fail-crash. See MASTERFILE §5.18, v0.6.0 findings.
    await client.query(`SELECT set_config('app.child_id', $1, true)`, [principal.childId ?? '']);
    await client.query(`SELECT set_config('app.user_id', $1, true)`, [principal.userId ?? '']);

    const q: Query = async (sql, params = []) => {
      const res = await client.query(sql, params as any[]);
      return res.rows;
    };
    const result = await fn(q);
    await client.query('COMMIT');
    return result;
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

/** For the delivery sweep and other background jobs — role `system`, no child context. */
export function withSystemSession<T>(pool: pg.Pool, fn: (q: Query) => Promise<T>): Promise<T> {
  return withSession(pool, { roleName: 'system', userId: null, childId: null }, fn);
}

/**
 * §5.17 — the database enforces P6/P7 independently via RLS; this is the
 * data this file's caller (packages/api) needs to run the *pure* `can()`
 * authorizer as the first lock. Closed, expired, or not-yet-valid edges are
 * still returned here — `can()` itself is what rejects them, so filtering
 * them out here would just move the enforcement to a second, unaudited place.
 */
export async function edgesFor(pool: pg.Pool, userId: string): Promise<Edge[]> {
  // Runs under the system role: listing a caller's OWN edges is an identity
  // operation the API layer needs before it can determine caller vs subject,
  // not something that itself needs `can()` to have already run.
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT g.child_id, g.user_id, g.role, g.scope, g.observer_only, g.restricted,
              lower(g.valid)::text AS valid_from, upper(g.valid)::text AS valid_to,
              g.expires_at::text AS expires_at, g.closed_at::text AS closed_at,
              cl.step AS ladder_step
         FROM guardianship g
         LEFT JOIN contact_ladder cl
           ON cl.guardianship_id = g.id AND cl.effective @> now()
        WHERE g.user_id = $1`,
      [userId],
    );
    return rows.map((r: any): Edge => ({
      childId: r.child_id,
      userId: r.user_id,
      role: r.role,
      scope: r.scope ?? {},
      observerOnly: r.observer_only,
      restricted: r.restricted,
      validFrom: r.valid_from,
      validTo: r.valid_to,
      expiresAt: r.expires_at,
      closedAt: r.closed_at,
      ladderStep: r.ladder_step,
    }));
  });
}

/**
 * db/migrations/0007_custody_order.sql — the real end-to-end loader for
 * schedule.ts's `Order`. §5.4 names the row shape; this is the one place
 * that row is turned into the exact shape sleepsUntilSideChange()/
 * patternSideOn()/blocks()/exchanges() consume (see custody_order.test.mjs,
 * which proves both the RLS on this table and this mapping).
 *
 * Mirrors edgesFor()'s own shape: its own withSystemSession, one query, one
 * row-to-domain mapping. System role because "what order governs this child
 * today" is a lookup the route handler needs before/alongside its own
 * caller-scoped session, not something that itself needs a second `can()`
 * pass — RLS on custody_order already admits the child her own row and every
 * non-child role everything else (see the migration's policies), so running
 * this as `system` does not widen who can reach it; the handler's existing
 * A3 childId-from-path check is what gates the call.
 *
 * A child can have more than one custody_order over her life (effective_from/
 * effective_to); returns the one in force on `nowLocalDate`, or `null` if
 * none is — an honest absence, never a guess, per the migration's own
 * EXCLUDE constraint guaranteeing at most one row can match.
 */
export async function activeCustodyOrderFor(
  pool: pg.Pool, childId: string, nowLocalDate: string,
): Promise<Order | null> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT pattern, order_tz,
              anchor_local_date::text AS anchor_local_date,
              to_char(exchange_time, 'HH24:MI') AS exchange_time,
              holiday_rules,
              effective_from::text AS effective_from,
              effective_to::text AS effective_to
         FROM custody_order
        WHERE child_id = $1
          AND effective_from <= $2::date
          AND (effective_to IS NULL OR effective_to >= $2::date)
        LIMIT 1`,
      [childId, nowLocalDate],
    );
    if (!rows.length) return null;
    const r = rows[0];
    return {
      pattern: r.pattern,
      orderTz: r.order_tz,
      anchorLocalDate: r.anchor_local_date,
      exchangeTime: r.exchange_time,
      holidays: r.holiday_rules ?? [],
      effectiveFrom: r.effective_from,
      effectiveTo: r.effective_to,
    } as Order;
  });
}

/**
 * db/migrations/0008_auth_credentials.sql — real guardian PIN + WebAuthn
 * credentials, replacing the hardcoded, unauthenticated '1273' the client
 * shipped with (client/lib/main.dart). Every function below follows the two
 * patterns already established in this file: identity-resolution reads run
 * `system`-scoped (edgesFor()'s own reasoning, extended here to
 * guardiansOfChild()); everything else runs scoped to the SPECIFIC guardian
 * it concerns, as that guardian's own session, so pin_credential/
 * webauthn_credential's owner-only RLS (0008's own policies) admits exactly
 * the one row each call needs and nothing else — there is no `system`
 * bypass on those two tables for routine reads/writes, deliberately (see
 * 0008's own comments on webauthn_credential's narrower exception).
 */

/**
 * §5.17's "first lock" needs to know WHO a child's guardians are before the
 * kiosk-pin ceremony can check an entered PIN against any of them — an
 * identity-resolution step independent of `can()`, exactly edgesFor()'s own
 * justification above, mirrored here for the reverse direction (child ->
 * guardians rather than guardian -> children). Runs `system`-scoped for the
 * same reason: guardianship itself carries no RLS in this schema (access to
 * it is gated at the application layer, per 0007's own header), so there is
 * no narrower session this could run under that would change what it sees.
 *
 * Queries `effective_guardianship` (0003_session_context.sql) rather than
 * re-deriving "live edge" against the raw `guardianship` table a second time
 * — merged in from the guardian-availability branch, which caught a real gap
 * in this function's first draft: the raw-table version only checked
 * `closed_at IS NULL AND valid @> now()`, missing `expires_at`, so a
 * guardianship edge that had timed out via `expires_at` but not yet been
 * explicitly closed would still count as "live" for kiosk-PIN purposes.
 * `effective_guardianship` is the one already-audited definition of "live"
 * every other RLS policy in this schema agrees on; this now matches it
 * exactly instead of maintaining a second, slightly-wrong copy of the same
 * filter. Return shape stays `{ userId }[]`, not a bare `string[]`, because
 * the kiosk-pin/verify route (routes.mjs) already destructures `g.userId`.
 */
export async function guardiansOfChild(
  pool: pg.Pool, childId: string,
): Promise<{ userId: string }[]> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT DISTINCT user_id FROM effective_guardianship WHERE child_id = $1`,
      [childId],
    );
    return rows.map((r: any) => ({ userId: r.user_id }));
  });
}

export async function pinCredentialFor(
  pool: pg.Pool, userId: string,
): Promise<{ pinHash: string; failedAttempts: number; lockedUntil: Date | null } | null> {
  // Scoped as THAT guardian's own session, not `system` — pin_credential has
  // no system-role policy at all (0008's migration), so a PIN hash is never
  // one dropped withSystemSession call away from being readable for every
  // guardian at once. The caller already knows which specific guardian it is
  // asking about (from guardiansOfChild(), or from c.principal.userId for a
  // guardian managing her own PIN), so scoping to exactly that userId is not
  // a widening of access — it is a change of WHICH single guardian's own row
  // this particular call is allowed to see, same as every other call here.
  return withSession(pool, { roleName: 'guardian', userId, childId: null }, async (q) => {
    const rows = await q(
      `SELECT pin_hash, failed_attempts, locked_until FROM pin_credential WHERE user_id = $1`,
      [userId],
    );
    if (!rows.length) return null;
    const r = rows[0];
    return { pinHash: r.pin_hash, failedAttempts: r.failed_attempts, lockedUntil: r.locked_until };
  });
}

/** Upsert. Setting a NEW pin clears any standing lockout/counter from the OLD
 * one — a guardian who just proved she can authenticate well enough to reach
 * this endpoint (it requires an existing guardian session) should not stay
 * locked out under a PIN she is actively replacing.
 *
 * SEC-01 follow-up — same `account_deactivated` gate as
 * storeWebauthnCredential() below, same atomic shape (`FOR UPDATE` inside
 * the same transaction as the write, not a separate pre-check): a
 * deactivated guardian's still-valid session should not be able to set a
 * FRESH kiosk PIN. Lower stakes than the WebAuthn case (this credential only
 * ever produces `{ok: matched}` for kiosk-escalation, per attemptPinFor()
 * below — it never issues a new session) but the same root cause, and the
 * atomic version costs nothing extra to write once the pattern exists, so it
 * gets the same treatment rather than the narrower accepted-race one. */
export async function setPinCredential(
  pool: pg.Pool, userId: string, pinHash: string,
): Promise<void> {
  await withSession(pool, { roleName: 'guardian', userId, childId: null }, async (q) => {
    const [row] = await q(
      `SELECT deactivated_at FROM app_user WHERE id = $1 FOR UPDATE`, [userId]);
    if (row?.deactivated_at) {
      throw Object.assign(
        new Error('setPinCredential: account is deactivated'),
        { code: 'account_deactivated' },
      );
    }
    await q(
      `INSERT INTO pin_credential (user_id, pin_hash, failed_attempts, locked_until, updated_at)
       VALUES ($1, $2, 0, NULL, now())
       ON CONFLICT (user_id) DO UPDATE
         SET pin_hash = EXCLUDED.pin_hash, failed_attempts = 0,
             locked_until = NULL, updated_at = now()`,
      [userId, pinHash],
    );
  });
}

/**
 * Two real, defensible numbers, not bare magic ones:
 *
 *  PIN_MAX_ATTEMPTS = 5 — a 4-digit PIN has 10,000 possible values. scrypt
 *  (auth.ts's hashPin/verifyPin) is the defense against an attacker who has
 *  already stolen the hash and can guess offline as fast as hardware allows;
 *  this counter is the OTHER defense, against an attacker (or a curious
 *  child) hammering the live kiosk endpoint with no hash at all. 5 tries is
 *  enough headroom for a guardian who mistypes twice in a row, while capping
 *  any one lockout window to a tiny fraction of the keyspace.
 *
 *  PIN_LOCKOUT_MS = 15 minutes — long enough that 5-per-15-minutes caps a
 *  sustained attacker at under 500 guesses/day (against 10,000 total),
 *  short enough that this doesn't become its own safety problem: this same
 *  PIN gates a child's escalation to a guardian who is standing right there
 *  (§8.1) — a lockout measured in hours would turn "Mom mistyped her PIN"
 *  into "call support," which is worse than the risk it defends against.
 *  The counter resets to 0 the moment a lock is imposed (not merely paused),
 *  so lockouts do not stack into an ever-longer ban across repeated windows.
 */
export const PIN_MAX_ATTEMPTS = 5;
export const PIN_LOCKOUT_MS = 15 * 60 * 1000;

export async function recordPinAttempt(
  pool: pg.Pool, userId: string, success: boolean,
): Promise<{ lockedUntil: Date | null }> {
  return withSession(pool, { roleName: 'guardian', userId, childId: null }, async (q) => {
    if (success) {
      const rows = await q(
        `UPDATE pin_credential
            SET failed_attempts = 0, locked_until = NULL, updated_at = now()
          WHERE user_id = $1
          RETURNING locked_until`,
        [userId],
      );
      return { lockedUntil: rows[0]?.locked_until ?? null };
    }
    // A single UPDATE, not a read-then-write: two concurrent failed attempts
    // against the same guardian must not both observe failed_attempts=4 and
    // both step to 5 while only one commits the lock — the same TOCTOU shape
    // consumeChallenge() below is written to avoid (see its own comment; that
    // exact class of bug was found and fixed on feature/secure-network-play).
    // The CASE arms compute the new counter and the new lock deadline from
    // the row this UPDATE already holds a lock on, never from a value read
    // in a separate prior statement.
    const rows = await q(
      `UPDATE pin_credential
          SET failed_attempts = CASE WHEN failed_attempts + 1 >= $2 THEN 0
                                      ELSE failed_attempts + 1 END,
              locked_until = CASE WHEN failed_attempts + 1 >= $2
                                   THEN now() + ($3 || ' milliseconds')::interval
                                   ELSE locked_until END,
              updated_at = now()
        WHERE user_id = $1
        RETURNING locked_until`,
      [userId, PIN_MAX_ATTEMPTS, PIN_LOCKOUT_MS],
    );
    return { lockedUntil: rows[0]?.locked_until ?? null };
  });
}

/**
 * The real fix for a critical, live-reproduced bug found in adversarial
 * review of this file's original kiosk-pin/verify caller: that caller read
 * `pinCredentialFor()` (a plain SELECT, no row lock) to decide whether a
 * guardian is currently locked out, and only LATER — as a completely separate
 * round trip, after the slow ~64ms scrypt verify — called `recordPinAttempt()`
 * to record the outcome. Nothing held a lock across that gap, so N concurrent
 * guesses against the SAME guardian all read "not locked" before any of them
 * had a chance to observe a lock a sibling request was in the middle of
 * imposing — every single one of them then ran a real scrypt verification
 * against the true hash, regardless of PIN_MAX_ATTEMPTS. Measured live: 200
 * concurrent guesses against one guardian, 200/200 ran verifyPin(), account
 * merely ended up at failed_attempts=1 — the lockout provided ZERO protection
 * against a concurrent burst, only against sequential guessing.
 *
 * The fix: fold "read the lock state", "verify", and "record the outcome"
 * into ONE transaction that takes a `SELECT ... FOR UPDATE` row lock on the
 * guardian's own pin_credential row FIRST, before doing anything else.
 * Postgres serializes every concurrent transaction that wants that same row:
 * only one can hold the lock at a time, and each one that acquires it next
 * sees the FRESH state left by the one before it (including any lock that one
 * just imposed) — not a stale snapshot read before that write happened. This
 * makes the check-then-verify-then-record sequence atomic with respect to
 * every OTHER concurrent attempt against the same guardian, which a separate
 * SELECT (no lock) followed by a separate UPDATE never was, no matter how
 * correct either statement was in isolation (recordPinAttempt()'s own UPDATE
 * was already provably safe from lost updates on the COUNTER — see its own
 * comment — the bug was entirely in the READ that decided whether to even
 * attempt verifyPin() in the first place).
 *
 * Net effect under concurrency: of N simultaneous guesses against one
 * guardian, AT MOST PIN_MAX_ATTEMPTS of them ever reach verifyPin() before
 * the rest observe the lock this same function just imposed and skip it —
 * exactly the sequential-guessing guarantee the lockout's own numbers
 * (PIN_MAX_ATTEMPTS/PIN_LOCKOUT_MS) were designed around, now also true when
 * every guess arrives at once. Proven live in
 * packages/db/test/auth_credentials.test.mjs's "F concurrency" section.
 *
 * No deactivated_at check here, deliberately, unlike setPinCredential()
 * above (SEC-01 follow-up): deactivateAccount() already DELETEs this user's
 * pin_credential row entirely, so a deactivated guardian's own PIN fails
 * this function's own `!rows.length` branch on its own — nothing left to
 * verify against. Same reasoning deletion.test.mjs's own header already
 * documents for why a real PIN/WebAuthn login "fails on its own."
 */
export async function attemptPinFor(
  pool: pg.Pool, userId: string, candidatePin: string,
): Promise<{ matched: boolean; hasCredential: boolean; locked: boolean }> {
  return withSession(pool, { roleName: 'guardian', userId, childId: null }, async (q) => {
    // FOR UPDATE — taken BEFORE anything else runs, so a concurrent call for
    // this exact userId blocks here until this transaction commits, rather
    // than racing ahead on a stale read. Real, not cosmetic: this is the one
    // line that turns "check" and "act" back into a single atomic step.
    const rows = await q(
      `SELECT pin_hash, failed_attempts, locked_until
         FROM pin_credential WHERE user_id = $1 FOR UPDATE`,
      [userId],
    );
    if (!rows.length) return { matched: false, hasCredential: false, locked: false };
    const r = rows[0];
    if (r.locked_until && r.locked_until.getTime() > Date.now()) {
      // Same documented, deliberate timing trade-off kiosk-pin/verify's own
      // comment already accepts: a locked guardian's scrypt check is skipped
      // entirely rather than run-and-discarded.
      return { matched: false, hasCredential: true, locked: true };
    }
    const ok = verifyPin(candidatePin, r.pin_hash);
    // Still inside the SAME transaction, still holding the SAME row lock —
    // this UPDATE cannot itself be raced by another attemptPinFor() call for
    // this userId, because no other such call can even acquire the FOR
    // UPDATE lock above until this one commits.
    if (ok) {
      await q(
        `UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL, updated_at = now()
          WHERE user_id = $1`,
        [userId],
      );
    } else {
      await q(
        `UPDATE pin_credential
            SET failed_attempts = CASE WHEN failed_attempts + 1 >= $2 THEN 0
                                        ELSE failed_attempts + 1 END,
                locked_until = CASE WHEN failed_attempts + 1 >= $2
                                     THEN now() + ($3 || ' milliseconds')::interval
                                     ELSE locked_until END,
                updated_at = now()
          WHERE user_id = $1`,
        [userId, PIN_MAX_ATTEMPTS, PIN_LOCKOUT_MS],
      );
    }
    return { matched: ok, hasCredential: true, locked: false };
  });
}

/**
 * Matches auth.ts's verifyAssertion() own default `challengeTtlMs` exactly.
 * Kept as a named constant rather than repeating the literal, so the two
 * never drift silently out of sync with each other.
 */
export const CHALLENGE_TTL_MS = 5 * 60 * 1000;

/** Generates via auth.ts's own newChallenge() (CSPRNG, 32 bytes) — this file
 * never invents its own randomness for a security token. */
export async function createChallenge(
  pool: pg.Pool, userId: string, purpose: 'register' | 'login',
): Promise<string> {
  const challenge = newChallenge();
  await withSystemSession(pool, async (q) => {
    await q(
      `INSERT INTO auth_challenge (user_id, challenge, purpose) VALUES ($1, $2, $3)`,
      [userId, challenge, purpose],
    );
  });
  return challenge;
}

/**
 * Single-use, atomically. A challenge is valid exactly once: this is a single
 * `UPDATE ... WHERE consumed_at IS NULL ... RETURNING`, so "is this challenge
 * still live" and "mark it consumed" happen as one statement under Postgres's
 * own row lock rather than two round trips a second concurrent call could
 * interleave between. Two callers racing the identical UPDATE can both issue
 * it; Postgres serializes writers to the same row, so the second one simply
 * matches zero rows (the first already flipped consumed_at) — never a torn
 * read where both believe they were first. This is exactly the join-token-
 * redemption TOCTOU class found and fixed on feature/secure-network-play;
 * this function is written to not reintroduce it.
 */
export async function consumeChallenge(
  pool: pg.Pool, userId: string, purpose: 'register' | 'login', challenge: string,
): Promise<boolean> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `UPDATE auth_challenge
          SET consumed_at = now()
        WHERE user_id = $1 AND purpose = $2 AND challenge = $3
          AND consumed_at IS NULL
          AND issued_at > now() - ($4 || ' milliseconds')::interval
        RETURNING id`,
      [userId, purpose, challenge, CHALLENGE_TTL_MS],
    );
    return rows.length === 1;
  });
}

/**
 * SEC-01 follow-up (round-2 audit's adversarial verify, not the original
 * finding) — a real, WORSE variant of the same bug class: unlike a
 * device_token, a WebAuthn credential minted here is not TTL-bound at all.
 * Without this gate, a deactivated guardian's still-valid session could
 * register a brand-new passkey, then use it via `webauthnLoginVerify()`
 * (server/index.mjs, gated to match, same pass) to re-authenticate
 * indefinitely — full standing guardian access, never expiring on its own,
 * not merely outliving one session's 1h TTL. That severity is why this gate
 * is ATOMIC, unlike registerDeviceToken()'s own accepted narrow race
 * (above): `app_user_read_all` (0011_account_deletion.sql) is `USING (true)`
 * — any role can read any row — so the check runs `FOR UPDATE` INSIDE the
 * same guardian-scoped transaction as the INSERT, taking the identical row
 * lock deactivateAccount() itself takes first. A concurrent
 * deactivateAccount() call for this exact userId and this registration
 * genuinely serialize against each other: whichever commits first is the
 * only outcome the other can observe — not two independent round trips with
 * a gap between them.
 */
export async function storeWebauthnCredential(
  pool: pg.Pool, userId: string, credentialId: string, publicKeyPem: string,
): Promise<void> {
  await withSession(pool, { roleName: 'guardian', userId, childId: null }, async (q) => {
    const [row] = await q(
      `SELECT deactivated_at FROM app_user WHERE id = $1 FOR UPDATE`, [userId]);
    if (row?.deactivated_at) {
      throw Object.assign(
        new Error('storeWebauthnCredential: account is deactivated'),
        { code: 'account_deactivated' },
      );
    }
    await q(
      `INSERT INTO webauthn_credential (user_id, credential_id, public_key_pem)
       VALUES ($1, $2, $3)`,
      [userId, credentialId, publicKeyPem],
    );
  });
}

export async function webauthnCredentialsForUser(
  pool: pg.Pool, userId: string,
): Promise<Credential[]> {
  return withSession(pool, { roleName: 'guardian', userId, childId: null }, async (q) => {
    const rows = await q(
      `SELECT credential_id, public_key_pem, sign_count, user_id
         FROM webauthn_credential WHERE user_id = $1`,
      [userId],
    );
    return rows.map((r: any): Credential => ({
      credentialId: r.credential_id, publicKeyPem: r.public_key_pem,
      signCount: Number(r.sign_count), userId: r.user_id,
    }));
  });
}

/**
 * System-scoped, deliberately, unlike every other accessor in this section:
 * at LOGIN the caller presents a bare credentialId with no session yet to
 * scope a guardian-owned lookup to — resolving "whose credential is this" IS
 * the identity-resolution step, not a data-access decision gated behind one.
 * webauthn_credential's migration grants `system` a narrow, explicitly-
 * justified lookup policy for exactly this reason, alongside (never instead
 * of) the guardian-owns-her-own-row policy every other function in this file
 * runs under. Returns null on no match rather than throwing — an unknown
 * credential is an ordinary, expected outcome of a login attempt, not an
 * error condition.
 */
export async function webauthnCredentialById(
  pool: pg.Pool, credentialId: string,
): Promise<Credential | null> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT credential_id, public_key_pem, sign_count, user_id
         FROM webauthn_credential WHERE credential_id = $1`,
      [credentialId],
    );
    if (!rows.length) return null;
    const r = rows[0];
    return { credentialId: r.credential_id, publicKeyPem: r.public_key_pem,
              signCount: Number(r.sign_count), userId: r.user_id };
  });
}

/**
 * Same system-scoped justification as webauthnCredentialById() immediately
 * above — part of the same pre-session login ceremony, called only AFTER
 * auth.ts's verifyAssertion() has already independently proven possession of
 * the private key for this exact credential (its own signCount-replay
 * check), so by the time this runs the caller is not a stranger, only not
 * yet holding an ISSUED session token (issueSession happens after this).
 *
 * A real TOCTOU, found and fixed here: this used to be an UNCONDITIONAL
 * `UPDATE ... SET sign_count = $2`, with no compare against the row's CURRENT
 * value. verifyAssertion()'s own replay check only ever sees a SNAPSHOT of
 * sign_count read moments earlier by webauthnCredentialById() — two truly
 * concurrent login attempts (e.g. a cloned authenticator used at the same
 * moment as the real one) that both read the same stale stored count and
 * both present the same next signCount both pass that snapshot check, and an
 * unconditional write here would let BOTH persist and BOTH be issued a
 * session — exactly the "bearer token that can be replayed forever" auth.ts's
 * own header says this mechanism exists to prevent.
 *
 * Fixed the same way consumeChallenge() above closes its own TOCTOU: the
 * comparison moves INTO the UPDATE's WHERE clause, so it is checked against
 * the row's value at the moment this exact statement acquires the row's
 * write lock, not a value read by an earlier, separate statement. Two
 * concurrent calls with the same `newSignCount` can both START, but Postgres
 * serializes them on the row: the first to acquire the lock sees the
 * pre-update value and its WHERE matches; the second, after waiting for the
 * first's lock to release, re-evaluates WHERE against the row the first one
 * just wrote and finds it no longer matches, updating zero rows.
 *
 * `$2 = 0` bypasses the comparison entirely rather than being folded into
 * `sign_count < $2` (which `0 < 0` would always fail): this app's real
 * authenticators (Android platform/synced passkeys, see WebAuthnBridge.kt's
 * own header) commonly report signCount=0 on every genuine login by design —
 * verifyAssertion() already treats "both incoming and stored are 0" as
 * "this authenticator does not support a counter, don't enforce one", and
 * this write path has to agree with that or every second real login from
 * such a device would start silently failing the CAS.
 *
 * Returns whether the write actually took effect — the caller MUST treat
 * `false` as a failed login (the race this function exists to lose safely),
 * not as an ignorable side channel.
 */
export async function updateWebauthnSignCount(
  pool: pg.Pool, credentialId: string, newSignCount: number,
): Promise<boolean> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `UPDATE webauthn_credential
          SET sign_count = $2
        WHERE credential_id = $1 AND ($2 = 0 OR sign_count < $2)
        RETURNING sign_count`,
      [credentialId, newSignCount],
    );
    return rows.length === 1;
  });
}

/**
 * db/migrations/0010_availability.sql. weekday is 0=Sunday..6=Saturday,
 * matching packages/delivery-engine/src/materialize.ts's own convention
 * (`DateTime...weekday % 7  // Sun=0`) rather than Luxon's native ISO
 * weekday — see the migration's own header for why.
 */
export interface AvailabilityWindowInput {
  weekday: number;
  startLocal: string;   // 'HH:mm'
  endLocal: string;     // 'HH:mm'
  note?: string | null;
}

export interface AvailabilityWindow extends AvailabilityWindowInput {
  guardianId: string;
  /** app_user.display_name at read time — for rendering a co-guardian's
   *  windows as "Dad", not a bare uuid. Not stored on the row itself. */
  guardianName: string;
}

/**
 * PUT /v1/me/availability — the calling guardian's ENTIRE new set of
 * windows, replace-all semantics (routes.mjs hands this the whole array on
 * every call, never a delta; a guardian who wants to clear a day just omits
 * it from the array).
 *
 * Deliberately opens its OWN guardian-scoped session (`withSession`, not
 * `withSystemSession`) with `userId: guardianId` — unlike
 * activeCustodyOrderFor()/guardiansOfChild() above, which run as `system`
 * because their tables admit the right rows to *every* non-child/system
 * role. guardian_availability_window's own write policy
 * (guardian_availability_own, 0010's migration) is keyed on
 * `guardian_id = current_actor()`; running this under `system` would leave
 * current_actor() NULL and the DELETE would silently affect zero rows while
 * every INSERT's WITH CHECK failed outright. Opening the session as the
 * real guardian makes the RLS policy the thing actually enforcing "a
 * guardian can write only their own rows", not just a comment claiming it —
 * the same "second lock" reasoning db/DEPLOYMENT.md and every other
 * RLS-backed table in this file already follow.
 *
 * `guardianId` MUST be the authenticated caller's own principal.userId,
 * never anything from the request body — routes.mjs passes
 * `c.principal.userId`, the same A3 discipline childId gets from the path,
 * applied here to the guardian's own identity on an identity-only route.
 */
export async function setAvailabilityWindows(
  pool: pg.Pool, guardianId: string, windows: AvailabilityWindowInput[],
): Promise<void> {
  await withSession(pool, { roleName: 'guardian', userId: guardianId, childId: null },
    async (q) => {
      await q(`DELETE FROM guardian_availability_window WHERE guardian_id = $1`, [guardianId]);
      for (const w of windows) {
        await q(
          `INSERT INTO guardian_availability_window
             (guardian_id, weekday, start_local, end_local, note)
           VALUES ($1, $2, $3, $4, $5)`,
          [guardianId, w.weekday, w.startLocal, w.endLocal, w.note ?? null],
        );
      }
    });
}

/**
 * GET /v1/children/:childId/availability — every co-guardian's windows for
 * `childId` (via guardiansOfChild() above), INCLUDING the calling guardian's
 * own rows: the caller is herself one of `childId`'s guardians, so her own
 * windows come back in the same list rather than needing a second call.
 * System role, mirroring activeCustodyOrderFor()'s own reasoning: the route
 * handler's real A3 childId-from-path + `can()` check already gated this
 * call before it runs (see guardian_availability_window's policy 4 in
 * 0010's migration for why that makes a system-role read here safe, not a
 * widening of access).
 *
 * guardiansOfChild() now returns `{ userId }[]` (merged shape, see its own
 * header) rather than the bare `string[]` this function originally assumed
 * — mapped here rather than changing the query below, which wants a plain
 * uuid array for its `= ANY($1::uuid[])` clause.
 */
export async function availabilityFor(pool: pg.Pool, childId: string): Promise<AvailabilityWindow[]> {
  const guardianIds = (await guardiansOfChild(pool, childId)).map(g => g.userId);
  if (!guardianIds.length) return [];
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT w.guardian_id, w.weekday,
              to_char(w.start_local, 'HH24:MI') AS start_local,
              to_char(w.end_local,   'HH24:MI') AS end_local,
              w.note, u.display_name AS guardian_name
         FROM guardian_availability_window w
         JOIN app_user u ON u.id = w.guardian_id
        WHERE w.guardian_id = ANY($1::uuid[])
        ORDER BY w.guardian_id, w.weekday, w.start_local`,
      [guardianIds],
    );
    return rows.map((r: any): AvailabilityWindow => ({
      guardianId: r.guardian_id,
      guardianName: r.guardian_name,
      weekday: r.weekday,
      startLocal: r.start_local,
      endLocal: r.end_local,
      note: r.note,
    }));
  });
}

/**
 * db/migrations/0017_child_theme_preference.sql. Wire names match
 * client/lib/theme.dart's `AppTheme.toWire()`/`fromWire()` exactly (both
 * enums' own `.name`) -- `null` on either field means no guardian has ever
 * Applied a theme for this child (the migration's own `theme_preference_
 * complete_or_absent` CHECK guarantees these two are never independently
 * null/non-null). Collapsing that absence to `classic`/`light` is
 * deliberately NOT this function's job -- server/routes.mjs's handler
 * returns the raw `{themePalette, themeBrightness} | null` shape as-is, and
 * client/lib/theme.dart's `AppTheme.fromWire()` is the one place that
 * fail-closed default is applied, so a family that has genuinely never
 * chosen stays honestly distinguishable from one that chose classic/light
 * on purpose.
 */
export interface ChildTheme {
  themePalette: string;
  themeBrightness: string;
}

/**
 * GET /v1/children/:childId/theme -- system role, mirroring
 * activeCustodyOrderFor()/availabilityFor()'s own reasoning: the route
 * handler's real A3 childId-from-path + can('settings', ...) check already
 * gated this call before it runs (0017's own child_theme_system_read policy
 * exists for exactly this call).
 */
export async function themeFor(pool: pg.Pool, childId: string): Promise<ChildTheme | null> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT theme_palette, theme_brightness
         FROM child_theme_preference
        WHERE child_id = $1 AND theme_palette IS NOT NULL`,
      [childId],
    );
    if (!rows.length) return null;
    const r = rows[0];
    return { themePalette: r.theme_palette, themeBrightness: r.theme_brightness };
  });
}

/**
 * PUT /v1/children/:childId/theme -- upsert, one row per child. Deliberately
 * opens its OWN guardian-scoped session (`withSession`, not
 * `withSystemSession`) with `userId: guardianId`, the exact same reasoning
 * setAvailabilityWindows() above already documents: 0017's own
 * child_theme_guardian_edge policy is keyed on `actor_has_edge(child_id)`,
 * evaluated against `current_actor()` -- running this as `system` would
 * leave that NULL and the INSERT's WITH CHECK would fail outright for
 * every caller, guardian or not. Opening the session as the real guardian
 * makes RLS the thing actually enforcing "a guardian with a live edge can
 * write", not just a comment claiming it.
 *
 * `guardianId` MUST be the authenticated caller's own principal.userId,
 * never anything from the request body -- routes.mjs passes
 * `c.principal.userId`, the same A3 discipline childId gets from the path.
 */
export async function setChildTheme(
  pool: pg.Pool, guardianId: string, childId: string, theme: ChildTheme,
): Promise<void> {
  await withSession(pool, { roleName: 'guardian', userId: guardianId, childId: null },
    async (q) => {
      await q(
        `INSERT INTO child_theme_preference (child_id, theme_palette, theme_brightness, updated_at)
         VALUES ($1, $2, $3, now())
         ON CONFLICT (child_id) DO UPDATE
           SET theme_palette = EXCLUDED.theme_palette,
               theme_brightness = EXCLUDED.theme_brightness,
               updated_at = now()`,
        [childId, theme.themePalette, theme.themeBrightness],
      );
    });
}

/**
 * db/migrations/0018_call_log.sql — the real backing for security.ts's own
 * RESIDUAL_RISKS claim that call metadata is retained. `system` role for
 * both the insert and the later update below: unlike setChildTheme() above,
 * this table's own RLS (call_log_system_all, 0018) grants system role ALL,
 * not a guardian-actor-scoped policy — the route's real can('call', ...)
 * check (server/routes.mjs) already gated this write before it runs, so
 * this is not a client-reachable widening, the same reasoning themeFor()'s
 * own system-role read already documents.
 *
 * `id` MUST be session-runtime's own createSession().id (routes.mjs passes
 * `session.id` verbatim) — the same identifier server/routes.mjs's real
 * call-start response and notifyDevices()'s own `ref` field already use,
 * not a second, redundant one minted here.
 */
export async function recordCallStart(pool: pg.Pool, input: {
  id: string; childId: string; startedBy: string; participantIds: string[];
  roomName: string; ladderStep: string; recorded: boolean; rang: boolean;
}): Promise<void> {
  await withSystemSession(pool, async (q) => {
    await q(
      `INSERT INTO call_log
         (id, child_id, started_by, participant_ids, room_name, ladder_step, recorded, rang)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [input.id, input.childId, input.startedBy, input.participantIds,
       input.roomName, input.ladderStep, input.recorded, input.rang],
    );
  });
}

/**
 * server/routes.mjs's call-end route — sets `ended_at` on the exact row
 * recordCallStart() above created. Idempotent by design (matches endSession
 * ()'s own doc comment in packages/transport/src/push.ts: "both parties
 * hanging up simultaneously produces two calls for one room; the second
 * must be a no-op, not an error") — `WHERE ended_at IS NULL` makes a second
 * call a real, harmless no-op UPDATE of zero rows rather than overwriting an
 * already-real end time with a later, wrong one. Returns whether this call
 * was the one that actually recorded the end, so the route can distinguish
 * "you ended it" from "it was already ended" without a separate SELECT.
 */
export async function recordCallEnd(
  pool: pg.Pool, childId: string, sessionId: string,
): Promise<boolean> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `UPDATE call_log SET ended_at = now()
        WHERE id = $1 AND child_id = $2 AND ended_at IS NULL
        RETURNING id`,
      [sessionId, childId],
    );
    return rows.length > 0;
  });
}

/**
 * db/migrations/0011_account_deletion.sql — account deletion, for real.
 * MASTERFILE §2.10, §2.11, §9.8, prohibition P8.
 * client/lib/deletion_screen.dart's `whatDeletionKeeps` / `whatDeletionRemoves`
 * constants ARE the spec (see that file's own header); this is the one place
 * that spec becomes a database transaction.
 *
 * Deactivation, never row deletion — the app_user row itself is left in
 * place (message_log.author_id and a delivered delivery_intent.sender_id
 * both reference it), only:
 *   - delivery_intent rows this user AUTHORED that are NOT in a delivered
 *     state ('pending' | 'ready' | 'expired' | 'revoked' — the schema's own
 *     state CHECK, db/migrations/0001_phase0_init.sql) are removed. 'delivered'
 *     and 'opened' both mean the child already has it (routes.mjs's own inbox
 *     query treats them identically: `state IN ('delivered','opened')`), so
 *     those, and only those, survive untouched.
 *   - every pin_credential / webauthn_credential / auth_challenge row for
 *     this user is removed (the login itself goes).
 *   - every device_token row this user OWNS (owner_user_id = userId,
 *     0012_push_device_token.sql) is removed too — added after the round-2
 *     audit's SEC-01: without this, a deactivated guardian's already-
 *     registered devices kept receiving push indefinitely, since nothing
 *     else in the system ever revisits device_token once a row is written.
 *     Run as 'system' (see below), which device_token_system_prune already
 *     grants unrestricted DELETE for — the same policy removeDeviceTokenSystem()
 *     uses to reap dead tokens.
 *   - app_user.deactivated_at is set.
 * All five in ONE transaction (withSession's BEGIN/COMMIT/ROLLBACK) so a
 * partial failure cannot half-delete an account.
 *
 * NOT done here, honestly: sessions in this codebase are signed, not stored
 * (see auth.ts's own header) — there is no session table to invalidate, so an
 * already-issued token remains cryptographically valid until its own short
 * TTL (SESSION_TTL_MS, 1h) naturally expires, even after this call returns.
 * deletion.test.mjs's own section D asserts this as a KNOWN GAP rather than
 * leaving it untested: a pre-deactivation token still authenticates ordinary
 * reads (GET /v1/me, 200) for the rest of its TTL, and that is unchanged by
 * anything below — building a real server-side session/deny-list to close it
 * generally is still out of scope for this pass, same as before.
 *
 * What IS newly closed (SEC-01's other half): a deactivated guardian could
 * previously use that same still-valid token to REGISTER A NEW device_token
 * during the TTL window — not just keep an old one, but grow fresh push
 * surface after deactivating. registerDeviceToken() below now checks
 * deactivated_at itself and refuses, mirroring server/index.mjs's devLogin
 * gate rather than waiting on a general session revocation mechanism that
 * doesn't exist. Narrower than "block every action a stale token can take,"
 * but it's the one action that matters here: creating new delivery capacity,
 * not merely retaining old capacity for a bounded hour.
 *
 * `callerRoleName` defaults to 'guardian' — the only non-child, non-system
 * top-level principal role this codepath can ever see (server/routes.mjs's
 * POST /v1/me/delete handler rejects a null `principal.userId` before this
 * is ever called, and readSession's own invariant means a 'child' principal
 * never has a userId to pass here). It matters, not just documentation:
 * pin_credential's own RLS (0004_auth_and_reaper.sql) hides
 * 'guardian_escalation' rows from a session whose role reads as 'child', so
 * running this under the wrong role would make the credential cleanup below
 * silently delete nothing instead of failing loudly — hence the explicit
 * guard just below rather than trusting every caller to pass it right.
 */
export interface DeactivationResult {
  userId: string;
  cancelledDeliveryIntents: number;
  removedPinCredentials: number;
  removedWebauthnCredentials: number;
  removedWebauthnChallenges: number;
  removedDeviceTokens: number;
}

export async function deactivateAccount(
  pool: pg.Pool,
  userId: string,
  callerRoleName: string = 'guardian',
): Promise<DeactivationResult> {
  if (!userId) throw new Error('deactivateAccount: userId required');
  if (callerRoleName === 'child') {
    throw new Error('deactivateAccount: a child role cannot deactivate an account — ' +
      'children have no login of their own to delete (§11)');
  }

  // Runs as 'system', not callerRoleName, once the child-caller precondition
  // above is satisfied: this transaction spans four tables whose RLS
  // policies don't agree on one non-system role. pin_credential/
  // webauthn_credential are owner-scoped (current_actor() = userId, still
  // satisfied — userId below is the real target, not null), app_user's own
  // policy admits 'system' explicitly (0011_account_deletion.sql), and
  // auth_challenge (0008_auth_credentials.sql) is system-only, full stop —
  // no non-system role can touch it at all. A caller-scoped session here
  // silently deletes 0 auth_challenge rows (RLS filters, doesn't error).
  return withSession(pool, { roleName: 'system', userId, childId: null }, async (q) => {
    // Row lock + existence/idempotency check first, `FOR UPDATE`: a
    // concurrent second call for the same user (a double-tap on the confirm
    // button) blocks on this row lock until the first transaction commits,
    // then sees deactivated_at already set and fails cleanly rather than
    // both transactions racing to "successfully" cancel the same rows.
    const existing = await q(
      `SELECT id, deactivated_at FROM app_user WHERE id = $1 FOR UPDATE`, [userId]);
    if (existing.length === 0) {
      throw Object.assign(new Error('deactivateAccount: no such app_user'),
        { code: 'account_not_found' });
    }
    if (existing[0].deactivated_at) {
      throw Object.assign(new Error('deactivateAccount: already deactivated'),
        { code: 'already_deactivated' });
    }

    // What goes: anything queued or banked but NOT YET DELIVERED.
    const cancelled = await q(
      `DELETE FROM delivery_intent
        WHERE sender_id = $1 AND state NOT IN ('delivered', 'opened')
        RETURNING id`, [userId]);

    // What goes: the login itself. pin_credential (0008_auth_credentials.sql)
    // is keyed by user_id alone — one PIN per guardian, no per-child rows to
    // exclude — so this WHERE clause already scopes to exactly this user's
    // own row, if any.
    const pins = await q(
      `DELETE FROM pin_credential WHERE user_id = $1 RETURNING user_id`, [userId]);
    const passkeys = await q(
      `DELETE FROM webauthn_credential WHERE user_id = $1 RETURNING credential_id`, [userId]);
    // webauthn_challenge was dropped and replaced by auth_challenge
    // (0008_auth_credentials.sql) — same "challenge" column, new table name.
    const challenges = await q(
      `DELETE FROM auth_challenge WHERE user_id = $1 RETURNING challenge`, [userId]);

    // SEC-01 fix — a deactivated guardian's already-registered devices stop
    // being valid push targets the moment this transaction commits, not
    // whenever notifyDevices() next happens to hit a dead-token error for
    // each one individually. device_token_system_prune (0012) grants
    // unrestricted DELETE to 'system', the role this whole call runs as.
    const deviceTokens = await q(
      `DELETE FROM device_token WHERE owner_user_id = $1 RETURNING id`, [userId]);

    // The row itself is NEVER deleted. RLS (0011_account_deletion.sql) has
    // no DELETE policy on app_user at all, so a stray "DELETE FROM app_user"
    // anywhere else in this codebase would be refused by Postgres itself,
    // not merely by convention — this UPDATE is the only mutation available.
    const deactivated = await q(
      `UPDATE app_user SET deactivated_at = now()
        WHERE id = $1 AND deactivated_at IS NULL
        RETURNING id`, [userId]);
    if (deactivated.length !== 1) {
      // Should be unreachable given the FOR UPDATE existence check above —
      // asserted anyway per this task's own "assert row counts" instruction.
      // A silent 0-row UPDATE here would mean the guardian is told their
      // account is gone while the database disagrees.
      throw new Error(`deactivateAccount: expected to deactivate exactly 1 app_user row, ` +
        `affected ${deactivated.length}`);
    }

    return {
      userId,
      cancelledDeliveryIntents: cancelled.length,
      removedPinCredentials: pins.length,
      removedWebauthnCredentials: passkeys.length,
      removedWebauthnChallenges: challenges.length,
      removedDeviceTokens: deviceTokens.length,
    };
  });
}

/**
 * packages/messaging/src/pipeline.ts's `materialize()` (via `captureMessage()`)
 * needs the child's real timezone timeline and day-part schedule as data
 * (`ChildCtx`) to resolve "next bedtime" to an actual instant. This is the
 * loader — the DB-shaped rows on the wire, turned into exactly the shape
 * `materialize()`/`ctxZone()` already consume, mirroring `edgesFor()`'s own
 * one-query-one-mapping shape. `null` is an honest absence: no such child.
 *
 * System role for the same reason `activeCustodyOrderFor` uses it — this is
 * context assembly the route handler needs before/alongside its own
 * caller-scoped session, not a second authorization pass.
 */
export async function childCtxFor(pool: pg.Pool, childId: string): Promise<ChildCtx | null> {
  return withSystemSession(pool, async (q) => {
    const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [childId]);
    if (!child.length) return null;

    const tzRows = await q(
      `SELECT tz, lower(valid)::text AS start, upper(valid)::text AS "end"
         FROM child_tz_interval WHERE child_id = $1 ORDER BY lower(valid)`,
      [childId],
    );
    // Only day-parts effective TODAY — mirrors day_part's own `effective
    // daterange` column; a day-part outside its effective window is not part
    // of her CURRENT schedule, and materialize() has no other way to exclude
    // a superseded one.
    const dpRows = await q(
      `SELECT kind, starts_local::text AS starts_local, ends_local::text AS ends_local,
              days_of_week, reachable
         FROM day_part
        WHERE child_id = $1 AND effective @> CURRENT_DATE`,
      [childId],
    );

    return {
      homeTz: child[0].home_tz,
      tzIntervals: tzRows.map((r: any) => ({ tz: r.tz, start: r.start, end: r.end })),
      dayParts: dpRows.map((r: any) => ({
        kind: r.kind,
        startsLocal: r.starts_local,
        endsLocal: r.ends_local,
        daysOfWeek: r.days_of_week,
        reachable: r.reachable,
      })),
    };
  });
}

/**
 * §16.1 #3 / §2.11 — raw export. "Free, unlimited, every tier" (deletion_screen
 * .dart's own button copy), backed for real for the first time here.
 * db/migrations/0006_court_tier.sql's `export_record` table has existed since
 * that migration landed with nothing writing to it; this is the first writer.
 *
 * SCOPING IS NOT DELEGATED ENTIRELY TO THE ROUTE LAYER -- and, as of the
 * certified-export merge, not delegated to it AT ALL: routes.mjs's
 * `GET .../export` registration serves both raw and certified export from
 * one handler and runs no coarse api.ts-layer `can()` check for either (see
 * that route's own comment for why one action string can't gate both kinds).
 * So this function runs the REAL, first-lock RBAC check itself, right below
 * -- `edgesFor()` + `can('export.raw', ...)`, the exact same call the route
 * layer used to make, now made here instead, so the per-edge
 * `scope['export.raw'] === false` override stays honored rather than
 * silently stopping being checked. `delivery_intent` and `media_artifact`
 * carry NO row-level security policy at all on top of that (see
 * db/DEPLOYMENT.md's own inventory: only `child_journal_entry`,
 * `pin_credential`, `expense`, `message_log`, `custody_order` have one), and
 * `message_log`'s own policy (`log_no_child`, 0006) blocks the `child` ROLE
 * but does not scope by `child_id` -- a guardian session that queried it
 * directly for the WRONG child would get that child's real rows back.
 * Postgres enforces P6/P7 here, never cross-child tenancy on these
 * particular tables; that is the app's job. So this function ALSO
 * re-derives "is the caller currently a live guardian of THIS child" a
 * second way, in SQL below, mirroring `guardianship`'s own shape rather than
 * trusting the `can()` check above alone -- the second lock `authorize.ts`'s
 * own header describes for `can()` itself, applied one layer deeper because
 * these two tables have no first lock of their own. Role is pinned to
 * `'guardian'` specifically in that SQL (not any edge) because
 * `authorize.ts`'s `ROLE_CAPS` only grants `'export.raw'` to that one role
 * -- a live `step_parent`/`sitter`/etc. or `coordinator` edge already fails
 * the `can()` check above for the same reason, so this mirrors that exactly
 * rather than being stricter for no documented reason.
 *
 * child_journal_entry IS queried below, unconditionally -- and for every
 * caller of this function (which requires a non-child, guardian principal;
 * see the throw just below) it returns ZERO rows, always, because
 * `journal_owner_only` (0001) grants read access to the owning child alone.
 * That is deliberately not special-cased away here: the guarantee comes from
 * Postgres actually refusing the guardian session the row, not from this file
 * remembering to leave the query out. P7 has no export-shaped exception.
 *
 * A CHILD PULLING HER OWN EXPORT (§21.2 rung 17, `authorizeExport()` in
 * packages/maturation/src/rungs.ts) IS NOT IMPLEMENTED HERE. Two real
 * blockers, not an oversight: (1) rungs.ts's own age gate
 * (`p.age < 17 -> not_yet_seventeen`) has no wiring anywhere server-side --
 * no route threads a child's age through, and `VerifiedPrincipal` does not
 * carry one; (2) `export_record.requested_by` is `NOT NULL REFERENCES
 * app_user(id)`, and a child principal has no `app_user` row at all (`auth.ts`
 * `readSession()`: a child token's `userId` is always `null`) -- there is no
 * honest id to write there. Faking either would be worse than refusing. A
 * child principal reaching this function is a server bug (routes.mjs's
 * handler is expected to reject it before this is ever called), so it throws
 * rather than silently returning an empty bundle.
 */
/**
 * One row of db/migrations/0018_call_log.sql, shaped for an export bundle —
 * shared verbatim between RawExportBundle (below) and
 * CertifiedExportResult (this file's certified-export half), so the two
 * kinds of export can never quietly drift into describing a call
 * differently. See RawExportBundle's own `callLog` field doc for the full
 * reasoning behind exactly these columns and no others.
 */
export interface CallLogEntry {
  id: string;
  startedBy: string;
  startedByName: string | null;
  participantIds: string[];
  ladderStep: string;
  recorded: boolean;
  rang: boolean;
  startedAt: string;
  endedAt: string | null;
}

export interface RawExportBundle {
  childId: string;
  childName: string | null;
  generatedAt: string;
  /**
   * Exactly one of requestedByUserId / requestedByChildId is non-null —
   * mirroring export_record's own requested_by / requested_by_child_id
   * split (0016_child_take_and_go.sql). A guardian-requested bundle
   * (rawExportBundleFor() below) carries requestedByUserId; the child's own
   * take-and-go bundle (takeAndGo() below) carries requestedByChildId.
   */
  requestedByUserId: string | null;
  requestedByChildId: string | null;
  /** Delivered/opened only — never a message still in flight or revoked. */
  delivered: Array<{
    id: string;
    payloadKind: string;
    senderId: string;
    senderName: string | null;
    state: string;
    materializedAt: string | null;
    /** null when payload_ref does not resolve to a media_artifact row. */
    artifact: {
      id: string;
      kind: string;
      storageKey: string;
      durationMs: number | null;
      captionKey: string | null;
      capturedAt: string;
      capturedTz: string;
      eraTag: string | null;
      preserved: boolean;
    } | null;
  }>;
  /** Always [] for the GUARDIAN callers this function actually serves — see
   *  the file-level comment on why the query still runs for real rather than
   *  being hardcoded empty. NOT always [] in general: takeAndGo() below is a
   *  second, child-facing caller of the shared assembleRawExportBundle()
   *  helper this interface also serves, and a child reading her OWN journal
   *  is exactly what journal_owner_only (0001) exists to allow — see that
   *  function's own header. */
  journalEntries: Array<{ id: string; body: string | null; mediaRef: string | null; createdAt: string }>;
  messageLog: Array<{ seq: number; authorId: string; at: string; body: string; prevHash: string; hash: string }>;
  /**
   * db/migrations/0018_call_log.sql — real call metadata, the audit's own
   * "single biggest finding" (CHANGELOG v0.49.35): session-runtime/src/
   * security.ts's RESIDUAL_RISKS table has claimed since before that pass
   * that "who called whom, when, for how long" is "Retained, because §14
   * court export needs it" — the table existed, but nothing ever actually
   * queried it FOR an export. This is that query.
   *
   * Metadata only, matching call_log's own column set — never content,
   * never location (P3), same discipline every other field in this bundle
   * already follows. `roomName` is deliberately excluded: an internal
   * signaling identifier, not part of "who called whom, when, for how
   * long," and not evidentiary — no other field in this bundle exposes an
   * internal routing/storage identifier without also being the payload the
   * export is actually about (contrast `storageKey` above, which IS the
   * artifact). `durationMs` is deliberately NOT computed here from
   * startedAt/endedAt: call_log has no stored duration column (the
   * migration's own header explains why — a call's real duration is only
   * known once it ends), and inventing one by subtracting two timestamps
   * would be synthesizing a field this schema does not actually have,
   * exactly what `delivered[].artifact.durationMs` above avoids by reading
   * a REAL `duration_ms` column instead. `startedAt`/`endedAt` round-trip
   * as plain `::text`, matching `materializedAt`/`capturedAt` above — NOT
   * the special `to_char(...)` format `loadMessageChain()` below uses,
   * because that format exists solely to reproduce `entryHash()`'s exact
   * input bytes for message_log's hash chain, and call_log has no hash
   * chain of its own to reproduce (0018's own header: "Deliberately NOT
   * append-only / hash-chained like message_log").
   *
   * `startedByName` resolves the single `started_by` FK, mirroring
   * `delivered[].senderName` above; `participantIds` (a real uuid[] column
   * — see 0018's own header on why it is a list, not a single column) is
   * left as raw ids, not resolved to names, since resolving a variable-
   * length array of names would need a second join this file has no
   * existing precedent for and the raw ids are still real, useful
   * identifiers for a reader cross-referencing the rest of the bundle.
   */
  callLog: CallLogEntry[];
}

/**
 * Shared by BOTH real callers of this bundle shape — rawExportBundleFor()
 * (a guardian pulling her child's export) and takeAndGo() (a child pulling
 * her OWN, further down this file) — so the actual assembly, serialization
 * and hashing logic exists in exactly one place, per this task's own
 * "reuse the export machinery, don't reinvent it" instruction. `q` is
 * whatever session the CALLER already opened (a guardian-scoped session for
 * rawExportBundleFor(); a system-scoped session for takeAndGo(), see that
 * function's own header for why) — this helper is not itself session-aware,
 * exactly like every other `q`-taking helper in this file.
 *
 * `journalRows` is supplied by the CALLER, not queried in here, because the
 * one table that differs between the two callers (child_journal_entry) needs
 * a DIFFERENT session role than everything else this helper reads:
 * journal_owner_only (0001) is satisfied only by an actual 'child'-role
 * session matching this exact child_id — 'system' does not satisfy it (it
 * checks `current_setting('app.role') = 'child'` literally, not "any
 * non-guardian role"), so a caller that wants real rows here must query them
 * itself, under its own short-lived child-scoped session, and hand the
 * result in. rawExportBundleFor() passes its own guardian-scoped query
 * result (always [], by construction — P7, see this file's header); it is
 * not special-cased away here, so the guarantee stays "Postgres actually
 * refused this," never "this code remembered to leave it out."
 *
 * message_log, unlike the journal, is NOT split this way: log_no_child
 * (0006_court_tier.sql) blocks the 'child' role specifically and admits
 * every OTHER role unconditionally — 'system' passes it exactly like
 * 'guardian' already does — so a single query against whatever `q` the
 * caller passed in is correct for both callers with no branching needed.
 * §21.7's own NOT_HERS_TO_DELETE comment (packages/maturation/src/rungs.ts)
 * is the reasoning this leans on for including it in the CHILD's own bundle
 * too, not just the guardian's: "She can have a copy of everything; she
 * cannot erase somebody else's record of their own conduct" — a copy, not
 * deletion rights, which is exactly what an export bundle is.
 *
 * call_log (0018_call_log.sql) joins this same single-query-against-
 * whatever-`q` shape for a DIFFERENT reason than message_log's: it carries
 * TWO policies, not one — `call_log_guardian_read` (real rows, gated by
 * `actor_has_edge(child_id)`, satisfied by rawExportBundleFor()'s own
 * guardian-scoped session below) and `call_log_system_all` (satisfied by
 * takeAndGo()'s system-scoped session) — no policy admits the 'child' role
 * at all (0018's own header: "the child never reads or writes this table
 * directly"). Both of this function's real callers are covered by ONE of
 * those two policies apiece, so — exactly like message_log — a single query
 * against whatever `q` was handed in is correct for both, with no
 * branching. This is the real backing for security.ts's own RESIDUAL_RISKS
 * claim that call metadata is "Retained, because §14 court export needs
 * it" (CHANGELOG v0.49.35) — the table existed and was written to since
 * that pass, but nothing before this queried it FOR an export; the claim
 * had no export-side implementation until now.
 */
/**
 * db/migrations/0018_call_log.sql, shaped as CallLogEntry — the ONE query
 * both assembleRawExportBundle() (below) and certifiedExportBundleFor()
 * (this file's certified-export half, further down) run, so a future
 * change to which columns an export shows can't accidentally update one
 * bundle kind and not the other. `u` resolves `started_by`'s display name,
 * mirroring the `delivered` query's own `sender_name` JOIN below;
 * `started_by` is NOT NULL (same as `delivery_intent.sender_id`), so an
 * INNER JOIN is safe here for the identical reason it is safe there.
 *
 * Correct under EITHER real caller's session — see this function's own
 * callers for which RLS policy admits which one (call_log_guardian_read
 * for a guardian-scoped `q`, call_log_system_all for a system-scoped one).
 */
async function loadCallLog(q: Query, childId: string): Promise<CallLogEntry[]> {
  const rows = await q(
    `SELECT cl.id, cl.started_by, u.display_name AS started_by_name,
            cl.participant_ids, cl.ladder_step, cl.recorded, cl.rang,
            cl.started_at::text, cl.ended_at::text
       FROM call_log cl
       JOIN app_user u ON u.id = cl.started_by
      WHERE cl.child_id = $1
      ORDER BY cl.started_at ASC`,
    [childId],
  );
  return rows.map((r: any): CallLogEntry => ({
    id: r.id,
    startedBy: r.started_by,
    startedByName: r.started_by_name ?? null,
    participantIds: r.participant_ids,
    ladderStep: r.ladder_step,
    recorded: r.recorded,
    rang: r.rang,
    startedAt: r.started_at,
    endedAt: r.ended_at ?? null,
  }));
}

async function assembleRawExportBundle(
  q: Query, childId: string,
  requester: { userId: string } | { childId: string },
  journalRows: any[],
): Promise<{ bundle: RawExportBundle; serialized: string; bundleHash: string }> {
  const childRows = await q(`SELECT display_name FROM child WHERE id = $1`, [childId]);

  const deliveredRows = await q(
    `SELECT di.id, di.payload_kind, di.sender_id, u.display_name AS sender_name,
            di.state, di.materialized_at::text,
            m.id AS artifact_id, m.kind AS artifact_kind, m.storage_key,
            m.duration_ms, m.caption_key, m.captured_at::text, m.captured_tz,
            m.era_tag, m.preserved
       FROM delivery_intent di
       JOIN app_user u ON u.id = di.sender_id
       LEFT JOIN media_artifact m ON m.id = di.payload_ref
      WHERE di.child_id = $1 AND di.state IN ('delivered', 'opened')
      ORDER BY di.materialized_at ASC NULLS LAST`,
    [childId],
  );

  const logRows = await q(
    `SELECT seq, author_id, at::text, body, prev_hash, hash
       FROM message_log WHERE child_id = $1 ORDER BY seq ASC`,
    [childId],
  );

  // Real call metadata (0018_call_log.sql) — see this function's own header
  // for why a single query against whatever `q` the caller passed in is
  // correct for both real callers, and loadCallLog()'s own header for why
  // this is the SAME query certifiedExportBundleFor() runs below.
  const callLogRows = await loadCallLog(q, childId);

  const bundle: RawExportBundle = {
    childId,
    childName: childRows[0]?.display_name ?? null,
    generatedAt: new Date().toISOString(),
    requestedByUserId: 'userId' in requester ? requester.userId : null,
    requestedByChildId: 'childId' in requester ? requester.childId : null,
    delivered: deliveredRows.map((r: any) => ({
      id: r.id,
      payloadKind: r.payload_kind,
      senderId: r.sender_id,
      senderName: r.sender_name ?? null,
      state: r.state,
      materializedAt: r.materialized_at ?? null,
      artifact: r.artifact_id ? {
        id: r.artifact_id,
        kind: r.artifact_kind,
        storageKey: r.storage_key,
        durationMs: r.duration_ms ?? null,
        captionKey: r.caption_key ?? null,
        capturedAt: r.captured_at,
        capturedTz: r.captured_tz,
        eraTag: r.era_tag ?? null,
        preserved: r.preserved,
      } : null,
    })),
    journalEntries: journalRows.map((r: any) => ({
      id: r.id, body: r.body ?? null, mediaRef: r.media_ref ?? null, createdAt: r.created_at,
    })),
    messageLog: logRows.map((r: any) => ({
      seq: Number(r.seq), authorId: r.author_id, at: r.at, body: r.body,
      prevHash: r.prev_hash, hash: r.hash,
    })),
    callLog: callLogRows,
  };

  // Real sha256 over the exact bytes a recipient would receive — see this
  // function's callers for why `serialized` (not just the hash) is what a
  // caller should persist/re-hash to verify.
  const serialized = JSON.stringify(bundle);
  const bundleHash = sha256Hex(serialized);
  return { bundle, serialized, bundleHash };
}

export type RawExportDenial = Deny | 'not_a_live_guardian';

export async function rawExportBundleFor(
  pool: pg.Pool,
  principal: Pick<VerifiedPrincipal, 'roleName' | 'userId' | 'childId'>,
  childId: string,
): Promise<
  | { ok: true; bundle: RawExportBundle; serialized: string; recordId: string; bundleHash: string }
  | { ok: false; reason: RawExportDenial }
> {
  if (principal.roleName === 'child') {
    // A CHILD PULLING HER OWN EXPORT THIS WAY (an ad-hoc, standalone pull,
    // independent of majority) is still not implemented — no route wires a
    // child caller into THIS function, and none should: rung 17's "her own
    // export, no guardian approval, from seventeen" is a narrower, separate
    // grant this pass does not build a standalone endpoint for. Her export
    // AT MAJORITY (§9.8.4) is real, as of this pass — see takeAndGo() below,
    // a deliberately separate function/route, not a child branch bolted onto
    // this guardian-shaped one (which still runs a live-GUARDIAN SQL check
    // a child can never satisfy — see below). routes.mjs's handler must
    // refuse a child caller before this exact function is ever reached.
    throw new Error(
      'rawExportBundleFor: child-self export is not implemented here (see ' +
      'takeAndGo() for the real, majority-gated child export path)');
  }
  if (!principal.userId) {
    throw new Error('rawExportBundleFor: non-child principal missing userId');
  }
  const requesterId = principal.userId;

  // RBAC — the "first lock," same can()-based check certifiedExportBundleFor()
  // runs for its own action, and for the same reason this function's own SQL
  // check below (kept as-is, not removed) does NOT by itself cover: routes.mjs
  // no longer runs a coarse api.ts-layer can() check for this route at all
  // (both raw and certified export are served from one registration that
  // can't be gated by a single action string — see that route's own comment),
  // so per-edge `scope['export.raw'] === false` overrides — real, and
  // previously enforced ONLY by that now-removed coarse check — would
  // otherwise silently stop being honored. can() is the single source of
  // truth for that toggle; re-implementing it in raw SQL here would risk the
  // exact drift this function's own header already warns against.
  const edges = await edgesFor(pool, requesterId);
  const rbac = can('export.raw', edges, childId, new Date());
  if (!rbac.allow) return { ok: false, reason: rbac.reason };

  return withSession(pool, principal, async (q) => {
    const live = await q(
      `SELECT 1 FROM guardianship
        WHERE child_id = $1 AND user_id = $2 AND role = 'guardian'
          AND closed_at IS NULL
          AND (expires_at IS NULL OR expires_at > now())
          AND restricted = false
          AND valid @> now()
        LIMIT 1`,
      [childId, requesterId],
    );
    if (!live.length) return { ok: false, reason: 'not_a_live_guardian' };

    // P7 — see the file-level comment. This is a real query against the real
    // table, not a hardcoded [], and it is expected to return zero rows for
    // every caller who can reach this line (a live guardian, never a child)
    // — journal_owner_only (0001) admits only an actual 'child'-role session
    // matching this child_id, which this guardian-scoped session is not.
    const journalRows = await q(
      `SELECT id, body, media_ref, created_at::text
         FROM child_journal_entry WHERE child_id = $1 ORDER BY created_at ASC`,
      [childId],
    );

    const { bundle, serialized, bundleHash } =
      await assembleRawExportBundle(q, childId, { userId: requesterId }, journalRows);

    const inserted = await q(
      `INSERT INTO export_record (child_id, requested_by, kind, was_free, bundle_hash)
       VALUES ($1, $2, 'raw', true, $3) RETURNING id::text`,
      [childId, requesterId, bundleHash],
    );

    return { ok: true, bundle, serialized, recordId: inserted[0].id, bundleHash };
  });
}

/**
 * §21.2 rung 17 / §9.8.4 / §21.7 — the child's OWN export, and the closure
 * that comes with it at majority. MASTERFILE calls this "the hardest button
 * anyone builds here" (§21.7) for the guardian-deletion feature this
 * function is a genuine mirror of — deactivateAccount() above is its closest
 * relative in this file: same shape (a `FOR UPDATE` idempotency lock, one
 * transaction, real row-count assertions, denial reasons returned rather
 * than guessed), same posture (never fake a success, never invent a softer
 * rail than the one this codebase already ships).
 *
 * WHAT THIS IS NOT, deliberately, and why it differs from deactivateAccount():
 * a guardian's account is DEACTIVATED (soft — her login dies, her queued
 * content is cancelled, but nothing of the CHILD's is touched, because it
 * was never the guardian's to lose). A child at majority is not "logging
 * out" of a family she is leaving unchanged behind her — §9.8.4 is explicit
 * that guardian READ ACCESS ENDS: every one of HER guardianship edges closes
 * (reason 'majority', already a valid value in guardianship's own
 * closed_reason CHECK since 0001 — this is the first writer of that value).
 * That is the "closure" half of "export + closure"; it is real custody
 * ending, not a login being revoked, because in this schema a child never
 * had a login to revoke in the first place (deactivateAccount()'s own guard,
 * a few functions up, says so for guardians; the symmetric fact for a child
 * is that there is no pin_credential/webauthn_credential/device_token
 * *login* row of hers to remove either — device_token rows she owns
 * (owner_child_id) are left untouched here, on purpose: they are HER
 * device's push registration, not a credential, and nothing about turning
 * eighteen makes her stop wanting her own tablet to notify her).
 *
 * REUSES the raw-export machinery rather than reinventing it, per this
 * feature's own brief: assembleRawExportBundle() above is the SAME function
 * rawExportBundleFor() calls for a guardian's pull — this is not a second,
 * parallel bundle-shaping implementation. Certified export is deliberately
 * NOT reused here: certifiedExportBundleFor()'s entire business rule
 * (annual free allowance vs. Court tier, §16.1 #3) is about a GUARDIAN's
 * legal-proceedings entitlement, has no meaning for a child taking her own
 * archive, and export_record.kind's own CHECK (0006) only ever admits
 * 'raw'|'certified' — this writes 'raw', matching what she is actually
 * getting: the same free, unlimited, full bundle a guardian's raw pull gets,
 * never gated by an allowance that was never about her.
 *
 * TWO SESSIONS, not one — an accepted, DOCUMENTED non-atomicity, same
 * posture registerDeviceToken()'s own cross-owner-conflict comment already
 * takes in this file, not a new kind of gap: journal_owner_only (0001) is
 * satisfied ONLY by an actual 'child'-role session matching this exact
 * child_id (see assembleRawExportBundle()'s own header) — 'system' cannot
 * read her journal — so her journal is read here, first, under a real
 * 'child'-role session, BEFORE the main 'system'-role transaction that does
 * the actual idempotency-checked mutation opens. A crash in the gap between
 * the two leaves nothing inconsistent on disk (the first session only ever
 * reads), at the cost of the bundle's journalEntries theoretically
 * reflecting a moment slightly before the rest of the bundle — the same
 * order of magnitude of honesty-over-perfection this file already accepts
 * elsewhere, not a security concern (nothing here decides WHETHER to grant
 * anything based on the journal read).
 *
 * export_record.requested_by_child_id (0016_child_take_and_go.sql) is what
 * makes the WRITE half of this possible at all — see that migration's own
 * header for why `requested_by` alone (NOT NULL REFERENCES app_user) could
 * never honestly name a child caller, and why export_record_no_child's RLS
 * is left untouched rather than loosened.
 */
export interface TakeAndGoResult {
  childId: string;
  handedOverAt: string;
  guardianshipsClosed: number;
  artifactsTransferred: number;
  journalEntriesTransferred: number;
  exportRecordId: string;
  bundle: RawExportBundle;
  serialized: string;
  bundleHash: string;
}

export async function takeAndGo(
  pool: pg.Pool, childId: string, now: Date = new Date(),
): Promise<{ ok: true; result: TakeAndGoResult } | { ok: false; reason: HandoverDenial }> {
  if (!childId) throw new Error('takeAndGo: childId required');

  // Her journal, read as HER — see this function's own header on why this
  // cannot be folded into the 'system' transaction below. Real rows, not the
  // always-[] a guardian caller of assembleRawExportBundle() gets — she is
  // the one caller who legitimately reaches journal_owner_only's own grant.
  const journalRows = await withSession(pool, { roleName: 'child', userId: null, childId },
    (q) => q(`SELECT id, body, media_ref, created_at::text
                 FROM child_journal_entry WHERE child_id = $1 ORDER BY created_at ASC`,
              [childId]));

  return withSystemSession(pool, async (q) => {
    // FOR UPDATE first, exactly deactivateAccount()'s own idempotency shape:
    // a double-tap on the confirm button blocks here until the first
    // transaction commits, then observes handed_over_at already set and
    // fails cleanly rather than two transactions racing to both "succeed" —
    // closing the same guardianship edges twice, or writing two export_record
    // rows for one irreversible event.
    const rows = await q(
      `SELECT id, birth_date::text, majority_age, handed_over_at::text, deceased_at::text
         FROM child WHERE id = $1 FOR UPDATE`, [childId]);
    if (!rows.length) {
      throw Object.assign(new Error('takeAndGo: no such child'), { code: 'child_not_found' });
    }
    const c = rows[0];

    // Real PRESERVED artifacts, queried — not estimated — for handover()'s
    // own `transferred.artifacts` count. `preserved = true` only, mirroring
    // compileYearBook()'s own reasoning (packages/archive/src/archive.ts):
    // "an unpreserved artifact is on a retention clock and may already be
    // gone" -- §9.8.4 is about her PRESERVED archive transferring, not a
    // count that includes ephemeral, still-in-flight media. media_artifact
    // carries no RLS (see rawExportBundleFor's own header on this table), so
    // a plain SELECT under this 'system' session sees every real row.
    const artifactRows = await q(
      `SELECT id, kind, storage_key AS "storageKey", captured_at::text AS "capturedAt",
              captured_tz AS "capturedTz", preserved, era_tag AS "eraTag", author_id AS "authorId"
         FROM media_artifact WHERE child_id = $1 AND preserved = true`, [childId]);
    const artifacts: HandoverArtifact[] = artifactRows.map((r: any) => ({
      id: r.id, childId, kind: r.kind, storageKey: r.storageKey, capturedAt: r.capturedAt,
      capturedTz: r.capturedTz, preserved: r.preserved, eraTag: r.eraTag, authorId: r.authorId,
    }));

    // packages/archive/src/archive.ts's handover() — the real, already-
    // tested (packages/ledger/test/phase3.test.mjs "P archive") business
    // rule: not_yet_of_age / already_handed_over / child_deceased, computed
    // from the SAME birth_date/majority_age this schema has carried since
    // 0001_phase0_init.sql. Reused, not reimplemented — this function does
    // not compare ages or diff dates itself anywhere.
    const child: HandoverChild = {
      id: c.id, birthDate: c.birth_date, majorityAge: c.majority_age,
      handedOverAt: c.handed_over_at, deceasedAt: c.deceased_at,
    };
    const h = handover(child, artifacts, journalRows.length, DateTime.fromJSDate(now));
    if (!h.ok) return { ok: false, reason: h.reason };

    const { bundle, serialized, bundleHash } =
      await assembleRawExportBundle(q, childId, { childId }, journalRows);

    const inserted = await q(
      `INSERT INTO export_record (child_id, requested_by_child_id, kind, was_free, bundle_hash)
       VALUES ($1, $2, 'raw', true, $3) RETURNING id::text`,
      [childId, childId, bundleHash],
    );

    // The closure itself. closure_has_reason (0001) requires closed_at and
    // closed_reason to be set together — this UPDATE always sets both, so
    // that CHECK is satisfied by construction, never raced.
    const closed = await q(
      `UPDATE guardianship SET closed_at = $2, closed_reason = 'majority'
        WHERE child_id = $1 AND closed_at IS NULL
        RETURNING id`,
      [childId, now.toISOString()]);

    const updated = await q(
      `UPDATE child SET handed_over_at = $2 WHERE id = $1 AND handed_over_at IS NULL
        RETURNING id`,
      [childId, now.toISOString()]);
    if (updated.length !== 1) {
      // Should be unreachable given the FOR UPDATE existence/idempotency
      // check above — asserted anyway, matching deactivateAccount()'s own
      // "never let the database silently disagree with what she was told."
      throw new Error(`takeAndGo: expected to hand over exactly 1 child row, ` +
        `affected ${updated.length}`);
    }

    return { ok: true, result: {
      childId,
      // `now.toISOString()` directly, not a round trip through Postgres's
      // own `::text` cast — matching every other client-facing timestamp
      // this file produces (rawExportBundleFor()'s `generatedAt`,
      // certifiedExportBundleFor()'s `attestation.at`), never Postgres's own
      // `timestamptz::text` format (space-separated, no 'T'), which nothing
      // else in this codebase hands to a client and no client here parses.
      handedOverAt: now.toISOString(),
      guardianshipsClosed: closed.length,
      artifactsTransferred: h.result.transferred.artifacts,
      journalEntriesTransferred: h.result.transferred.journalEntries,
      exportRecordId: inserted[0].id,
      bundle, serialized, bundleHash,
    } };
  });
}

/** What a NEW `intent_batch` row needs, when the caller is assembling one
 * (message banking, §9.5) rather than a single ad-hoc capture. */
export interface NewIntentBatch {
  label: string;
  reason?: 'deployment' | 'medical' | 'treatment' | 'travel' | 'custody_gap' | 'other';
  cadence: 'daily' | 'weekdays' | 'weekly' | 'custom';
  startsLocal: string;   // date, 'YYYY-MM-DD'
  endsLocal: string;
}

export interface PersistedCapture {
  artifactId: string;
  intentId: string;
  /** Non-null only when `opts.newBatch` was supplied, or the intent already
   * named an existing batch (message banking's later members). */
  batchId: string | null;
}

/**
 * packages/messaging/src/pipeline.ts's `captureMessage()` is pure — it
 * decides whether a message may be captured and computes the artifact/
 * intent rows, but writes nothing to Postgres. This is where its `ok: true`
 * output actually lands: one `media_artifact` row (the video — every
 * capture through this pipeline includes one; `kind` is hardcoded
 * `'video_msg'` in pipeline.ts, so there is no branch where the payload
 * arrives without media), one `delivery_intent` row (the schedule), and —
 * only when the caller passes `opts.newBatch`, i.e. is assembling a
 * message-banking run rather than a single reply — one new `intent_batch`
 * row the intent is filed under.
 *
 * `system` role: by the time this runs, `action: 'message'` has already been
 * the FIRST lock (packages/api/src/api.ts) and `captureMessage()`'s own
 * `can()` check has already been the SECOND (§5.17/§5.18) — this function
 * only ever receives an `ok: true` result. Mirrors `activeCustodyOrderFor`'s
 * own reasoning for the same role choice.
 *
 * HONEST GAP, not introduced by this function and not fixed by it:
 * `media_artifact`, `intent_batch`, and `delivery_intent` carry NO row-level
 * security at all (see db/migrations/0001_phase0_init.sql — unlike
 * `child_journal_entry`, `pin_credential`, `expense`, `custody_order`, none
 * of the three tables written here ever got an ENABLE/FORCE pass). Closing
 * that safely means auditing every existing reader of these tables (the
 * delivery sweep's system-role `claim_due_intents()`, GET .../inbox's
 * caller-scoped SELECT, the reaper's `artifacts_due_for_reaping()`) against a
 * new policy — its own migration and its own review, not a side effect of
 * adding one new write path. Flagged here rather than silently left implicit.
 */
export async function persistCapturedMessage(
  pool: pg.Pool,
  capture: { artifact: ArtifactRow; intent: Omit<IntentRow, 'payloadRef'> },
  opts: { newBatch?: NewIntentBatch } = {},
): Promise<PersistedCapture> {
  return withSystemSession(pool, async (q) => {
    const a = capture.artifact;
    const artifactRows = await q(
      `INSERT INTO media_artifact
         (child_id, author_id, author_child_id, kind, storage_key, duration_ms,
          caption_key, captured_at, captured_tz, era_tag, preserved, preserved_by,
          preserved_at, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8::timestamptz,$9,$10,$11,$12,
               $13::timestamptz,$14::timestamptz)
       RETURNING id`,
      [a.childId, a.authorId, a.authorChildId, a.kind, a.storageKey, a.durationMs,
       a.captionKey, a.capturedAt, a.capturedTz, a.eraTag, a.preserved, a.preservedBy,
       a.preservedAt, a.expiresAt],
    );
    const artifactId = artifactRows[0].id as string;

    const i = capture.intent;
    let batchId: string | null = i.batchId;
    if (opts.newBatch) {
      // intent_batch.sender_id stays NOT NULL REFERENCES app_user(id) —
      // message banking (§9.8.1) is a guardian-only capability, deliberately
      // untouched by 0021_child_message_sender.sql (see that migration's own
      // header). No real caller reaches this branch for a child-originated
      // capture today (server/routes.mjs's POST .../messages never passes
      // `opts.newBatch`), but failing loudly here — rather than letting a
      // future caller hit intent_batch's raw NOT NULL violation — keeps that
      // a clear, named error instead of an opaque Postgres one.
      if (!i.senderId) {
        throw new Error(
          'persistCapturedMessage: opts.newBatch requires an app_user sender ' +
          '(intent_batch.sender_id is NOT NULL) — a child-originated capture ' +
          '(senderChildId set) cannot start a batch.');
      }
      const b = opts.newBatch;
      const batchRows = await q(
        `INSERT INTO intent_batch
           (child_id, sender_id, label, reason, cadence, daypart,
            starts_local, ends_local)
         VALUES ($1,$2,$3,$4,$5,$6,$7::date,$8::date)
         RETURNING id`,
        [i.childId, i.senderId, b.label, b.reason ?? null, b.cadence,
         i.targetDaypart, b.startsLocal, b.endsLocal],
      );
      batchId = batchRows[0].id as string;
    }

    const intentRows = await q(
      `INSERT INTO delivery_intent
         (child_id, sender_id, sender_child_id, payload_kind, payload_ref,
          policy, target_local_date, target_daypart, batch_id, batch_seq,
          state, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6::delivery_policy,$7::date,$8,$9,$10,$11,
               $12::timestamptz)
       RETURNING id`,
      [i.childId, i.senderId, i.senderChildId, i.payloadKind, artifactId,
       i.policy, i.targetLocalDate, i.targetDaypart, batchId, i.batchSeq,
       i.state, i.expiresAt],
    );

    return { artifactId, intentId: intentRows[0].id as string, batchId };
  });
}

// --------------------------------------------------------- device tokens ---
/**
 * db/migrations/0012_push_device_token.sql — feeds packages/transport/src/
 * notify.ts's notifyDevices(). See that migration's own header for the
 * owner-column and dedupe-by-token reasoning; not repeated here.
 */
export type DeviceOwner = { userId: string; childId?: never }
                         | { childId: string; userId?: never };

export interface DeviceTokenRow {
  id: string;
  platform: Platform;
  token: string;
  /**
   * §8.11.4's real delivery channel, when the client reported one (0015).
   * NULL means unknown — see that migration's own comment for why this is
   * never defaulted to a guess at the storage layer. notify.ts resolves a
   * conservative, explicitly-commented fallback at SEND time instead.
   */
  channel: Channel | null;
}

/**
 * Registers (or re-registers) a device for push. `principal` is the SAME
 * shape withSession() takes — this function opens its own session scoped to
 * that principal, exactly like activeCustodyOrderFor()'s own `pool` +
 * separate-session pattern above, so RLS's device_token_insert_own /
 * device_token_update_own / device_token_select_own policies (0008) are what
 * actually enforce "a principal can only write, and see, their own device
 * rows," not application logic here.
 *
 * UPSERT on the token itself (device_token_token_key, the migration's own
 * unique index) — see that migration for why this, not a client device id,
 * is the dedupe key.
 *
 * `RETURNING id` here (and in unregisterDeviceToken's DELETE below) relies on
 * device_token_select_own existing — found the hard way, by testing against a
 * real database rather than assuming: Postgres's row-security model does NOT
 * let an INSERT/UPDATE/DELETE policy's own USING/WITH CHECK substitute for
 * SELECT visibility. Locating an existing row (UPDATE/DELETE) or returning a
 * freshly-written one (`RETURNING`) additionally requires that row to pass a
 * SELECT policy — with none present, UPDATE/DELETE match nothing at all and
 * INSERT...RETURNING hard-fails, regardless of what their own policy says.
 * 0008's own header has the full empirical trail; the fix was adding that
 * SELECT policy, scoped to own rows only, not routing around RETURNING here.
 *
 * CROSS-OWNER RE-REGISTRATION — a second real conflict found by testing, not
 * assumed. `ON CONFLICT (token) DO UPDATE` re-attributing a row to a NEW
 * owner (0008's own dedupe design: the physical device now belongs to
 * whoever's app instance just presented this exact token) needs to UPDATE a
 * row the CALLER does not own — and device_token_update_own's USING clause,
 * correctly, refuses that: "a principal can only write their own rows" and
 * "the same UPSERT can silently steal someone else's row" cannot both hold.
 * The fix is NOT loosening that policy (that would be the actual security
 * hole "own rows only" exists to prevent) — it's a two-step fallback, scoped
 * so the CALLER still never touches another owner's row directly: if the
 * caller-scoped upsert is blocked by RLS specifically (SQLSTATE 42501,
 * "row-level security policy" in the message — not any other permission
 * error), a SYSTEM-scoped step deletes the stale conflicting row (system's
 * own device_token_system_prune policy, the same one removeDeviceTokenSystem
 * uses), then the ORIGINAL caller-scoped insert is retried, now conflict-free.
 * A race between the delete and the retry (another registration landing in
 * between) surfaces as a real unique-constraint error on the retry rather
 * than a silent wrong result — narrow, honest, not pretended away.
 *
 * SEC-01 fix — a `deactivated_at` gate, adult callers only. deactivateAccount()
 * (this file) now removes an already-registered device the moment an account
 * deactivates, but that alone leaves the OTHER half of the round-2 audit's
 * finding open: the same still-valid session token (signed, not stored — see
 * that function's own header) could keep registering brand-new devices for
 * the rest of its TTL, growing fresh push surface after deactivation instead
 * of merely retaining old surface. Checked here, not centrally, because no
 * general session-revocation mechanism exists in this codebase to check it
 * FROM (deletion.test.mjs's own section D asserts that gap as known, not
 * silently assumed) — this mirrors server/index.mjs's devLogin gate exactly:
 * one sensitive mutation, one explicit check, same shape, same reasoning.
 * A child principal is skipped entirely: children have no login and no
 * deactivated_at concept of their own (deactivateAccount's own guard already
 * refuses a 'child' caller for the same reason).
 *
 * HONEST GAP, asserted not silently left implicit (round-2 audit's
 * adversarial verify caught this omission): the check below and the upsert
 * it guards are TWO SEPARATE transactions (this SELECT runs inside its own
 * withSystemSession; the upsert opens a fresh withSession further down) — no
 * lock is held across the gap between them. Unlike every OTHER check-then-act
 * sequence in this file (attemptPinFor's FOR UPDATE lock, consumeChallenge's
 * single atomic UPDATE, updateWebauthnSignCount's compare-in-the-WHERE-clause
 * below), this one is NOT closed. A deactivateAccount() call that commits in
 * the narrow window between this SELECT and the INSERT below is not observed
 * by either transaction, and a device_token row can still land for an
 * account that is deactivated by the time it commits. Left this way rather
 * than folded into one transaction: the exposure is one lingering token
 * until the next dead-token bounce (packages/transport/src/notify.ts's own
 * reap-on-send-failure path), not a session or standing-access grant — the
 * same order of magnitude as the already-accepted cross-owner-conflict race
 * a few lines above, not the WebAuthn case above in this file, which a
 * one-transaction fix WAS worth the complexity for.
 */
export async function registerDeviceToken(
  pool: pg.Pool,
  principal: Pick<VerifiedPrincipal, 'roleName' | 'userId' | 'childId'>,
  platform: Platform,
  token: string,
  /**
   * Optional (0015) — a caller that genuinely knows its own real §8.11.4
   * channel passes it; a caller that doesn't (still every Android client as
   * of v0.49.11 — see devices.ts's own header) omits it, and this stays
   * NULL rather than being guessed at here.
   */
  channel?: Channel | null,
): Promise<string> {
  if (principal.roleName === 'system') {
    throw new Error('registerDeviceToken: system role cannot own a device');
  }
  const isChild = principal.roleName === 'child';
  const ownerUserId = isChild ? null : principal.userId;
  const ownerChildId = isChild ? principal.childId : null;

  if (!isChild) {
    const [row] = await withSystemSession(pool,
      (q) => q(`SELECT deactivated_at FROM app_user WHERE id = $1`, [ownerUserId]));
    if (row?.deactivated_at) {
      throw Object.assign(
        new Error('registerDeviceToken: account is deactivated'),
        { code: 'account_deactivated' },
      );
    }
  }

  const upsert = () => withSession(pool, principal, async (q) => {
    const rows = await q(
      `INSERT INTO device_token (owner_user_id, owner_child_id, platform, token, channel, last_seen_at)
       VALUES ($1, $2, $3, $4, $5, now())
       ON CONFLICT (token) DO UPDATE
         SET owner_user_id  = EXCLUDED.owner_user_id,
             owner_child_id = EXCLUDED.owner_child_id,
             platform       = EXCLUDED.platform,
             -- COALESCE, not a bare overwrite: a re-registration call that
             -- doesn't know the channel (channel arg omitted -> NULL here)
             -- must never clobber an already-known value from an earlier
             -- call that did. Every current call site is deterministic per
             -- device (push_channel.dart always passes the same value for
             -- the same platform), so this is a no-op today — it's future
             -- defense for the day a real native-detection caller exists
             -- and might not always resolve one.
             channel        = COALESCE(EXCLUDED.channel, device_token.channel),
             last_seen_at   = now()
       RETURNING id`,
      [ownerUserId, ownerChildId, platform, token, channel ?? null],
    );
    return rows[0].id as string;
  });

  try {
    return await upsert();
  } catch (e: any) {
    const isRlsDenial = e?.code === '42501'
      && String(e?.message ?? '').includes('row-level security policy');
    if (!isRlsDenial) throw e;
    // The conflicting row belongs to a DIFFERENT owner. Free it as system,
    // then retry the exact same caller-scoped upsert — this time as a plain
    // insert, since the conflict is gone.
    await withSystemSession(pool, (q) => q(`DELETE FROM device_token WHERE token = $1`, [token]));
    return upsert();
  }
}

/**
 * Deletes ONE device row belonging to the calling principal. RLS's
 * device_token_delete_own policy (combined with device_token_select_own —
 * see registerDeviceToken's own comment above for why both are needed) means
 * a token belonging to someone else simply matches zero rows here —
 * silently, safely, not an error — rather than this function needing to
 * check ownership itself.
 */
export async function unregisterDeviceToken(
  pool: pg.Pool,
  principal: Pick<VerifiedPrincipal, 'roleName' | 'userId' | 'childId'>,
  token: string,
): Promise<boolean> {
  return withSession(pool, principal, async (q) => {
    const rows = await q(`DELETE FROM device_token WHERE token = $1 RETURNING id`, [token]);
    return rows.length > 0;
  });
}

/**
 * SYSTEM-ROLE ONLY. The sender (packages/transport/src/notify.ts) is the only
 * caller — device_token_system_read is the one RLS policy that admits this,
 * and it admits nothing else. NEVER expose this over the API to any
 * client-facing role: it is exactly the "list someone else's device tokens"
 * capability the migration's RLS comment says nothing but system should have.
 */
export async function deviceTokensFor(
  pool: pg.Pool, owner: DeviceOwner,
): Promise<DeviceTokenRow[]> {
  return withSystemSession(pool, async (q) => {
    const rows = 'userId' in owner
      ? await q(
          `SELECT id, platform, token, channel FROM device_token WHERE owner_user_id = $1`,
          [owner.userId])
      : await q(
          `SELECT id, platform, token, channel FROM device_token WHERE owner_child_id = $1`,
          [owner.childId]);
    return rows.map((r: any): DeviceTokenRow =>
      ({ id: r.id, platform: r.platform, token: r.token, channel: r.channel ?? null }));
  });
}

/**
 * SYSTEM-ROLE ONLY. Reaps a token FCM/APNs has just told notify.ts is
 * permanently dead (UNREGISTERED / Unregistered / BadDeviceToken) — the
 * reactive half of the dedupe strategy 0008's own header documents. Never
 * exposed over the API.
 */
export async function removeDeviceTokenSystem(pool: pg.Pool, id: string): Promise<boolean> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(`DELETE FROM device_token WHERE id = $1 RETURNING id`, [id]);
    return rows.length > 0;
  });
}

// ==================================================== certified export =====
/**
 * db/migrations/0006_court_tier.sql's `message_log` — the real, already
 * hash-chained, DB-trigger-enforced parent<->parent log — and
 * 0013_court_tier_flag.sql's `app_user.court_tier`. MASTERFILE §2.11, §16.1
 * #3. client/lib/court_export.dart's own header names the gap this closes:
 * a real, well-built UI with a real 1:1 port of ledger.ts's authorization
 * logic, and "no backend exists yet to actually assemble or transfer these
 * files." This is that backend, for the certified half only (raw export is
 * feature/raw-export's job, a sibling branch not present in this checkout).
 *
 * Every real primitive below is REUSED, not re-implemented: `can()`
 * (family-graph/authorize.ts) for "does this caller even hold export
 * standing over this child," `authorizeExport()`/`verifyChain()`/`certify()`
 * (ledger.ts) for the actual business rule and the actual cryptography. This
 * file only wires them to real rows.
 *
 * ---- WHY THE COARSE RBAC CHECK BELOW PASSES `{ court: true }` TO can() ----
 * `can()`'s own 'export.certified' branch (authorize.ts line ~154) is
 * unconditional: `!tier.court` denies with no awareness of §16.1 #3's annual
 * free allowance at all (see packages/family-graph/test/graph.test.mjs's own
 * H8 assertions, which assert exactly that, with no allowance exception —
 * that engine was never taught the allowance exists, and this file does not
 * change it: graph.test.mjs's contract must keep passing unmodified). If
 * this file called `can('export.certified', edges, childId, now, role,
 * { court: realCourtTierFlag })`, EVERY non-court-tier guardian would be
 * denied even their free first export, every time — can() has no way to
 * express "unless a free credit remains." That would make the free-annual
 * rule this whole feature exists to implement permanently unreachable.
 *
 * So the two questions are deliberately kept separate, exactly as
 * MASTERFILE's own principle §2.11 keeps them separate: `can()` here answers
 * only "does this edge exist, live, unrestricted, with export.certified role
 * capability" (the RBAC question — identical to what export.raw or any other
 * action would check); `authorizeExport()` below, called immediately after
 * with the REAL court_tier flag and REAL annual count, is the sole,
 * authoritative source of the tier/allowance decision and its precise
 * denial reason. Passing `{court:true}` here does not weaken enforcement —
 * a caller with no live edge to this child, a closed/expired/restricted
 * edge, or a role lacking export.certified capability is still refused
 * right here, before authorizeExport() ever runs.
 */
// Derived from authorize.ts's own `Deny`, minus the members that are
// structurally unreachable through the `can()` call below (P6/P7 never
// apply to 'export.certified'; ladder_none/observer_readonly only ever fire
// for actions in CONTACT/WRITES, which 'export.certified' is in neither of),
// plus `ExportDenial` (ledger.ts) — the reasons `authorizeExport()` itself can
// produce — and 'chain_broken', the one reason this file adds on top of that.
//
// NOTE on 'tier_required': `can()`'s OWN 'tier_required' member (from Deny)
// really is unreachable here, because the tier passed to `can()` below is
// forced true — see this function's header. That is a DIFFERENT source from
// `ExportDenial`'s 'tier_required', which is the literal
// `authorizeExport()` (ledger.ts:167) actually returns on every real denial
// once the annual free allowance is spent and the guardian lacks Court tier —
// read that function; there is no separate 'annual_allowance_used' branch in
// it, so that string is never produced by a live call despite being part of
// `ExportDenial`'s declared type. An earlier version of this type excluded
// 'tier_required' outright, conflating the two sources: that made this type
// narrower than what `authorizeExport()`'s real return value actually is,
// which is exactly the contract violation
// packages/db/test/court_export.test.mjs section B/D exists to catch — see
// that file's own assertions for the reachable value.
export type CertifiedExportDenial =
  | Exclude<Deny,
      'ladder_none' | 'observer_readonly' | 'P6_child_financial' | 'P7_journal_never'>
  | ExportDenial | 'chain_broken';

export type CertifiedExportResult =
  | {
      ok: true;
      free: boolean;
      chain: LogEntry[];
      attestation: Attestation;
      /**
       * Real call metadata (0018_call_log.sql), same shape and same query
       * pattern as RawExportBundle's own `callLog` field — see that
       * field's doc for the full reasoning. Deliberately NOT folded into
       * `chain`/`attestation`/`verifyChain()`/`certify()`: those exist
       * specifically to hash-chain-verify message_log, and call_log has no
       * hash chain of its own to verify (0018's own header: "Deliberately
       * NOT append-only / hash-chained like message_log") — reusing that
       * machinery for a table it was never designed to cover would be
       * exactly the kind of quiet contradiction MASTERFILE's own §5.21.3
       * warns against. It IS covered by `bundleHash` below, though: that
       * hash is computed over `{chain, attestation, callLog}` together, so
       * altering a call record after export is still detectable, just
       * through the bundle-level hash rather than message_log's own
       * per-entry chain.
       */
      callLog: CallLogEntry[];
      bundleHash: string;
      exportRecordId: string;
    }
  | { ok: false; reason: CertifiedExportDenial; faults?: ChainFault[] };

/**
 * `at` is a real timestamptz round-tripped as ISO-8601 with millisecond
 * precision + 'Z' (`to_char(... , 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`) — the
 * exact format `entryHash()` must see to reproduce the hash a writer
 * computed at INSERT time. Nothing in this codebase writes message_log rows
 * yet (handover_notes.dart's UI has no backend behind it either — a
 * separate, real gap this pass does not close, see this function's own test
 * fixtures for the one place that format is exercised end to end today).
 */
async function loadMessageChain(
  q: Query, childId: string,
): Promise<LogEntry[]> {
  const rows = await q(
    `SELECT seq, author_id,
            to_char(at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS at,
            body, prev_hash, hash
       FROM message_log WHERE child_id = $1 ORDER BY seq ASC`,
    [childId],
  );
  return rows.map((r: any): LogEntry => ({
    seq: Number(r.seq), childId, authorId: r.author_id, at: r.at,
    body: r.body, prevHash: r.prev_hash, hash: r.hash,
  }));
}

export async function certifiedExportBundleFor(
  pool: pg.Pool, requestedBy: string, childId: string, now: Date = new Date(),
): Promise<CertifiedExportResult> {
  // 1 · RBAC — the "first lock," identical in kind to every other action.
  // See this function's own header for why tier is forced true here.
  const edges = await edgesFor(pool, requestedBy);
  const rbac = can('export.certified', edges, childId, now, undefined, { court: true });
  if (!rbac.allow) return { ok: false, reason: rbac.reason as CertifiedExportDenial };

  return withSystemSession(pool, async (q) => {
    // 2 · the REAL business rule's REAL inputs — queried, never estimated.
    // Guardian-scoped, not (guardian, child)-scoped: see 0008's own comment
    // on why this does NOT reuse 0006's certified_exports_last_year() SQL
    // helper, which counts per (requested_by, child_id) and therefore
    // answers a narrower question than §16.1 #3 actually specifies.
    //
    // FOR UPDATE here, and BEFORE the count query, on purpose: without it, two
    // concurrent requests from the SAME guardian each open their own
    // transaction at the default READ COMMITTED isolation, each see
    // certifiedInLast12Months=0 before either has committed its own INSERT,
    // and both walk away with was_free=true — a real TOCTOU that defeats
    // §16.1 #3's one-free-per-rolling-year rule under nothing more exotic
    // than two browser tabs. count(*) can't itself carry FOR UPDATE (Postgres
    // rejects FOR UPDATE with an aggregate), so this locks the guardian's own
    // app_user row instead: a second transaction's FOR UPDATE on the same row
    // blocks here until the first COMMITs (or ROLLBACKs), so its own count
    // query below is guaranteed to run AFTER the first request's INSERT is
    // visible, never racing it. Per-guardian granularity, not a global lock —
    // two DIFFERENT guardians exporting concurrently lock different rows and
    // never block each other. See court_export.test.mjs's own concurrent-
    // request section (E) for the regression this closes.
    const tierRows = await q(
      `SELECT court_tier FROM app_user WHERE id = $1 FOR UPDATE`, [requestedBy]);
    const courtTier: boolean = tierRows[0]?.court_tier ?? false;

    const countRows = await q(
      `SELECT count(*)::int AS n FROM export_record
        WHERE requested_by = $1 AND kind = 'certified'
          AND created_at > now() - interval '12 months'`,
      [requestedBy],
    );
    const certifiedInLast12Months: number = countRows[0]?.n ?? 0;

    const auth = authorizeExport({
      kind: 'certified', childId, requestedBy, courtTier, certifiedInLast12Months,
    });
    if (!auth.ok) return { ok: false, reason: auth.reason };

    // 3 · the real chain, read, never assembled from a fixture.
    const chain = await loadMessageChain(q, childId);

    // 4 · verify for real. message_log's own triggers (0006) make a broken
    // chain structurally impossible to write via a normal INSERT/UPDATE —
    // this is defense-in-depth on top of that guarantee, not decoration; see
    // packages/db/test/court_export.test.mjs for the one way this suite can
    // even construct a broken chain to prove this path (deliberately
    // disabling the trigger, since no ordinary write can produce one).
    const verification = verifyChain(chain);
    if (!verification.ok) {
      return { ok: false, reason: 'chain_broken', faults: verification.faults };
    }

    // 5 · real call metadata (0018_call_log.sql) — loadCallLog()'s own
    // header explains why this is the identical query
    // assembleRawExportBundle() runs for the raw-export half of this
    // feature, and why it is NOT run through verifyChain()/certify(): those
    // two exist to hash-chain-verify message_log specifically, and
    // call_log has no chain of its own to verify. `q` here is the
    // system-scoped session this whole function already opened
    // (withSystemSession above), which call_log_system_all (0018) admits
    // unconditionally — the RBAC "first lock" already ran, above, so this
    // is not a client-reachable widening, the same reasoning this
    // function's own header already gives for reading `app_user.court_tier`
    // and `export_record` under the same system session.
    const callLog = await loadCallLog(q, childId);

    const attestation = certify(chain, childId, now.toISOString());
    // Covers callLog too, not just {chain, attestation} — see
    // CertifiedExportResult's own `callLog` field doc for why folding it in
    // here (rather than into the message_log-specific chain/attestation
    // machinery) is the honest way to make a later edit to a call record
    // detectable without pretending call_log has a hash chain it doesn't.
    const bundleHash = sha256Hex(JSON.stringify({ chain, attestation, callLog }));

    const inserted = await q(
      `INSERT INTO export_record (child_id, requested_by, kind, was_free, head_hash, bundle_hash)
       VALUES ($1, $2, 'certified', $3, $4, $5)
       RETURNING id`,
      [childId, requestedBy, auth.free, attestation.headHash, bundleHash],
    );

    return {
      ok: true, free: auth.free, chain, attestation, callLog, bundleHash,
      exportRecordId: inserted[0].id,
    };
  });
}

/**
 * MASTERFILE §11, §8.5 — the guardian invitation flow, real create/read/
 * accept-decision/revoke. See `0014_guardian_invite.sql`'s own header for
 * the honest scope limit: this does NOT create a `guardianship` row and
 * cannot, because closing that loop needs an account-creation route this
 * codebase has never built for a brand-new guardian. `acceptGuardianInvite`
 * records a real decision; it is not, and must not become, a silent stand-in
 * for "and now she has access."
 */
export const INVITABLE_ROLES = [
  'guardian', 'trusted_adult', 'step_parent', 'sitter', 'coordinator',
] as const;
export type InvitableRole = typeof INVITABLE_ROLES[number];

export interface GuardianInvite {
  id: string;
  childId: string;
  invitedBy: string;
  invitedEmail: string;
  role: InvitableRole;
  label: string;
  createdAt: string;
  expiresAt: string;
  acceptedAt: string | null;
  revokedAt: string | null;
}

function rowToInvite(r: any): GuardianInvite {
  return {
    id: r.id, childId: r.child_id, invitedBy: r.invited_by, invitedEmail: r.invited_email,
    role: r.role, label: r.label, createdAt: r.created_at, expiresAt: r.expires_at,
    acceptedAt: r.accepted_at, revokedAt: r.revoked_at,
  };
}

/**
 * Trusts the caller (the route, `server/routes.mjs`) to have already
 * confirmed `invitedBy` holds a LIVE, unrestricted guardian edge to
 * `childId` — the same "route does the `can()`-shaped first lock, this
 * function is the second" split every other pool.ts function uses. There is
 * no `Action` for "invite" in `authorize.ts`'s enum (adding one would widen
 * that shared surface for a single caller), so this route checks the edge
 * directly rather than through `can()` — mirroring `kiosk-pin/verify`'s own
 * identity-scoped-handler posture in routes.mjs.
 */
export async function createGuardianInvite(
  pool: pg.Pool, invitedBy: string, childId: string,
  role: InvitableRole, label: string, invitedEmail: string,
): Promise<{ ok: true; invite: GuardianInvite } | { ok: false; reason: 'invalid_role' }> {
  if (!(INVITABLE_ROLES as readonly string[]).includes(role)) {
    return { ok: false, reason: 'invalid_role' };
  }
  return withSession(pool, { roleName: 'guardian', userId: invitedBy, childId: null }, async (q) => {
    const rows = await q(
      `INSERT INTO guardian_invite (child_id, invited_by, invited_email, role, label)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [childId, invitedBy, invitedEmail, role, label],
    );
    return { ok: true, invite: rowToInvite(rows[0]) };
  });
}

/**
 * The invited party has no session — no app_user row exists for them yet
 * (see 0014's header). Runs as `system`; the invite's own long, random,
 * single-purpose `id` is what stands in for a credential here, exactly as
 * `webauthnLoginChallenge`'s single-use challenge does for a not-yet-
 * authenticated login attempt. Never lists invites; only ever looks one up
 * by the id the caller was handed out of band.
 */
export async function getGuardianInvite(
  pool: pg.Pool, inviteId: string,
): Promise<GuardianInvite | null> {
  return withSystemSession(pool, async (q) => {
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1`, [inviteId]);
    return rows.length ? rowToInvite(rows[0]) : null;
  });
}

export type AcceptInviteError = 'not_found' | 'expired' | 'already_accepted' | 'revoked';

/**
 * Records a real decision. Does NOT create a `guardianship` row — see this
 * file's own header and 0014's migration header for why that would be
 * fabricating a security step (account creation) that does not exist.
 */
export async function acceptGuardianInvite(
  pool: pg.Pool, inviteId: string, now: Date,
): Promise<{ ok: true; invite: GuardianInvite } | { ok: false; reason: AcceptInviteError }> {
  return withSystemSession(pool, async (q) => {
    // FOR UPDATE: a double-tap on "accept" must not race two transactions
    // into both reading accepted_at IS NULL — same shape as
    // deactivateAccount()'s own idempotency lock above.
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1 FOR UPDATE`, [inviteId]);
    if (!rows.length) return { ok: false, reason: 'not_found' };
    const row = rows[0];
    if (row.revoked_at) return { ok: false, reason: 'revoked' };
    if (row.accepted_at) return { ok: false, reason: 'already_accepted' };
    if (new Date(row.expires_at) <= now) return { ok: false, reason: 'expired' };

    const updated = await q(
      `UPDATE guardian_invite SET accepted_at = $2 WHERE id = $1 RETURNING *`,
      [inviteId, now.toISOString()],
    );
    return { ok: true, invite: rowToInvite(updated[0]) };
  });
}

/**
 * Only 'not_found' and 'already_accepted' — NOT 'not_your_invitation'. RLS
 * scopes the SELECT below to `invited_by = byUserId` before this function
 * ever sees a row, so a different guardian's invite is indistinguishable
 * from no invite at all — the same non-distinguishing shape kiosk-pin/verify
 * already uses (there, for a different reason: not leaking which factor
 * failed). Unlike observer.ts's in-memory revoke(), which sees every
 * observer and so CAN return a real 'not_your_invitation', this one
 * genuinely cannot — declaring that reason here would be an unreachable
 * type, not an honest one.
 */
export type RevokeInviteError = 'not_found' | 'already_accepted';

/** Only the guardian who sent it may revoke — same rule as observer.ts's revoke(). */
export async function revokeGuardianInvite(
  pool: pg.Pool, inviteId: string, byUserId: string, now: Date,
): Promise<{ ok: true } | { ok: false; reason: RevokeInviteError }> {
  return withSession(pool, { roleName: 'guardian', userId: byUserId, childId: null }, async (q) => {
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1 FOR UPDATE`, [inviteId]);
    if (!rows.length) return { ok: false, reason: 'not_found' };
    if (rows[0].accepted_at) return { ok: false, reason: 'already_accepted' };

    // Idempotent, on purpose — RevokeInviteError has no 'already_revoked'
    // reason, so a second revoke of an already-revoked invite still
    // returns ok:true rather than an error. But idempotent must mean the
    // OBSERVABLE STATE doesn't change either, not just that no error is
    // thrown: without the `revoked_at IS NULL` guard this UPDATE used to
    // carry, a second call (a double-tap, or a client retry after a
    // timeout of unknown outcome — the exact race acceptGuardianInvite()'s
    // own FOR UPDATE lock above already exists to prevent on the accept
    // side) silently overwrote a real revocation instant with a later,
    // fabricated one. In a product whose own court-export feature exists
    // to produce a trustworthy record of exactly when access was revoked,
    // a rewritable revoked_at is a real integrity bug, not a cosmetic one.
    // The FOR UPDATE row lock already taken above is what makes this guard
    // race-free against a concurrent double-tap, not just single-threaded
    // logic.
    if (!rows[0].revoked_at) {
      await q(`UPDATE guardian_invite SET revoked_at = $2 WHERE id = $1`, [inviteId, now.toISOString()]);
    }
    return { ok: true };
  });
}

export type BootstrapInviteError =
  | 'not_found' | 'expired' | 'revoked' | 'not_accepted'
  | 'already_bootstrapped' | 'email_already_registered';

/**
 * The gap CHANGELOG v0.49.9 found and explicitly declined to invent an
 * answer for: "how does a passwordless account get created at all."
 *
 * Given an invite that has ALREADY been through the real POST .../accept
 * route (accepted_at IS NOT NULL — checked below, not re-derived from
 * expires_at alone), creates the invited party's FIRST app_user row and
 * hands back its id so the caller (server/routes.mjs) can mint a real
 * session via `Api.issueSessionToken()`. Does NOT touch webauthn_credential
 * or pin_credential at all, and does NOT create a guardianship row — see
 * this file's own header and 0014/0020's migration headers for why the
 * latter stays a real, separate, still-open gap this function does not
 * close.
 *
 * Single-use by construction, not just by this function's own already_
 * bootstrapped branch: 0020's bootstrap_columns_paired/bootstrap_needs_
 * accept CHECK constraints and its partial UNIQUE index on
 * bootstrap_user_id are the second lock behind it, the same "the DB
 * enforces it independently" posture this file's RLS-backed functions
 * already rely on everywhere else.
 *
 * Runs as `system`, same reasoning as acceptGuardianInvite(): the invited
 * party has no session yet — the invite's own long, random, ALREADY-
 * ACCEPTED id is what stands in for a credential here, one step later in
 * the same flow getGuardianInvite()/acceptGuardianInvite() already use it
 * for.
 */
export async function bootstrapGuardianInvite(
  pool: pg.Pool, inviteId: string, displayName: string, now: Date,
): Promise<
  | { ok: true; userId: string; childId: string }
  | { ok: false; reason: BootstrapInviteError }
> {
  return withSystemSession(pool, async (q) => {
    // FOR UPDATE — same double-tap protection acceptGuardianInvite() already
    // uses: two concurrent bootstrap calls against the SAME invite id must
    // not both observe bootstrapped_at IS NULL and both proceed to create a
    // second app_user row.
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1 FOR UPDATE`, [inviteId]);
    if (!rows.length) return { ok: false, reason: 'not_found' };
    const row = rows[0];
    // Revoked checked before not_accepted — a revoked-before-ever-accepted
    // invite (0014's own CHECK permits that state; acceptGuardianInvite()
    // itself refuses to accept a revoked one) is named the more specific,
    // more security-relevant 'revoked' rather than the merely incidental
    // 'not_accepted' it would also technically satisfy.
    if (row.revoked_at) return { ok: false, reason: 'revoked' };
    if (!row.accepted_at) return { ok: false, reason: 'not_accepted' };
    // Defense in depth, matching webauthnLoginVerify's own belt-and-
    // suspenders posture (server/index.mjs): acceptGuardianInvite() already
    // refuses to set accepted_at past expires_at, so this branch should be
    // unreachable through the real accept route — kept anyway so a future
    // bug in that OTHER function cannot silently turn into a live session
    // minted off a decision window that had already closed.
    if (new Date(row.expires_at) <= now) return { ok: false, reason: 'expired' };
    if (row.bootstrapped_at) return { ok: false, reason: 'already_bootstrapped' };

    // A guardian already invited to a second child — or anyone else whose
    // email happens to match an existing account — must sign in the
    // ordinary way. Minting a session for an EXISTING app_user row here, off
    // nothing but knowledge of an invite id, would be a real authentication
    // bypass of that account's own passkey, not an account bootstrap.
    // Refusing outright, rather than attaching to the existing row, is the
    // conservative reading of "first-time guardian" this route is scoped to
    // — see this function's own file header on the still-open question of
    // what a SECOND invite to an already-registered guardian should do.
    const existing = await q(`SELECT id FROM app_user WHERE email = $1`, [row.invited_email]);
    if (existing.length) return { ok: false, reason: 'email_already_registered' };

    // child_id is NOT NULL REFERENCES child(id) ON DELETE CASCADE — if this
    // invite row still exists, its child does too, so home_tz is always
    // real here. A real, precedented fallback (server/routes.mjs's own /now
    // handler already falls back to child.home_tz the same way, per its own
    // file header), not an invented one — no route anywhere in this
    // codebase yet lets a guardian set her OWN home_tz, first-time or not.
    const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [row.child_id]);

    let userId: string;
    try {
      const inserted = await q(
        `INSERT INTO app_user (email, display_name, home_tz)
         VALUES ($1, $2, $3) RETURNING id`,
        [row.invited_email, displayName, child[0].home_tz],
      );
      userId = inserted[0].id;
    } catch (e: any) {
      // The SELECT above closes the common case; this closes the race
      // between two DIFFERENT invites for the same email bootstrapping
      // concurrently — each holds FOR UPDATE on its OWN guardian_invite
      // row, so the lock above does not serialize them against each other.
      // Postgres's own app_user.email UNIQUE constraint is the actual,
      // final authority, same "the DB enforces it independently" posture
      // this file's RLS-backed functions already rely on for every other
      // invariant.
      if (e?.code === '23505') return { ok: false, reason: 'email_already_registered' };
      throw e;
    }

    await q(
      `UPDATE guardian_invite SET bootstrapped_at = $2, bootstrap_user_id = $3 WHERE id = $1`,
      [inviteId, now.toISOString(), userId],
    );
    return { ok: true, userId, childId: row.child_id };
  });
}

/** Assembled `DbPort` for `new Api(secret, dbPort)` — see packages/api/src/api.ts. */
export function dbPort(pool: pg.Pool): DbPort {
  return {
    edgesFor: (userId: string) => edgesFor(pool, userId),
    withSession: (principal, fn) => withSession(pool, principal, fn),
  };
}
