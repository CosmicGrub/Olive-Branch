/**
 * server/routes.mjs — GET /v1/children/:childId/medications, POST
 * .../medications/:medicationId/doses, GET/PUT .../emergency-card. Real
 * for the first time — found and closed by this project's own
 * coordination-layer audit (MASTERFILE §20.2b), same pass that closed the
 * handover log and expenses.
 *
 * `medication`/`medication_dose`/`medical_record` (db/migrations/
 * 0026_medications_emergency_card.sql) have real FORCE RLS
 * (`..._no_child`), and `medication.view`/`medication.log`/
 * `emergency_card.view` already existed in family-graph/src/authorize.ts's
 * Action union with real ROLE_CAPS — but nothing anywhere ever wrote or
 * read a row. meds_care.dart/emergency_card.dart were pure hardcoded
 * client state with zero network calls.
 *
 * Proves:
 *   (a) GET .../medications returns the real seeded medications, empty
 *       doses for a day nothing was logged.
 *   (b) POST .../doses records a real dose; GET reflects it.
 *   (c) the real double-dose guard: a second 'given' dose for the same
 *       medication/day/slot is a real 409, naming who and when, against a
 *       REAL Postgres unique-index conflict, not merely a pre-check.
 *   (d) a sitter can log a dose (real ROLE_CAPS) but a step_parent cannot
 *       (also real ROLE_CAPS, a pre-existing distinction this pass did not
 *       invent).
 *   (e) GET/PUT .../emergency-card round-trips real medical_record fields,
 *       and "Guardians" is derived live from the real guardianship/
 *       app_user rows, including phone_e164, not stored separately.
 *   (f) only a guardian may PUT the emergency card — a sitter (real
 *       emergency_card.view holder) is refused.
 *   (g) a child session is refused for every route.
 */
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';

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

const DAD = '11111111-1111-4111-9111-000000000003';
const MOM = '22222222-2222-4222-9222-000000000003';
const SITTER = '77777777-7777-4777-9777-000000000003';
const STEP = '88888888-8888-4888-9888-000000000003';
const CHILD = '55555555-5555-4555-9555-000000000003';

async function cleanup() {
  await admin.query(`DELETE FROM medication_dose WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM medication WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM medical_record WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[DAD, MOM, SITTER, STEP]]);
}
await cleanup();

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz, phone_e164) VALUES
     ($1,'Dad','America/Chicago','+16175550142'), ($2,'Mom','America/Denver','+16175550198'),
     ($3,'Sitter Sue','America/New_York',null), ($4,'Stepdad Sam','America/New_York',null)`,
  [DAD, MOM, SITTER, STEP]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/Los_Angeles')`, [CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $4, 'sitter', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $5, 'step_parent', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, SITTER, STEP]);
const med = (await admin.query(
  `INSERT INTO medication (child_id, name, dose, slots, is_prn, min_gap_hours)
   VALUES ($1, 'Methylphenidate', '10 mg', '["morning","evening"]'::jsonb, false, null)
   RETURNING id`, [CHILD])).rows[0];
const prnMed = (await admin.query(
  `INSERT INTO medication (child_id, name, dose, slots, is_prn, min_gap_hours, max_doses_per_24h)
   VALUES ($1, 'Albuterol inhaler', '2 puffs', '["prn"]'::jsonb, true, 4, 3)
   RETURNING id`, [CHILD])).rows[0];
await admin.query('COMMIT');
const MED_ID = med.id, PRN_MED_ID = prnMed.id;

const SECRET = Buffer.from('f'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const momTok = issueSession(SECRET,
  { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);
const sitterTok = issueSession(SECRET,
  { userId: SITTER, roleName: 'sitter', childId: null, escalated: false }, NOW);
const stepTok = issueSession(SECRET,
  { userId: STEP, roleName: 'step_parent', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const getMeds = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/medications`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const postDose = (childId, medicationId, tok, body) => api.handle(
  'POST', `/v1/children/${childId}/medications/${medicationId}/doses`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);
const getCard = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/emergency-card`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '',
);
const putCard = (childId, tok, body) => api.handle(
  'PUT', `/v1/children/${childId}/emergency-card`,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body),
);

// ===========================================================================
// A · GET .../medications returns the real seeded medications, no doses yet.
// ===========================================================================
{
  const res = await getMeds(CHILD, dadTok);
  check('A list', 'authorized guardian -> 200', res.status, 200);
  check('A list', 'both real seeded medications present', res.body.medications.length, 2);
  const m = res.body.medications.find(x => x.id === MED_ID);
  check('A list', 'real name round-trips', m?.name, 'Methylphenidate');
  check('A list', 'real slots jsonb round-trips', JSON.stringify(m?.slots), '["morning","evening"]');
  check('A list', 'no doses logged yet today', res.body.doses.length, 0);
  check('A list', 'a real localDate is present (child-local, not server-local)',
    /^\d{4}-\d{2}-\d{2}$/.test(res.body.localDate), true);
}

// ===========================================================================
// B · a real dose is recorded; GET reflects it with a real joined name.
// ===========================================================================
{
  const res = await postDose(CHILD, MED_ID, dadTok, { slot: 'morning' });
  check('B record dose', 'authorized guardian -> 201', res.status, 201);
  check('B record dose', 'status defaults to given', res.body.status, 'given');
  check('B record dose', 'medicationId round-trips', res.body.medicationId, MED_ID);

  const list = await getMeds(CHILD, dadTok);
  check('B record dose', 'the real dose now appears in GET', list.body.doses.length, 1);
  check('B record dose', "the real dose's joined byUserName is real",
    list.body.doses[0].byUserName, 'Dad');
}

// ===========================================================================
// C · the real double-dose guard — a second 'given' dose for the SAME
//     medication/day/slot is a real 409 against a real Postgres unique-index
//     conflict, naming who and when.
// ===========================================================================
{
  const res = await postDose(CHILD, MED_ID, momTok, { slot: 'morning' });
  check('C double dose', 'a second guardian trying the same slot is refused', res.status, 409);
  check('C double dose', 'names the real reason', res.body.error, 'already_administered');
  check('C double dose', 'names the real guardian who actually gave it', res.body.by, 'Dad');
  check('C double dose', 'names a real ISO timestamp, not a placeholder',
    /^\d{4}-\d{2}-\d{2}T/.test(res.body.atIso), true);

  const dbCount = (await admin.query(
    `SELECT count(*) AS n FROM medication_dose WHERE medication_id = $1`, [MED_ID])).rows[0].n;
  check('C double dose', 'the refused second dose left no trace — still exactly one real row',
    dbCount, '1');
}

// ===========================================================================
// D · a different slot / different medication is NOT blocked by the same
//     guard — this is a real per-(medication,day,slot) key, not a
//     per-medication or per-day lock.
// ===========================================================================
{
  const res = await postDose(CHILD, PRN_MED_ID, momTok, { slot: 'prn' });
  check('D different medication', 'a PRN dose for a DIFFERENT medication is unaffected',
    res.status, 201);
}

// ===========================================================================
// E · role distinctions — a sitter CAN log a dose; a step_parent, despite
//     holding real medication.view, CANNOT (a real, pre-existing ROLE_CAPS
//     distinction, not invented by this pass).
// ===========================================================================
{
  const sitterRes = await postDose(CHILD, MED_ID, sitterTok, { slot: 'evening' });
  check('E roles', 'a sitter can log a real dose', sitterRes.status, 201);

  const stepGetRes = await getMeds(CHILD, stepTok);
  check('E roles', 'a step_parent CAN view medications', stepGetRes.status, 200);
  const stepPostRes = await postDose(CHILD, MED_ID, stepTok, { slot: 'evening' });
  check('E roles', 'a step_parent CANNOT log a dose — real, pre-existing ROLE_CAPS',
    stepPostRes.status, 403);
}

// ===========================================================================
// F · GET/PUT .../emergency-card round-trips real fields; "Guardians" is
//     derived live from real guardianship + app_user.phone_e164, not
//     stored on medical_record at all.
// ===========================================================================
{
  const putRes = await putCard(CHILD, dadTok, {
    bloodType: 'O positive', allergies: ['Peanuts — carries an EpiPen'],
    conditions: ['Mild asthma'], pediatricianName: 'Dr. Priya Nair',
    pediatricianPractice: 'Riverbend Pediatrics', pediatricianPhone: '(617) 555-0177',
    insuranceProvider: 'BlueBridge Family Health', insuranceMemberId: 'BBH-7734-2201',
    ifMatch: 0,
  });
  check('F emergency card', 'a real guardian can PUT the card -> 200', putRes.status, 200);
  check('F emergency card', 'bloodType round-trips', putRes.body.bloodType, 'O positive');
  check('F emergency card', 'allergies round-trip',
    JSON.stringify(putRes.body.allergies), '["Peanuts — carries an EpiPen"]');

  const getRes = await getCard(CHILD, momTok);
  check('F emergency card', 'a DIFFERENT guardian can GET the same real record -> 200',
    getRes.status, 200);
  check('F emergency card', 'pediatricianPractice round-trips',
    getRes.body.pediatricianPractice, 'Riverbend Pediatrics');
  check('F emergency card', 'exactly the two real seeded guardians, derived live',
    getRes.body.guardians.length, 2);
  const dadGuardian = getRes.body.guardians.find(g => g.userId === DAD);
  check('F emergency card', "a guardian's real phone_e164 is included, not a placeholder",
    dadGuardian?.phone, '+16175550142');
  check('F emergency card', 'the sitter/step_parent are NOT counted among "Guardians" -- '
    + 'role-filtered, not every effective edge', getRes.body.guardians.length, 2);
  check('F emergency card', 'the real medications list is folded into the same response',
    getRes.body.medications.length, 2);
}

// ===========================================================================
// G · only a guardian may PUT — a sitter (a real emergency_card.view
//     holder) is refused; role_lacks_capability, not P6 (this is medical,
//     not financial).
// ===========================================================================
{
  const sitterGetRes = await getCard(CHILD, sitterTok);
  check('G write guard', 'a sitter CAN view the card -- the real narrow read carve-out',
    sitterGetRes.status, 200);
  const sitterPutRes = await putCard(CHILD, sitterTok, { bloodType: 'should not land', ifMatch: 1 });
  check('G write guard', 'a sitter CANNOT edit it', sitterPutRes.status, 403);

  const stillReal = await getCard(CHILD, dadTok);
  check('G write guard', "the refused PUT left the real record untouched",
    stillReal.body.bloodType, 'O positive');
}

// ===========================================================================
// H · a child session is refused for every route.
// ===========================================================================
{
  const getMedsRes = await getMeds(CHILD, childTok);
  check('H child refused', 'GET .../medications refused', getMedsRes.status, 403);

  const postDoseRes = await postDose(CHILD, MED_ID, childTok, { slot: 'morning' });
  check('H child refused', 'POST .../doses refused', postDoseRes.status, 403);

  const getCardRes = await getCard(CHILD, childTok);
  check('H child refused', 'GET .../emergency-card refused', getCardRes.status, 403);

  const putCardRes = await putCard(CHILD, childTok, { bloodType: 'nope' });
  check('H child refused', 'PUT .../emergency-card refused', putCardRes.status, 403);
  const histChild = await api.handle('GET', `/v1/children/${CHILD}/emergency-card/history`,
    { authorization: `Bearer ${childTok}` }, '');
  check('H child refused', 'GET .../emergency-card/history refused', histChild.status, 403);
}

// ===========================================================================
// I · G-11 — optimistic concurrency + append-only history (migration 0036).
// ===========================================================================
{
  const first = await getCard(CHILD, dadTok);
  check('I versioning', 'GET returns the version the first PUT produced (1)', first.body.version, 1);
  check('I versioning', 'GET returns lastChange.byName = the real writer',
    first.body.lastChange?.byName, 'Dad');

  const noMatch = await putCard(CHILD, dadTok, { bloodType: 'A' });
  check('I versioning', 'a PUT with no ifMatch is refused 428, not silently applied',
    noMatch.status, 428);

  // Mom saves from the version both of them read...
  const momSave = await putCard(CHILD, momTok, { bloodType: 'O positive', allergies: ['Peanuts', 'Egg'],
    ifMatch: 1 });
  check('I versioning', 'first writer from version 1 wins -> 200', momSave.status, 200);
  check('I versioning', 'and the card is now version 2', momSave.body.version, 2);
  check('I versioning', 'attributed to the second guardian', momSave.body.lastChange?.byName, 'Mom');

  // ...Dad, still on version 1, must NOT overwrite it.
  const dadStale = await putCard(CHILD, dadTok, { bloodType: 'B', allergies: [], ifMatch: 1 });
  check('I versioning', 'a stale writer is refused 409', dadStale.status, 409);
  check('I versioning', '409 body names stale_version', dadStale.body.error, 'stale_version');
  check('I versioning', '409 body carries the current version so the client can reload',
    dadStale.body.currentVersion, 2);
  const afterStale = await getCard(CHILD, dadTok);
  check('I versioning', 'the stale write changed nothing (allergies kept)',
    JSON.stringify(afterStale.body.allergies), '["Peanuts","Egg"]');

  // Two writers racing on the same version: exactly one wins.
  const [r1, r2] = await Promise.all([
    putCard(CHILD, dadTok, { bloodType: 'AB', ifMatch: 2 }),
    putCard(CHILD, momTok, { bloodType: 'O', ifMatch: 2 }),
  ]);
  check('I versioning', 'concurrent writers on one version: exactly one 200 and one 409',
    [r1.status, r2.status].sort().join(','), '200,409');

  const hist = await api.handle('GET', `/v1/children/${CHILD}/emergency-card/history`,
    { authorization: `Bearer ${dadTok}` }, '');
  check('I history', 'a guardian can read the history -> 200', hist.status, 200);
  check('I history', 'one history row per successful write (1,2,3)',
    hist.body.entries.map(e => e.version).join(','), '3,2,1');
  const v1 = hist.body.entries.find(e => e.version === 1);
  check('I history', 'the first write replaced nothing (priorValues null)', v1.priorValues, null);
  const v2 = hist.body.entries.find(e => e.version === 2);
  check('I history', 'v2 records the writer by display name', v2.changedBy, 'Mom');
  check('I history', 'v2 keeps the values it replaced (the original single allergy)',
    JSON.stringify(v2.priorValues.allergies), '["Peanuts — carries an EpiPen"]');

  // Append-only is enforced by the database, not by route politeness.
  let updRefused = false;
  try { await admin.query(`UPDATE medical_record_history SET version = 99 WHERE child_id = $1`, [CHILD]); }
  catch { updRefused = true; }
  check('I append-only', 'UPDATE on the history table is refused (even for the superuser)', updRefused, true);
  let delRefused = false;
  try { await admin.query(`DELETE FROM medical_record_history WHERE child_id = $1`, [CHILD]); }
  catch { delRefused = true; }
  check('I append-only', 'a direct DELETE on the history table is refused', delRefused, true);
  const cnt = await admin.query(`SELECT count(*)::int AS n FROM medical_record_history WHERE child_id = $1`, [CHILD]);
  check('I append-only', 'all three rows are still there', cnt.rows[0].n, 3);
}

// ===========================================================================
// K · S-D6 -- the medication safety rules are enforced by the SERVER.
// ===========================================================================
{
  const hoursAgo = (h) => new Date(Date.now() - h * 3600_000).toISOString();

  // slot validation + canonicalisation
  const unknown = await postDose(CHILD, MED_ID, momTok, { slot: 'lunch' });
  check('K slot validation', 'a slot the medication does not have is refused 400', unknown.status, 400);
  check('K slot validation', 'with the reason unknown_slot', unknown.body.error, 'unknown_slot');
  check('K slot validation', 'and the real slots listed', JSON.stringify(unknown.body.allowed), '["morning","evening"]');
  const upper = await postDose(CHILD, MED_ID, momTok, { slot: '  MORNING ' });
  check('K slot validation', "a differently-cased slot hits the SAME double-dose guard (Dad already gave 'morning')",
    upper.status, 409);
  check('K slot validation', 'naming Dad', upper.body.by, 'Dad');
  const morningRows = (await admin.query(
    `SELECT count(*) AS n FROM medication_dose WHERE medication_id = $1 AND slot = 'morning'`, [MED_ID])).rows[0].n;
  check('K slot validation', "no second 'morning' row, and no stray 'MORNING' row either", morningRows, '1');
  const strays = (await admin.query(
    `SELECT count(*) AS n FROM medication_dose WHERE medication_id = $1 AND slot <> lower(slot)`, [MED_ID])).rows[0].n;
  check('K slot validation', 'every stored slot is a canonical slot spelling', strays, '0');
  const noSlot = await postDose(CHILD, MED_ID, momTok, {});
  check('K slot validation', 'a missing slot is still 400 slot_required', noSlot.body.error, 'slot_required');

  // medication ownership
  const ghost = await postDose(CHILD, '00000000-0000-4000-8000-00000000dead', momTok, { slot: 'morning' });
  check('K ownership', 'a medication id that does not exist is 404', ghost.status, 404);
  const OTHER_CHILD = '55555555-5555-4555-9555-0000000000c2';
  await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'Other','2015-01-01','America/Chicago')`, [OTHER_CHILD]);
  const otherMed = (await admin.query(
    `INSERT INTO medication (child_id, name, dose, slots, is_prn) VALUES ($1,'Other med','1','["morning"]'::jsonb,false) RETURNING id`,
    [OTHER_CHILD])).rows[0].id;
  const cross = await postDose(CHILD, otherMed, momTok, { slot: 'morning' });
  check('K ownership', "ANOTHER child's medication cannot be logged under this child's path", cross.status, 404);
  check('K ownership', 'and nothing was written for it',
    (await admin.query(`SELECT count(*) AS n FROM medication_dose WHERE medication_id = $1`, [otherMed])).rows[0].n, '0');
  await admin.query(`DELETE FROM medication WHERE id = $1`, [otherMed]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [OTHER_CHILD]);

  // PRN minimum gap (a PRN dose by Mom was logged in section D)
  const tooSoon = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn' });
  check('K prn gap', 'a second PRN dose inside the 4h minimum gap is refused 409', tooSoon.status, 409);
  check('K prn gap', 'reason too_soon', tooSoon.body.error, 'too_soon');
  check('K prn gap', 'the refusal says when the next dose may stand (about 4h out)',
    Math.abs(Date.parse(tooSoon.body.nextAllowedAt) - (Date.now() + 4 * 3600_000)) < 120_000, true);
  check('K prn gap', 'and the gap', tooSoon.body.minGapHours, 4);

  // audited back-dating
  const back5 = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: hoursAgo(5) });
  check('K backdated', 'a dose given 5h ago (outside the gap on both sides) is accepted', back5.status, 201);
  check('K backdated', 'the response is flagged backdated', back5.body.backdated, true);
  check('K backdated', 'administeredAt is the CLAIMED time (about 5h ago)',
    Math.abs(Date.parse(back5.body.administeredAt) - (Date.now() - 5 * 3600_000)) < 120_000, true);
  check('K backdated', 'recordedAt is the REAL time (about now)',
    Math.abs(Date.parse(back5.body.recordedAt) - Date.now()) < 120_000, true);
  const audit = (await admin.query(
    `SELECT backdated, recorded_at - administered_at AS lag, is_prn FROM medication_dose WHERE id = $1`, [back5.body.id])).rows[0];
  check('K backdated', 'the row is stored backdated, with the lag between claim and record', audit.backdated, true);
  check('K backdated', 'and marked PRN', audit.is_prn, true);
  const live = (await admin.query(
    `SELECT backdated, recorded_at = administered_at AS same FROM medication_dose WHERE medication_id = $1 AND by_user_id = $2 AND NOT backdated LIMIT 1`,
    [PRN_MED_ID, MOM])).rows[0];
  check('K backdated', 'a live dose is not backdated and recorded == administered', `${live.backdated}|${live.same}`, 'false|true');
  const listed = await getMeds(CHILD, dadTok);
  check('K backdated', 'GET exposes the audit flag on every dose', listed.body.doses.length > 0 && listed.body.doses.every(d => typeof d.backdated === 'boolean'), true);
  const tooSoonBack = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: hoursAgo(6) });
  check('K backdated', 'a back-dated dose too close to ANOTHER earlier dose is refused too (gap both sides)',
    `${tooSoonBack.status}:${tooSoonBack.body.error}`, '409:too_soon');
  let violated = false;
  try { await admin.query(`UPDATE medication_dose SET backdated = false WHERE id = $1`, [back5.body.id]); }
  catch { violated = true; }
  check('K backdated', 'the database refuses to relabel a backdated row as live (CHECK)', violated, true);

  // rolling 24h cap (medication seeded with max_doses_per_24h = 3)
  const back10 = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: hoursAgo(10) });
  check('K prn cap', 'the third dose in 24h (now, -5h, -10h) is accepted', back10.status, 201);
  const back15 = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: hoursAgo(15) });
  check('K prn cap', 'a fourth inside the same rolling 24h is refused 409', back15.status, 409);
  check('K prn cap', 'reason daily_max', back15.body.error, 'daily_max');
  check('K prn cap', 'with the cap', back15.body.max, 3);
  const back30 = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: hoursAgo(30) });
  check('K prn cap', 'a dose from 30h ago does not touch the current window', back30.status, 201);

  // given_at validation
  const future = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: new Date(Date.now() + 3600_000).toISOString() });
  check('K given_at', 'a time in the future is 400 bad_given_at', `${future.status}:${future.body.error}:${future.body.detail}`, '400:bad_given_at:in_the_future');
  const old = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: hoursAgo(100) });
  check('K given_at', 'more than 72h ago is 400 too_old', `${old.status}:${old.body.detail}`, '400:too_old');
  const naive = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: '2026-01-01T08:00:00' });
  check('K given_at', 'a bare local time with no offset is refused (ambiguous across two zones)',
    `${naive.status}:${naive.body.detail}`, '400:iso_with_offset_required');
  const junk = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: 'yesterday' });
  check('K given_at', 'junk is refused', junk.status, 400);
  const numeric = await postDose(CHILD, PRN_MED_ID, dadTok, { slot: 'prn', given_at: 12345 });
  check('K given_at', 'a non-string is refused', numeric.status, 400);

  // the unique index now covers scheduled doses only
  let prnTwice = true;
  try {
    for (let i = 0; i < 2; i++) {
      await admin.query(
        `INSERT INTO medication_dose (medication_id, child_id, local_date, slot, administered_at, by_user_id, status, is_prn, backdated)
         VALUES ($1,$2,'2020-01-01','prn', now() - interval '30 days' - ($3 || ' hours')::interval, $4, 'given', true, true)`,
        [PRN_MED_ID, CHILD, String(i * 6), MOM]);
    }
  } catch { prnTwice = false; }
  check('K unique index', 'two PRN doses on one local date + slot are now possible', prnTwice, true);
  let schedTwice = false;
  try {
    for (let i = 0; i < 2; i++) {
      await admin.query(
        `INSERT INTO medication_dose (medication_id, child_id, local_date, slot, administered_at, by_user_id, status, is_prn, backdated)
         VALUES ($1,$2,'2020-01-02','morning', now() - interval '40 days', $3, 'given', false, true)`, [MED_ID, CHILD, MOM]);
    }
  } catch { schedTwice = true; }   // the second insert must violate the partial unique index
  check('K unique index', 'two SCHEDULED doses on one local date + slot still collide', schedTwice, true);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
