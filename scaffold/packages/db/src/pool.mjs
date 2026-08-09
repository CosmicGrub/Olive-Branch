import pg from "pg";
function createPool(connectionString) {
  return new pg.Pool({ connectionString });
}
async function withSession(pool, principal, fn) {
  if (principal.roleName === "child" && !principal.childId) {
    throw new Error("withSession: child principal missing childId");
  }
  if (principal.roleName !== "child" && principal.roleName !== "system" && !principal.userId) {
    throw new Error(`withSession: ${principal.roleName} principal missing userId`);
  }
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(`SELECT set_config('app.role', $1, true)`, [principal.roleName]);
    await client.query(`SELECT set_config('app.child_id', $1, true)`, [principal.childId ?? ""]);
    await client.query(`SELECT set_config('app.user_id', $1, true)`, [principal.userId ?? ""]);
    const q = async (sql, params = []) => {
      const res = await client.query(sql, params);
      return res.rows;
    };
    const result = await fn(q);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {
    });
    throw e;
  } finally {
    client.release();
  }
}
function withSystemSession(pool, fn) {
  return withSession(pool, { roleName: "system", userId: null, childId: null }, fn);
}
async function edgesFor(pool, userId) {
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
      [userId]
    );
    return rows.map((r) => ({
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
      ladderStep: r.ladder_step
    }));
  });
}
async function activeCustodyOrderFor(pool, childId, nowLocalDate) {
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
      [childId, nowLocalDate]
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
      effectiveTo: r.effective_to
    };
  });
}
function dbPort(pool) {
  return {
    edgesFor: (userId) => edgesFor(pool, userId),
    withSession: (principal, fn) => withSession(pool, principal, fn)
  };
}
export {
  activeCustodyOrderFor,
  createPool,
  dbPort,
  edgesFor,
  withSession,
  withSystemSession
};
