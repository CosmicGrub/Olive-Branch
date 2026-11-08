/**
 * packages/db/test/domain_constraints.test.mjs — migration 0042, against a REAL
 * Postgres. Data-model audit S-D10 (day-part ordering/overlap), S-D20 (CHECKs,
 * time-zone names, enumerations) and the S-D10 end-to-end seam: childCtxFor()
 * hands the engine every day-part with its effective bounds, and the engine
 * resolves by the TARGET date.
 *
 * Needs a live, migrated Postgres (DATABASE_URL = the NOSUPERUSER app role,
 * ADMIN_DATABASE_URL = fixtures). Same posture as scheduler.test.mjs.
 */
import pg from 'pg';
import { DateTime } from 'luxon';
import { createPool, childCtxFor } from '../src/pool.mjs';
import { materialize } from '../../delivery-engine/src/materialize.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();
const pool = createPool(DATABASE_URL);
const CHILD = '5d5d5d5d-0042-4042-9042-000000000001';
const SENDER = '5d5d5d5d-0042-4042-9042-0000000000a1';

async function refused(sql, params = []) {
  await admin.query('SAVEPOINT s');
  try { await admin.query(sql, params); await admin.query('RELEASE SAVEPOINT s'); return null; }
  catch (e) { await admin.query('ROLLBACK TO SAVEPOINT s'); return e.constraint ?? e.code ?? e.message; }
}

await admin.query('DELETE FROM child WHERE id = $1', [CHILD]);
await admin.query('DELETE FROM app_user WHERE id = $1', [SENDER]);
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'D42','America/New_York')`, [SENDER]);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'C42','2016-04-02','America/New_York')`, [CHILD]);
await admin.query('BEGIN');

const dp = (kind, s, e, days, eff) => refused(
  `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
   VALUES ($1,$2,$3,$4,$5::smallint[],true,$6::daterange)`, [CHILD, kind, s, e, days, eff]);

// ---------------------------------------------------------------- day_part --
{
  const g = 'A day_part days_of_week';
  check(g, 'a day outside 0..6 is refused', await dp('bedtime', '20:00', '20:30', '{7}', '[2026-01-01,)'), 'day_part_days_valid');
  check(g, 'a negative day is refused', await dp('bedtime', '20:00', '20:30', '{-1,2}', '[2026-01-01,)'), 'day_part_days_valid');
  check(g, 'an empty set of days is refused', await dp('bedtime', '20:00', '20:30', '{}', '[2026-01-01,)'), 'day_part_days_valid');
  check(g, 'more than seven entries is refused', await dp('bedtime', '20:00', '20:30', '{0,1,2,3,4,5,6,0}', '[2026-01-01,)'), 'day_part_days_valid');
  check(g, 'a valid set is accepted', await dp('bedtime', '20:00', '20:30', '{0,1,2,3,4,5,6}', '[2026-01-01,2026-09-01)'), 'null');
}
{
  const g = 'B day_part overlap (EXCLUDE)';
  check(g, 'same kind, overlapping dates + days + time of day is refused',
    await dp('bedtime', '20:15', '20:45', '{3}', '[2026-06-01,2026-07-01)'), 'day_part_no_overlap');
  check(g, 'same kind, adjacent effective ranges (the schedule change) is accepted',
    await dp('bedtime', '21:00', '21:30', '{0,1,2,3,4,5,6}', '[2026-09-01,)'), 'null');
  check(g, 'same kind, same dates, disjoint weekdays is accepted',
    await dp('free', '10:00', '11:00', '{1,2}', '[2026-01-01,)'), 'null');
  check(g, 'same kind, same dates + weekdays, disjoint time of day is accepted',
    await dp('free', '14:00', '15:00', '{1,2}', '[2026-01-01,)'), 'null');
  check(g, 'same kind, overlapping time of day on one shared weekday is refused',
    await dp('free', '10:30', '11:30', '{2,3}', '[2026-01-01,)'), 'day_part_no_overlap');
  check(g, 'DIFFERENT kinds may overlap (the engine resolves that conservatively)',
    await dp('school', '10:30', '11:30', '{1,2}', '[2026-01-01,)'), 'null');
  check(g, 'a wrapping part (21:00 -> 06:30) conflicts with a same-kind late-evening part',
    (await dp('asleep', '21:00', '06:30', '{0,1,2,3,4,5,6}', '[2026-01-01,)')) === null &&
    (await dp('asleep', '22:00', '23:00', '{5}', '[2026-01-01,)')) === 'day_part_no_overlap', true);
}

// --------------------------------------------------------------- time zones --
{
  const g = 'C time-zone names';
  check(g, 'child.home_tz: a nonsense zone is refused',
    await refused(`UPDATE child SET home_tz = 'Mars/Phobos' WHERE id = $1`, [CHILD]), 'child_home_tz_valid');
  check(g, 'child.home_tz: a real IANA zone is accepted',
    await refused(`UPDATE child SET home_tz = 'Asia/Kolkata' WHERE id = $1`, [CHILD]), 'null');
  check(g, 'child.home_tz: UTC is accepted',
    await refused(`UPDATE child SET home_tz = 'UTC' WHERE id = $1`, [CHILD]), 'null');
  check(g, 'child.home_tz: empty string is refused',
    await refused(`UPDATE child SET home_tz = '' WHERE id = $1`, [CHILD]), 'child_home_tz_valid');
  check(g, 'child.home_tz: wrong case is refused (Luxon would reject it too)',
    await refused(`UPDATE child SET home_tz = 'america/new_york' WHERE id = $1`, [CHILD]), 'child_home_tz_valid');
  await admin.query(`UPDATE child SET home_tz = 'America/New_York' WHERE id = $1`, [CHILD]);
  check(g, 'child_tz_interval.tz: a bad zone is refused',
    await refused(`INSERT INTO child_tz_interval (child_id, tz, valid, source) VALUES ($1,'Nowhere/Land',tstzrange(now(), now() + interval '1 day'),'manual')`, [CHILD]),
    'child_tz_interval_tz_valid');
  check(g, 'child_tz_interval.tz: a good zone is accepted',
    await refused(`INSERT INTO child_tz_interval (child_id, tz, valid, source) VALUES ($1,'America/Chicago',tstzrange(now(), now() + interval '1 day'),'manual')`, [CHILD]), 'null');
  check(g, 'custody_order.order_tz: a bad zone is refused',
    await refused(`INSERT INTO custody_order (child_id, order_tz, pattern, anchor_local_date, exchange_time, effective_from)
                   VALUES ($1,'Bogus/Zone','2-2-3','2026-01-05','18:00','2026-01-01')`, [CHILD]), 'custody_order_tz_valid');
}

// ------------------------------------------------------------- enumerations --
{
  const g = 'D enumerations';
  const intent = (kind, daypart) => refused(
    `INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, target_daypart, expires_at)
     VALUES ($1,$2,$3,gen_random_uuid(),'at_daypart',$4, now() + interval '90 days')`, [CHILD, SENDER, kind, daypart]);
  check(g, 'an unknown payload_kind is refused', await intent('hologram', 'bedtime'), 'delivery_intent_payload_kind_known');
  check(g, 'an unknown target_daypart is refused', await intent('video_msg', 'teatime'), 'delivery_intent_target_daypart_known');
  check(g, 'a known payload_kind + daypart is accepted', await intent('video_msg', 'bedtime'), 'null');
  const kinds = [];
  for (const k of ['voice_note', 'drawing', 'homework', 'photo', 'call_clip', 'e2e_video', 'nudge']) kinds.push(await intent(k, 'bedtime'));
  check(g, 'every media kind the pipeline persists is a legal payload_kind', kinds.every(x => x === null), true);
  check(g, 'intent_batch.daypart is constrained too',
    await refused(`INSERT INTO intent_batch (child_id, sender_id, label, cadence, daypart, starts_local, ends_local)
                   VALUES ($1,$2,'b','daily','teatime','2026-01-01','2026-02-01')`, [CHILD, SENDER]), 'intent_batch_daypart_known');
}

// ------------------------------------- S-D10 end to end: ctx + target-date ----
{
  const g = 'E childCtxFor + materialize by target date';
  await admin.query('COMMIT');
  const ctx = await childCtxFor(pool, CHILD);
  const bed = ctx.dayParts.filter(p => p.kind === 'bedtime');
  check(g, 'childCtxFor returns EVERY bedtime row, not only the one in force today', bed.length, 2);
  check(g, 'effective bounds are inclusive child-local dates (old part ends the day before the new one starts)',
    bed.map(p => `${p.effectiveFrom}..${p.effectiveTo}`).join(' | '), '2026-01-01..2026-08-31 | 2026-09-01..null');
  const night = (d) => materialize(
    { id: 'i', childId: CHILD, state: 'pending', expiresAt: '2030-01-01T00:00:00Z',
      policy: 'on_local_date', targetLocalDate: d, targetDaypart: 'bedtime' },
    ctx, DateTime.fromISO('2026-05-01T12:00:00Z'));
  check(g, 'the last night of the old schedule is 20:00',
    night('2026-08-31').scheduledAt.setZone('America/New_York').toFormat('HH:mm'), '20:00');
  check(g, 'the first night of the new schedule is 21:00',
    night('2026-09-01').scheduledAt.setZone('America/New_York').toFormat('HH:mm'), '21:00');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
await admin.query('DELETE FROM child WHERE id = $1', [CHILD]);
await admin.query('DELETE FROM app_user WHERE id = $1', [SENDER]);
await admin.end(); await pool.end();
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
