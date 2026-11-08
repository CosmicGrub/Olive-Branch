/**
 * packages/db/test/edge_rls.test.mjs — migration 0040 (audit S-B4): cross-family
 * isolation enforced BY THE DATABASE, plus migration 0039's composite FK (S-B5)
 * and security_event policies.
 *
 * Before 0040 the family-private tables only asked "is the caller a child?", so
 * family A's guardian could read (and write) family B's message_log, expenses,
 * medications, ... if a handler ever forgot its `WHERE child_id`. This suite
 * drives REAL sessions (withSession → set_config → the actual policies) as a
 * NOSUPERUSER NOBYPASSRLS role (app_owner, DATABASE_URL) over two families and
 * asserts, table by table, who sees what — including every deny path:
 *
 *   A  read matrix: 11 tables × 11 actors (co-guardian, sitter, former guardian
 *      with a closed edge, restricted guardian, other family, a stranger, the
 *      child, system, and a session with NO role at all)
 *   B  writes: another family's guardian cannot INSERT/UPDATE/DELETE; a child
 *      cannot INSERT; the family's own guardian can (positive control)
 *   C  guardianship / child / app_user: scoped reads, system-only writes
 *   D  health_check still works (as system) and sees no unforced table
 *   E  medication_dose composite FK (S-B5) at the database
 *   F  security_event: a co-guardian reads it, another family does not, it is
 *      append-only for everyone, and only `system` writes it
 */
import pg from 'pg';
import { createPool, withSession, withSystemSession } from '../src/pool.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();
const raw = new pg.Client({ connectionString: DATABASE_URL });   // no app.* settings at all
await raw.connect();

const CA = 'e1000000-0000-4000-8000-00000000000a';   // family A's child
const CB = 'e1000000-0000-4000-8000-00000000000b';   // family B's child
const GA1 = 'e2000000-0000-4000-8000-000000000001';  // guardian of CA
const GA2 = 'e2000000-0000-4000-8000-000000000002';  // co-guardian of CA
const SA  = 'e2000000-0000-4000-8000-000000000003';  // sitter of CA
const GAX = 'e2000000-0000-4000-8000-000000000004';  // FORMER guardian of CA (closed edge)
const GAR = 'e2000000-0000-4000-8000-000000000005';  // RESTRICTED guardian of CA
const GB  = 'e2000000-0000-4000-8000-000000000006';  // guardian of CB
const STR = 'e2000000-0000-4000-8000-000000000007';  // a guardian with no edge anywhere
const ALL_USERS = [GA1, GA2, SA, GAX, GAR, GB, STR];

async function cleanup() {
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete');
  // (security_event is append-only: its rows go with the child via ON DELETE CASCADE.)
  for (const t of ['message_log', 'expense', 'export_record', 'medication_dose',
                   'medication', 'medical_record', 'exchange_bag_item', 'exchange_running_late_log',
                   'exchange_arrival_event', 'care_note', 'custody_order']) {
    await admin.query(`DELETE FROM ${t} WHERE child_id = ANY($1::uuid[])`, [[CA, CB]]);
  }
  await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CA, CB]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CA, CB]]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [ALL_USERS]);
}
await cleanup();

await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Ann','America/Chicago'), ($2,'Alex','America/Chicago'), ($3,'Sid','America/Chicago'),
     ($4,'Xavier','America/Chicago'), ($5,'Rae','America/Chicago'), ($6,'Bea','America/Chicago'),
     ($7,'Stranger','America/Chicago')`, ALL_USERS);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Aria','2016-04-02','America/New_York'), ($2,'Bo','2016-04-02','America/New_York')`, [CA, CB]);
const open = `tstzrange(now() - interval '1 year', null)`;
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1,$2,'guardian','{}',${open}), ($1,$3,'guardian','{}',${open}), ($1,$4,'sitter','{}',${open}),
     ($5,$6,'guardian','{}',${open})`, [CA, GA1, GA2, SA, CB, GB]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid, closed_at, closed_reason)
   VALUES ($1,$2,'guardian','{}', tstzrange(now() - interval '2 years', now() - interval '1 day'),
           now() - interval '1 day', 'revoked')`, [CA, GAX]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid, restricted)
   VALUES ($1,$2,'guardian','{}', ${open}, true)`, [CA, GAR]);

// One real row per family-private table, per child.
const INSERTS = {
  message_log: (c, u) => [`INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
    VALUES ($1, 0, $2, 'edge-rls', repeat('0',64), repeat('a',64))`, [c, u]],
  expense: (c, u) => [`INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule, description)
    VALUES ($1, $2, 100, 'other', current_date, '{}'::jsonb, 'edge-rls')`, [c, u]],
  export_record: (c, u) => [`INSERT INTO export_record (child_id, requested_by, kind, was_free)
    VALUES ($1, $2, 'raw', true)`, [c, u]],
  medical_record: (c) => [`INSERT INTO medical_record (child_id) VALUES ($1)`, [c]],
  medication: (c) => [`INSERT INTO medication (child_id, name, dose) VALUES ($1, 'EdgeMed', '1 tab')`, [c]],
  exchange_bag_item: (c) => [`INSERT INTO exchange_bag_item (child_id, label) VALUES ($1, 'edge-rls')`, [c]],
  exchange_running_late_log: (c, u) => [`INSERT INTO exchange_running_late_log (child_id, eta_minutes, reported_by_user_id)
    VALUES ($1, 5, $2)`, [c, u]],
  exchange_arrival_event: (c, u) => [`INSERT INTO exchange_arrival_event
    (child_id, scheduled_at, arrived_at, delay_minutes, reported_by_user_id) VALUES ($1, now(), now(), 0, $2)`, [c, u]],
  care_note: (c, u) => [`INSERT INTO care_note (child_id, from_user_id, items, expires_at)
    VALUES ($1, $2, '[]'::jsonb, now() + interval '1 day')`, [c, u]],
  custody_order: (c) => [`INSERT INTO custody_order (child_id, order_tz, pattern, anchor_local_date, exchange_time, effective_from)
    VALUES ($1, 'America/Chicago', 'alternating_weeks', current_date, '18:00', current_date)`, [c]],
};
for (const [c, u] of [[CA, GA1], [CB, GB]]) {
  for (const make of Object.values(INSERTS)) await admin.query(...make(c, u));
}
const medIds = {};
for (const [c, u] of [[CA, GA1], [CB, GB]]) {
  medIds[c] = (await admin.query(`SELECT id FROM medication WHERE child_id = $1`, [c])).rows[0].id;
  await admin.query(
    `INSERT INTO medication_dose (medication_id, child_id, local_date, slot, administered_at, by_user_id, status)
     VALUES ($1, $2, current_date, 'am', now(), $3, 'given')`, [medIds[c], c, u]);
}
const TABLES = [...Object.keys(INSERTS), 'medication_dose'];

const as = (principal, fn) => withSession(pool, principal, fn);
const count = (principal, table, child) =>
  as(principal, async (q) => (await q(`SELECT count(*)::int AS n FROM ${table} WHERE child_id = $1`, [child]))[0].n);

// ===========================================================================
// A · read matrix
// ===========================================================================
const ACTORS = [
  ['guardian GA1',            { roleName: 'guardian', userId: GA1, childId: null }, { CA: 1, CB: 0 }],
  ['co-guardian GA2',         { roleName: 'guardian', userId: GA2, childId: null }, { CA: 1, CB: 0 }],
  ['sitter SA (live edge)',   { roleName: 'sitter',   userId: SA,  childId: null }, { CA: 1, CB: 0 }],
  ['FORMER guardian (closed edge)', { roleName: 'guardian', userId: GAX, childId: null }, { CA: 0, CB: 0 }],
  ['RESTRICTED guardian',     { roleName: 'guardian', userId: GAR, childId: null }, { CA: 0, CB: 0 }],
  ['guardian of ANOTHER family', { roleName: 'guardian', userId: GB, childId: null }, { CA: 0, CB: 1 }],
  ['guardian with no edge at all', { roleName: 'guardian', userId: STR, childId: null }, { CA: 0, CB: 0 }],
  ['system',                  { roleName: 'system',   userId: null, childId: null }, { CA: 1, CB: 1 }],
];
for (const table of TABLES) {
  for (const [label, principal, want] of ACTORS) {
    check('A read matrix', `${table}: ${label} sees ${want.CA} of family A's rows`,
      await count(principal, table, CA), want.CA);
    check('A read matrix', `${table}: ${label} sees ${want.CB} of family B's rows`,
      await count(principal, table, CB), want.CB);
  }
  // The child: P6/P7-style "not a child surface" for every table but her own custody order.
  const kidWant = table === 'custody_order' ? 1 : 0;
  check('A read matrix', `${table}: child of family A sees ${kidWant} of her own family's rows`,
    await count({ roleName: 'child', userId: null, childId: CA }, table, CA), kidWant);
  check('A read matrix', `${table}: child of family A sees 0 of family B's rows`,
    await count({ roleName: 'child', userId: null, childId: CA }, table, CB), 0);
  const noRole = (await raw.query(`SELECT count(*)::int AS n FROM ${table} WHERE child_id = ANY($1::uuid[])`, [[CA, CB]])).rows[0].n;
  check('A read matrix', `${table}: a session that never set app.role sees nothing (fails closed)`, noRole, 0);
}

// ===========================================================================
// B · writes
// ===========================================================================
{
  const insertExpense = (principal, child, by) => as(principal, (q) => q(
    `INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule, description)
     VALUES ($1, $2, 250, 'other', current_date, '{}'::jsonb, 'edge-rls-write') RETURNING id`, [child, by]));
  let code = null;
  try { await insertExpense({ roleName: 'guardian', userId: GB, childId: null }, CA, GB); } catch (e) { code = e.code; }
  check('B writes', "family B's guardian cannot INSERT an expense into family A's child (RLS 42501)", code, '42501');
  code = null;
  try { await insertExpense({ roleName: 'child', userId: null, childId: CA }, CA, GA1); } catch (e) { code = e.code; }
  check('B writes', 'a child session cannot INSERT an expense (42501)', code, '42501');
  code = null;
  try { await insertExpense({ roleName: 'guardian', userId: GAX, childId: null }, CA, GAX); } catch (e) { code = e.code; }
  check('B writes', 'a FORMER guardian (closed edge) cannot INSERT into the old family (42501)', code, '42501');
  const own = await insertExpense({ roleName: 'guardian', userId: GA1, childId: null }, CA, GA1);
  check('B writes', "positive control: the family's own guardian CAN insert", own.length, 1);

  const upd = await as({ roleName: 'guardian', userId: GB, childId: null }, (q) =>
    q(`UPDATE expense SET description = 'hijacked' WHERE child_id = $1 RETURNING id`, [CA]));
  check('B writes', "family B's guardian UPDATE of family A's expenses touches 0 rows", upd.length, 0);
  const del = await as({ roleName: 'guardian', userId: GB, childId: null }, (q) =>
    q(`DELETE FROM expense WHERE child_id = $1 RETURNING id`, [CA]));
  check('B writes', "and DELETE touches 0 rows", del.length, 0);
  const still = (await admin.query(`SELECT count(*)::int AS n FROM expense WHERE child_id = $1 AND description <> 'hijacked'`, [CA])).rows[0].n;
  check('B writes', "family A's expenses are intact afterwards (verified as superuser)", still >= 2, true);

  code = null;
  try {
    await as({ roleName: 'guardian', userId: GB, childId: null }, (q) => q(
      `INSERT INTO medication_dose (medication_id, child_id, local_date, slot, administered_at, by_user_id, status)
       VALUES ($1, $2, current_date, 'pm', now(), $3, 'given')`, [medIds[CA], CA, GB]));
  } catch (e) { code = e.code; }
  check('B writes', "family B's guardian cannot log a dose against family A's medication (42501)", code, '42501');
  code = null;
  try {
    await as({ roleName: 'guardian', userId: GB, childId: null }, (q) => q(
      `INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
       VALUES ($1, 1, $2, 'forged', repeat('a',64), repeat('b',64))`, [CA, GB]));  // a VALID link, so only RLS can refuse it
  } catch (e) { code = e.code; }
  // The chain trigger reads the log head under the CALLER's session, so for an outsider it sees
  // an empty log and refuses first (P0001); RLS (42501) is the lock behind it. Either way the
  // append must not land.
  check('B writes', "and cannot append to family A's court-evidence message_log (refused: trigger P0001 or RLS 42501)",
    code === '42501' || code === 'P0001', true);
  check('B writes', "...and family A's log is still exactly its genesis entry (verified as superuser)",
    (await admin.query(`SELECT count(*)::int AS n FROM message_log WHERE child_id = $1`, [CA])).rows[0].n, 1);
}

// ===========================================================================
// C · guardianship / child / app_user
// ===========================================================================
{
  const edgesSeen = async (principal, childId) => as(principal, async (q) =>
    (await q(`SELECT user_id FROM guardianship WHERE child_id = $1 ORDER BY user_id`, [childId])).map((r) => r.user_id));
  check('C guardianship', "GA1 sees the whole of family A's edges (self, co-guardian, sitter, former, restricted)",
    (await edgesSeen({ roleName: 'guardian', userId: GA1, childId: null }, CA)).length, 5);
  check('C guardianship', "GA1 sees none of family B's edges",
    (await edgesSeen({ roleName: 'guardian', userId: GA1, childId: null }, CB)).length, 0);
  check('C guardianship', 'GB sees only family B',
    (await edgesSeen({ roleName: 'guardian', userId: GB, childId: null }, CB)).join(), GB);
  check('C guardianship', "GB sees none of family A's edges",
    (await edgesSeen({ roleName: 'guardian', userId: GB, childId: null }, CA)).length, 0);
  check('C guardianship', 'a stranger with no edge sees no edges at all',
    (await edgesSeen({ roleName: 'guardian', userId: STR, childId: null }, CA)).length, 0);
  check('C guardianship', 'a FORMER guardian sees only her OWN (closed) edge, not the family',
    (await edgesSeen({ roleName: 'guardian', userId: GAX, childId: null }, CA)).join(), GAX);
  check('C guardianship', "the child sees her own family's edges",
    (await edgesSeen({ roleName: 'child', userId: null, childId: CA }, CA)).length, 5);
  check('C guardianship', "and not another family's",
    (await edgesSeen({ roleName: 'child', userId: null, childId: CA }, CB)).length, 0);
  check('C guardianship', 'system sees both families', (await edgesSeen({ roleName: 'system', userId: null, childId: null }, CB)).length, 1);

  const writeDenied = async (sql, params) => {
    const r = await as({ roleName: 'guardian', userId: GA1, childId: null }, async (q) => {
      try { return { n: (await q(sql, params)).length }; } catch (e) { return { code: e.code }; }
    });
    return r.code ?? `rows:${r.n}`;
  };
  check('C guardianship', 'a guardian cannot INSERT a guardianship edge for herself (42501)',
    await writeDenied(`INSERT INTO guardianship (child_id, user_id, role, scope, valid)
      VALUES ($1, $2, 'guardian', '{}', tstzrange(now(), null)) RETURNING id`, [CB, GA1]), '42501');
  check('C guardianship', 'a guardian cannot extend her own edge (UPDATE touches 0 rows)',
    await writeDenied(`UPDATE guardianship SET expires_at = NULL, restricted = false WHERE user_id = $1 RETURNING id`, [GA1]), 'rows:0');
  check('C guardianship', 'a guardian cannot delete an edge (0 rows)',
    await writeDenied(`DELETE FROM guardianship WHERE user_id = $1 RETURNING id`, [GA2]), 'rows:0');

  const childrenSeen = (principal) => as(principal, async (q) =>
    (await q(`SELECT id FROM child ORDER BY id`)).map((r) => r.id).join());
  check('C child', 'GA1 sees exactly her own child', await childrenSeen({ roleName: 'guardian', userId: GA1, childId: null }), CA);
  check('C child', 'GB sees exactly hers', await childrenSeen({ roleName: 'guardian', userId: GB, childId: null }), CB);
  check('C child', 'a stranger sees no child', await childrenSeen({ roleName: 'guardian', userId: STR, childId: null }), '');
  check('C child', 'a FORMER guardian no longer sees the child', await childrenSeen({ roleName: 'guardian', userId: GAX, childId: null }), '');
  check('C child', 'the child sees only herself', await childrenSeen({ roleName: 'child', userId: null, childId: CA }), CA);
  const kids = await childrenSeen({ roleName: 'system', userId: null, childId: null });
  check('C child', 'system sees both', kids.includes(CA) && kids.includes(CB), true);
  const kidUpd = await as({ roleName: 'guardian', userId: GA1, childId: null }, (q) =>
    q(`UPDATE child SET display_name = 'renamed' WHERE id = $1 RETURNING id`, [CA]));
  check('C child', "a guardian cannot rewrite the child row (UPDATE touches 0 rows: system-only)", kidUpd.length, 0);

  const usersSeen = (principal) => as(principal, async (q) =>
    (await q(`SELECT id FROM app_user WHERE id = ANY($1::uuid[]) ORDER BY id`, [ALL_USERS])).map((r) => r.id));
  const sees = (a, b) => b.every((x) => a.includes(x)) && a.length === b.length;
  check('C app_user', "GA1 sees family A's people (self, co-guardian, sitter, former, restricted) and NOT family B or strangers",
    sees(await usersSeen({ roleName: 'guardian', userId: GA1, childId: null }), [GA1, GA2, SA, GAX, GAR]), true);
  check('C app_user', 'GB sees only herself (no other family, no strangers)',
    sees(await usersSeen({ roleName: 'guardian', userId: GB, childId: null }), [GB]), true);
  check('C app_user', 'a stranger sees only herself (the old USING (true) policy showed every email and phone)',
    sees(await usersSeen({ roleName: 'guardian', userId: STR, childId: null }), [STR]), true);
  check('C app_user', "the child sees her guardians' rows (names on her screens), not another family's",
    sees(await usersSeen({ roleName: 'child', userId: null, childId: CA }), [GA1, GA2, SA, GAX, GAR]), true);
  check('C app_user', 'system sees everyone', sees(await usersSeen({ roleName: 'system', userId: null, childId: null }), ALL_USERS), true);
  check('C app_user', 'a session with no role sees no users',
    (await raw.query(`SELECT count(*)::int AS n FROM app_user WHERE id = ANY($1::uuid[])`, [ALL_USERS])).rows[0].n, 0);
  let code = null;
  try {
    await as({ roleName: 'guardian', userId: GA1, childId: null }, (q) => q(
      `INSERT INTO app_user (display_name, home_tz) VALUES ('Mallory', 'UTC')`));
  } catch (e) { code = e.code; }
  check('C app_user', 'a guardian cannot INSERT an app_user (the old WITH CHECK (true) is gone; 42501)', code, '42501');
  const made = await withSystemSession(pool, (q) => q(
    `INSERT INTO app_user (display_name, home_tz) VALUES ('EdgeRlsTemp', 'UTC') RETURNING id`));
  check('C app_user', 'positive control: system can create accounts', made.length, 1);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [made[0].id]);
  const selfUpd = await as({ roleName: 'guardian', userId: GA1, childId: null }, (q) =>
    q(`UPDATE app_user SET display_name = 'Ann2' WHERE id = $1 RETURNING id`, [GA1]));
  check('C app_user', 'a user can still update her own row (self_update kept)', selfUpd.length, 1);
  const otherUpd = await as({ roleName: 'guardian', userId: GA1, childId: null }, (q) =>
    q(`UPDATE app_user SET display_name = 'owned' WHERE id = $1 RETURNING id`, [GA2]));
  check('C app_user', "but not a co-guardian's (UPDATE touches 0 rows)", otherUpd.length, 0);
}

// ===========================================================================
// D · health_check
// ===========================================================================
{
  const hc = await withSystemSession(pool, (q) => q(`SELECT check_name, observed FROM health_check`));
  check('D health_check', 'the view still evaluates under FORCE RLS (as system)', hc.length >= 7, true);
  const unforced = hc.find((r) => r.check_name === 'rls_unforced');
  check('D health_check', 'rls_unforced sees 0 unforced tables across the extended list', Number(unforced?.observed), 0);
  const gap = hc.find((r) => r.check_name === 'log_sequence_gap');
  check('D health_check', 'log_sequence_gap is evaluated (not blind) and finds no gap', Number(gap?.observed), 0);
  const closure = hc.find((r) => r.check_name === 'closure_without_reason');
  check('D health_check', 'closure_without_reason (reads guardianship) is evaluated and clean', Number(closure?.observed), 0);
}

// ===========================================================================
// E · medication_dose composite FK (S-B5, migration 0039)
// ===========================================================================
{
  let code = null;
  try {
    await admin.query(
      `INSERT INTO medication_dose (medication_id, child_id, local_date, slot, administered_at, by_user_id, status)
       VALUES ($1, $2, current_date, 'noon', now(), $3, 'given')`, [medIds[CA], CB, GB]);
  } catch (e) { code = e.code; }
  check('E dose FK', "even a superuser cannot file family A's medication under family B's child (23503)", code, '23503');
  const ok = await admin.query(
    `INSERT INTO medication_dose (medication_id, child_id, local_date, slot, administered_at, by_user_id, status)
     VALUES ($1, $2, current_date, 'noon', now(), $3, 'given') RETURNING id`, [medIds[CA], CA, GA1]);
  check('E dose FK', 'positive control: the matching (medication, child) pair is accepted', ok.rowCount, 1);
}

// ===========================================================================
// F · security_event
// ===========================================================================
{
  await withSystemSession(pool, async (q) => {
    await q(`INSERT INTO security_event (child_id, actor_id, kind, summary) VALUES ($1, $2, 'pin_changed', 'A guardian PIN was changed')`, [CA, GA1]);
    await q(`INSERT INTO security_event (child_id, actor_id, kind, summary) VALUES ($1, $2, 'export_taken', 'An export of the family records was taken')`, [CB, GB]);
  });
  const seen = (principal, child) => count(principal, 'security_event', child);
  check('F security_event', 'the co-guardian reads the other guardian\'s event (that is the point)',
    await seen({ roleName: 'guardian', userId: GA2, childId: null }, CA), 1);
  check('F security_event', 'the actor reads her own', await seen({ roleName: 'guardian', userId: GA1, childId: null }, CA), 1);
  check('F security_event', "another family's guardian reads nothing of family A", await seen({ roleName: 'guardian', userId: GB, childId: null }, CA), 0);
  check('F security_event', 'a FORMER guardian reads nothing', await seen({ roleName: 'guardian', userId: GAX, childId: null }, CA), 0);
  check('F security_event', 'the child reads nothing (not a child surface)', await seen({ roleName: 'child', userId: null, childId: CA }, CA), 0);
  check('F security_event', 'a stranger reads nothing', await seen({ roleName: 'guardian', userId: STR, childId: null }, CA), 0);
  let code = null;
  try {
    await as({ roleName: 'guardian', userId: GA1, childId: null }, (q) => q(
      `INSERT INTO security_event (child_id, actor_id, kind, summary) VALUES ($1, $2, 'pin_changed', 'forged')`, [CA, GA1]));
  } catch (e) { code = e.code; }
  check('F security_event', 'a guardian cannot write events herself (only system; 42501)', code, '42501');
  const del = await as({ roleName: 'guardian', userId: GA1, childId: null }, (q) =>
    q(`DELETE FROM security_event WHERE child_id = $1 RETURNING seq`, [CA]));
  check('F security_event', 'a guardian cannot erase the trail of her own break-in (0 rows)', del.length, 0);
  code = null;
  try { await withSystemSession(pool, (q) => q(`DELETE FROM security_event WHERE child_id = $1`, [CA])); }
  catch (e) { code = e.code; }
  check('F security_event', 'not even system can DELETE (append-only trigger; 23000)', code, '23000');
  code = null;
  try { await withSystemSession(pool, (q) => q(`UPDATE security_event SET summary = 'edited' WHERE child_id = $1`, [CA])); }
  catch (e) { code = e.code; }
  check('F security_event', 'nor rewrite a summary (23000)', code, '23000');
  const stamped = await withSystemSession(pool, (q) =>
    q(`UPDATE security_event SET notified_at = now() WHERE child_id = $1 RETURNING seq`, [CA]));
  check('F security_event', 'but may stamp notified_at (the notifier hook)', stamped.length, 1);
  code = null;
  try { await withSystemSession(pool, (q) => q(
    `INSERT INTO security_event (child_id, actor_id, kind, summary) VALUES ($1, $2, 'not_a_kind', 'x')`, [CA, GA1])); }
  catch (e) { code = e.code; }
  check('F security_event', 'an unknown kind is refused by the CHECK (23514)', code, '23514');
}

await cleanup();
await admin.end(); await raw.end(); await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
