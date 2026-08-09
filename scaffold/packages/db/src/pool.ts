import pg from 'pg';
import type { VerifiedPrincipal } from '../../auth/src/auth.ts';
import { can, type Edge, type Deny } from '../../family-graph/src/authorize.ts';
import type { DbPort, Query } from '../../api/src/api.ts';
import type { Order } from '../../custody/src/schedule.ts';

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
 * db/migrations/0008_games_access.sql — games dormant by default, unlockable
 * only by the child's own guardian. House convention: no settings affordance
 * ever on a child-facing surface, so this loader is the ONLY thing a child
 * session ever calls — it runs as that child, which is precisely what
 * child_games_access's own RLS admits (read her own row, nothing else,
 * FOR SELECT only — see the migration).
 *
 * Absence of a row is a real, intended default, not a guess: the column
 * itself is `NOT NULL DEFAULT false`, so a child with no row yet (never
 * toggled by her guardian, or provisioned before this feature shipped) is
 * exactly as dormant as one with an explicit row. Returning anything else for
 * "no row" would be inventing data this system does not have.
 */
export async function gamesEnabledFor(pool: pg.Pool, childId: string): Promise<boolean> {
  return withSession(pool, { roleName: 'child', userId: null, childId }, async (q) => {
    const rows = await q(
      `SELECT games_enabled FROM child_games_access WHERE child_id = $1`,
      [childId],
    );
    return rows.length ? rows[0].games_enabled : false;
  });
}

export type GamesAccessDecision =
  | { allow: true; enabled: boolean }
  | { allow: false; reason: Deny };

/**
 * Guardian-authorized write — the ONLY way games access ever changes; there
 * is no child-side write path (see gamesEnabledFor's own doc, and the
 * migration's FOR SELECT-only child policy).
 *
 * Two independent locks, neither trusting the other:
 *  1. FIRST LOCK, here: the real `can()`/`edgesFor()` authorizer (§5.17) —
 *     reused, not reinvented. There is no dedicated Action for this in
 *     family-graph/src/authorize.ts, and none is needed: `settings` is
 *     already guardian-only in ROLE_CAPS, which is exactly the shape
 *     "lock/unlock games" needs. Rejects with the real `Deny` reason
 *     `can()` produced (no_edge, edge_closed, restricted, ...) before ever
 *     opening a write session — a guardian with no real edge to this child
 *     never reaches the database for this call.
 *  2. SECOND LOCK: the write itself runs `withSession` AS that guardian
 *     (never `system`), so child_games_access's own RLS
 *     (`actor_is_guardian_of`) independently re-checks the same live edge.
 *     A bug that let (1) pass incorrectly would still be caught here.
 */
export async function setGamesEnabledFor(
  pool: pg.Pool, childId: string, guardianUserId: string, enabled: boolean,
): Promise<GamesAccessDecision> {
  const edges = await edgesFor(pool, guardianUserId);
  const decision = can('settings', edges, childId, new Date(), 'guardian');
  if (!decision.allow) return { allow: false, reason: decision.reason };

  return withSession(pool, { roleName: 'guardian', userId: guardianUserId, childId: null },
    async (q) => {
      const rows = await q(
        `INSERT INTO child_games_access (child_id, games_enabled, updated_by, updated_at)
         VALUES ($1, $2, $3, now())
         ON CONFLICT (child_id) DO UPDATE
           SET games_enabled = EXCLUDED.games_enabled,
               updated_by    = EXCLUDED.updated_by,
               updated_at    = now()
         RETURNING games_enabled`,
        [childId, enabled, guardianUserId],
      );
      // RLS's own WITH CHECK would have raised, not returned zero rows, if the
      // second lock disagreed with the first — this length check is therefore
      // defensive, not the primary guard.
      if (!rows.length) return { allow: false, reason: 'no_edge' };
      return { allow: true, enabled: rows[0].games_enabled };
    });
}

/** Assembled `DbPort` for `new Api(secret, dbPort)` — see packages/api/src/api.ts. */
export function dbPort(pool: pg.Pool): DbPort {
  return {
    edgesFor: (userId: string) => edgesFor(pool, userId),
    withSession: (principal, fn) => withSession(pool, principal, fn),
  };
}
