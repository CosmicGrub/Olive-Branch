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
import { DateTime } from 'luxon';
import { activeCustodyOrderFor, gamesEnabledFor, setGamesEnabledFor } from '../packages/db/src/pool.mjs';
import { sleepsUntilSideChange } from '../packages/custody/src/schedule.mjs';

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
      // db/migrations/0008_games_access.sql -- games dormant by default,
      // unlockable only by her own guardian. Real value for the child role
      // ONLY, via the loader's own child-scoped session (its RLS admits
      // nothing else) -- never a toggle here, ChildHome may only passively
      // render what this says (house convention: no settings affordance ever
      // on a child-facing surface).
      const gamesEnabled = c.principal.roleName === 'child'
        ? await gamesEnabledFor(pool, c.principal.childId)
        : undefined;
      return { body: {
        userId: c.principal.userId,
        childId: c.principal.childId,
        roleName: c.principal.roleName,
        escalated: c.principal.escalated,
        displayName: displayName ?? null,
        ...(gamesEnabled !== undefined ? { gamesEnabled } : {}),
      } };
    },
  });

  api.register({
    // No dedicated Action exists for "lock/unlock games" in
    // family-graph/src/authorize.ts, and none is needed: `settings` is
    // already guardian-only in ROLE_CAPS, exactly the shape this needs, so
    // it is reused rather than inventing a parallel capability `can()` was
    // never taught to recognize -- same reasoning routes.mjs's own /now
    // route already documents for calendar.view.
    method: 'PATCH', path: '/v1/children/:childId/games-access', action: 'settings',
    handler: async (c, q) => {
      // Defense in depth: api.ts's own authorize step hard-blocks a child
      // principal only for P6/P7-reserved reasons (see api.ts's own comment
      // on that branch) -- every other action, `settings` included, falls
      // through to the handler for a child acting inside her own scope. A
      // child-side write path here must be structurally impossible (house
      // convention), so this is an explicit first-line reject, not reliance
      // on setGamesEnabledFor()'s incidental null-userId fail-closed path.
      if (c.principal.roleName === 'child') {
        return { status: 403, body: { error: 'child_cannot_toggle_games' } };
      }
      const enabled = c.body?.enabled;
      if (typeof enabled !== 'boolean') {
        return { status: 400, body: { error: 'enabled_must_be_boolean' } };
      }
      const result = await setGamesEnabledFor(pool, c.childId, c.principal.userId, enabled);
      if (!result.allow) {
        return { status: 403, body: { error: result.reason } };
      }
      return { body: { childId: c.childId, gamesEnabled: result.enabled } };
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
}
