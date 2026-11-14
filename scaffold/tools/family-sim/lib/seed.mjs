// Seeding + cleanup, done with a Postgres ADMIN connection.
//
// THIS IS ITSELF A FINDING (see gaps): the server has no sign-up, no
// family-creation and no child-creation route, so the accounts, children and
// guardianship edges cannot be created through the API. The harness inserts
// them with SQL, exactly the way server/seed-dev.mjs and every route test do.
// Everything after this point goes through the real server routes.
import { NS } from './families.mjs';

const OPEN = `tstzrange(now() - interval '1 year', null)`;

function localHMS(ms, tz) {
  const f = new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
  return f.format(new Date(ms)).replace(/^24:/, '00:');
}

/**
 * A compressed "day" laid across REAL time. The server has no clock hook, so the
 * only way to cross day-part boundaries fast is to put the boundaries where the
 * real clock will be: virtual 15:00..21:30 maps onto [startMs, startMs + 6.5 * msPerVHour].
 */
export function dayPlan(startMs, msPerVHour) {
  const parts = [['after_school', 15, 17.5], ['dinner', 17.5, 19], ['wind_down', 19, 20.5], ['bedtime', 20.5, 21.5]];
  return { startMs, msPerVHour, parts,
    realAt: (vh) => startMs + (vh - 15) * msPerVHour,
    virtualAt: (ms) => 15 + (ms - startMs) / msPerVHour };
}
export const fmtVirtual = (vh) => {
  const h = Math.floor(vh), m = Math.floor((vh - h) * 60);
  return `${String(((h % 24) + 24) % 24).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
};

export async function cleanup(admin, { userIds, childIds }) {
  const fks = (await admin.query(`
    SELECT c.conrelid::regclass::text AS tbl, a.attname AS col, c.confrelid::regclass::text AS ref
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
     WHERE c.contype = 'f' AND array_length(c.conkey, 1) = 1
       AND c.confrelid IN ('public.child'::regclass, 'public.app_user'::regclass)`)).rows;
  await admin.query('BEGIN');
  try {
    await admin.query(`SET LOCAL session_replication_role = replica`);   // no triggers / FK actions: exact, order-free delete
    for (let pass = 0; pass < 2; pass++) {
      for (const f of fks) {
        const ids = f.ref === 'child' || f.ref === 'public.child' ? childIds : userIds;
        await admin.query(`DELETE FROM ${f.tbl} WHERE ${f.col} = ANY($1::uuid[])`, [ids]);
      }
    }
    await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [childIds]);
    await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [userIds]);
    await admin.query('COMMIT');
  } catch (e) { await admin.query('ROLLBACK'); throw e; }
}

export async function seedFamily(admin, fam, { plan = null } = {}) {
  for (const g of fam.guardians) {
    await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,$2,$3)`, [g.id, g.name, fam.tz]);
  }
  for (const k of fam.kids) {
    await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,$2,$3,$4)`,
      [k.id, k.name, k.birthDate, fam.tz]);
    for (const g of fam.guardians) {
      await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1,$2,'guardian','{}',${OPEN})`,
        [k.id, g.id]);
    }
    if (plan) {
      for (const [kind, a, b] of plan.parts) {
        const s = localHMS(plan.realAt(a), fam.tz), e = localHMS(plan.realAt(b), fam.tz);
        if (e <= s) continue;                      // wraps local midnight: skip, never write a bad range
        await admin.query(
          `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
           VALUES ($1,$2,$3,$4,'{0,1,2,3,4,5,6}', $5, '[2020-01-01,2099-01-01)')`,
          [k.id, kind, s, e, kind !== 'dinner']);
      }
    }
    if (fam.custody) {
      const d = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);
      await admin.query(
        `INSERT INTO custody_order (child_id, order_tz, pattern, anchor_local_date, exchange_time, effective_from)
         VALUES ($1,$2,'alternating_weeks',$3,'18:00',$4)`, [k.id, fam.tz, d(-3), d(-30)]);
    }
  }
  // One medication + one bag item on the first child: there is no create route for either (gap).
  const c0 = fam.kids[0].id;
  await admin.query(`INSERT INTO medication (id, child_id, name, dose, slots) VALUES ($1,$2,'Simdrops','1 tab','["am"]'::jsonb)`,
    [fam.medicationId, c0]);
  await admin.query(`INSERT INTO exchange_bag_item (id, child_id, label) VALUES ($1,$2,'sim-bag')`, [fam.bagItemId, c0]);
}

export const idSet = (fams) => ({
  userIds: fams.flatMap((f) => f.guardians.map((g) => g.id)),
  childIds: fams.flatMap((f) => f.kids.map((k) => k.id)),
});
export { NS };
