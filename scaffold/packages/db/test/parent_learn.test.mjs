/**
 * packages/db — Parent Learn: real RLS and the real loaders.
 * db/migrations/0035_parent_learn.sql; packages/parent-learn/src/learn.ts.
 *
 * Same harness as guardian_activity_override.test.mjs: a real Postgres with
 * 0035 applied, DATABASE_URL as app_owner (NOBYPASSRLS) and ADMIN_DATABASE_URL
 * as a superuser used only for seeding/inspection. Not part of `npm test`'s
 * default chain (a suite that measures RLS run as `postgres` measures
 * nothing — db/DEPLOYMENT.md); tools/verify.sh runs it in its DB section.
 *
 * The cases that matter most: a reflection is readable by its author and by
 * NOBODY else (co-guardian, child, sitter, step-parent, system, a stranger
 * guardian), nothing is stored unless the guardian opted in, a shared rules
 * list never outlives its opt-in, the other guardian can read but never
 * write the list, and no export function reads any of the new tables.
 */
import pg from 'pg';
import { readFileSync } from 'node:fs';
import {
  createPool, withSession, withSystemSession,
  learnSettingsFor, setLearnSettings, saveReflection, listReflections,
  deleteReflection, clearReflections, setHouseRules, houseRulesFor,
} from '../src/pool.mjs';

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

// Family A: child CA with two live guardians (DAD, MOM), a sitter, a step-parent.
// Family B: child CB with one unrelated guardian (STRANGER).
const CA = 'cccccccc-cccc-4ccc-8ccc-0000000000a1';
const CB = 'cccccccc-cccc-4ccc-8ccc-0000000000b1';
const DAD = 'dddddddd-dddd-4ddd-8ddd-0000000000a1';
const MOM = 'dddddddd-dddd-4ddd-8ddd-0000000000a2';
const SITTER = 'dddddddd-dddd-4ddd-8ddd-0000000000a3';
const STEP = 'dddddddd-dddd-4ddd-8ddd-0000000000a4';
const STRANGER = 'dddddddd-dddd-4ddd-8ddd-0000000000b1';
const ALL_USERS = [DAD, MOM, SITTER, STEP, STRANGER];

async function reset() {
  await admin.query(`DELETE FROM guardian_house_rule WHERE child_id IN ($1,$2)`, [CA, CB]);
  await admin.query(`DELETE FROM guardian_reflection WHERE guardian_id = ANY($1::uuid[])`, [ALL_USERS]);
  await admin.query(`DELETE FROM guardian_learn_settings WHERE guardian_id = ANY($1::uuid[])`, [ALL_USERS]);
  await admin.query(`DELETE FROM guardianship WHERE child_id IN ($1,$2)`, [CA, CB]);
  await admin.query(`DELETE FROM child WHERE id IN ($1,$2)`, [CA, CB]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [ALL_USERS]);
}

await admin.query('BEGIN');
await reset();
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/New_York'),
     ($3,'Sitter','America/Denver'), ($4,'Step','America/Denver'), ($5,'Stranger','America/Denver')`,
  [DAD, MOM, SITTER, STEP, STRANGER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2019-04-02','America/New_York'), ($2,'Eli','2018-01-01','America/Denver')`, [CA, CB]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1,$2,'guardian','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$3,'guardian','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$4,'sitter','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$5,'step_parent','{}',tstzrange(now() - interval '1 year', null)),
     ($6,$7,'guardian','{}',tstzrange(now() - interval '1 year', null))`,
  [CA, DAD, MOM, SITTER, STEP, CB, STRANGER]);
await admin.query('COMMIT');

const asDad = (fn) => withSession(pool, { roleName: 'guardian', userId: DAD, childId: null }, fn);
const asMom = (fn) => withSession(pool, { roleName: 'guardian', userId: MOM, childId: null }, fn);
const asStranger = (fn) => withSession(pool, { roleName: 'guardian', userId: STRANGER, childId: null }, fn);
const asSitter = (fn) => withSession(pool, { roleName: 'sitter', userId: SITTER, childId: null }, fn);
const asStep = (fn) => withSession(pool, { roleName: 'step_parent', userId: STEP, childId: null }, fn);
const asChild = (fn) => withSession(pool, { roleName: 'child', userId: null, childId: CA }, fn);

// ===========================================================================
// A · settings: absent row == private defaults, never stored; partial patches
// ===========================================================================
{
  const g = 'A settings';
  const d = await learnSettingsFor(pool, DAD);
  check(g, 'no row: reflection defaults to session-only', d.reflection, 'session');
  check(g, 'no row: framing neutral', d.framing, 'neutral');
  check(g, 'no row: rules list off', d.rulesList, 'false');
  check(g, 'no row: message check off', d.messageCheck, 'false');
  const n = (await admin.query(`SELECT count(*)::int n FROM guardian_learn_settings WHERE guardian_id=$1`, [DAD])).rows[0].n;
  check(g, 'reading the defaults writes nothing (defaults are never stored)', n, 0);

  const s1 = await setLearnSettings(pool, DAD, { messageCheck: true });
  check(g, 'a partial patch turns one thing on', s1.messageCheck, 'true');
  check(g, 'the rest stay at the private defaults', `${s1.reflection}/${s1.framing}/${s1.rulesList}`, 'session/neutral/false');
  const s2 = await setLearnSettings(pool, DAD, { reflection: 'saved', framing: 'culture-note' });
  check(g, 'a second patch keeps the first', `${s2.messageCheck}/${s2.reflection}/${s2.framing}`, 'true/saved/culture-note');
  const back = await learnSettingsFor(pool, DAD);
  check(g, 'round-trip equals what was written', JSON.stringify(back), JSON.stringify(s2));
  const junk = await setLearnSettings(pool, DAD, { reflection: 'cloud', framing: 'x', rulesList: 'yes' });
  check(g, 'junk values in a patch fall back (reflection)', junk.reflection, 'saved');
  check(g, 'junk values in a patch fall back (rulesList is not a boolean true)', junk.rulesList, 'false');
  check(g, "MOM's settings are untouched by DAD's writes", (await learnSettingsFor(pool, MOM)).messageCheck, 'false');
  let checkThrew = false;
  try { await admin.query(`INSERT INTO guardian_learn_settings (guardian_id, reflection) VALUES ($1,'cloud')`, [MOM]); }
  catch { checkThrew = true; }
  check(g, 'the CHECK constraint refuses a bad reflection mode even for a superuser', checkThrew, 'true');
}

// ===========================================================================
// B · reflections: opt-in storage, owner-only reads, upsert, delete
// ===========================================================================
{
  const g = 'B reflections';
  await setLearnSettings(pool, MOM, { reflection: 'session' });
  const refused = await saveReflection(pool, MOM, '2026-11-01', 70, 60);
  check(g, 'session-only: a save is REFUSED', JSON.stringify(refused), JSON.stringify({ ok: false, reason: 'reflection_not_saved' }));
  check(g, 'and nothing was written', (await listReflections(pool, MOM)).length, 0);
  await setLearnSettings(pool, MOM, { reflection: 'off' });
  check(g, "'off': a save is refused too", (await saveReflection(pool, MOM, '2026-11-01', 70, 60)).ok, 'false');
  check(g, 'a guardian with NO settings row is refused (default is session-only)', (await saveReflection(pool, STRANGER, '2026-11-01', 1, 1)).ok, 'false');

  // DAD has 'saved' from section A.
  check(g, "'saved': a save succeeds", (await saveReflection(pool, DAD, '2026-11-01', 80, 30)).ok, 'true');
  await saveReflection(pool, DAD, '2026-11-02', 40, 90);
  const l = await listReflections(pool, DAD);
  check(g, 'list is newest first', l.map((r) => r.day).join(), '2026-11-02,2026-11-01');
  check(g, 'values round-trip', `${l[1].warmth}/${l[1].expectations}`, '80/30');
  await saveReflection(pool, DAD, '2026-11-01', 55, 55);
  const l2 = await listReflections(pool, DAD);
  check(g, 'the same day upserts, never duplicates', l2.length, 2);
  check(g, 'the upsert replaced the values', l2.find((r) => r.day === '2026-11-01').warmth, 55);

  let rangeThrew = false;
  try { await saveReflection(pool, DAD, '2026-11-03', 101, 5); } catch { rangeThrew = true; }
  check(g, 'a warmth of 101 is refused by the CHECK (route validates first; the DB is the backstop)', rangeThrew, 'true');

  // ---- who can read DAD's reflection: nobody but DAD ---------------------
  const sel = `SELECT count(*)::int n FROM guardian_reflection`;
  check(g, 'DAD reads his own', (await asDad((q) => q(sel)))[0].n, 2);
  check(g, 'the CO-GUARDIAN sees zero rows (not even a count)', (await asMom((q) => q(sel)))[0].n, 0);
  check(g, 'an unrelated guardian sees zero rows', (await asStranger((q) => q(sel)))[0].n, 0);
  check(g, 'a sitter sees zero rows', (await asSitter((q) => q(sel)))[0].n, 0);
  check(g, 'a step-parent sees zero rows', (await asStep((q) => q(sel)))[0].n, 0);
  check(g, 'the CHILD sees zero rows', (await asChild((q) => q(sel)))[0].n, 0);
  check(g, 'the SYSTEM role sees zero rows (no system policy exists)', (await withSystemSession(pool, (q) => q(sel)))[0].n, 0);
  check(g, 'the co-guardian even naming DAD by id gets nothing',
    (await asMom((q) => q(`SELECT count(*)::int n FROM guardian_reflection WHERE guardian_id=$1`, [DAD])))[0].n, 0);
  check(g, "listReflections for MOM returns none of DAD's", (await listReflections(pool, MOM)).length, 0);

  // ---- nobody else can write, update or delete DAD's rows -----------------
  const momUpdate = await asMom((q) => q(`UPDATE guardian_reflection SET warmth = 0 WHERE guardian_id=$1 RETURNING id`, [DAD]));
  check(g, 'the co-guardian UPDATE affects zero rows', momUpdate.length, 0);
  const momDelete = await asMom((q) => q(`DELETE FROM guardian_reflection WHERE guardian_id=$1 RETURNING id`, [DAD]));
  check(g, 'the co-guardian DELETE affects zero rows', momDelete.length, 0);
  let forgedInsert = false;
  try { await asMom((q) => q(`INSERT INTO guardian_reflection (guardian_id, day, warmth, expectations) VALUES ($1,'2026-11-09',1,1)`, [DAD])); }
  catch { forgedInsert = true; }
  check(g, 'the co-guardian cannot INSERT a row in DAD\'s name', forgedInsert, 'true');
  let childInsert = false;
  try { await asChild((q) => q(`INSERT INTO guardian_reflection (guardian_id, day, warmth, expectations) VALUES ($1,'2026-11-09',1,1)`, [DAD])); }
  catch { childInsert = true; }
  check(g, 'a child cannot INSERT either', childInsert, 'true');
  check(g, "DAD's rows survived every attempt", (await listReflections(pool, DAD)).length, 2);

  // ---- delete ------------------------------------------------------------
  check(g, 'delete one day reports it existed', await deleteReflection(pool, DAD, '2026-11-01'), 'true');
  check(g, 'delete again is a harmless no-op', await deleteReflection(pool, DAD, '2026-11-01'), 'false');
  check(g, 'one row remains', (await listReflections(pool, DAD)).length, 1);
  check(g, 'clearReflections removes the rest', await clearReflections(pool, DAD), 1);
  check(g, 'and the list is empty', (await listReflections(pool, DAD)).length, 0);
  check(g, "MOM clearing her own does not touch DAD's", await (async () => { await saveReflection(pool, DAD, '2026-11-05', 9, 9); await clearReflections(pool, MOM); return (await listReflections(pool, DAD)).length; })(), 1);
}

// ===========================================================================
// C · house rules: opt-in, author-write, co-guardian read-only, isolation
// ===========================================================================
{
  const g = 'C house rules';
  const rules = [{ category: 'bedtime', text: ' 8:00 on school nights ' }, { category: 'screens', text: 'No screens at dinner' }];
  const off = await setHouseRules(pool, DAD, CA, rules);
  check(g, 'rules list off (the default): a write is REFUSED', JSON.stringify(off), JSON.stringify({ ok: false, reason: 'rules_list_off' }));
  check(g, 'and nothing was stored', (await admin.query(`SELECT count(*)::int n FROM guardian_house_rule`)).rows[0].n, 0);

  await setLearnSettings(pool, DAD, { rulesList: true });
  const ok = await setHouseRules(pool, DAD, CA, [...rules, { category: 'style', text: 'authoritative' }, { category: 'safety', text: '' }, null, 7]);
  check(g, 'opted in: only valid core-category rules are stored (style, blank, junk dropped)', JSON.stringify(ok), JSON.stringify({ ok: true, count: 2 }));
  const mine = await houseRulesFor(pool, DAD, CA);
  check(g, 'DAD sees his two as `mine`', mine.mine.length, 2);
  check(g, 'text was trimmed', mine.mine.find((r) => r.category === 'bedtime').text, '8:00 on school nights');
  check(g, 'DAD has no `others`', mine.others.length, 0);

  const moms = await houseRulesFor(pool, MOM, CA);
  check(g, "the OTHER guardian reads DAD's list as `others`", moms.others.length, 2);
  check(g, "MOM's own `mine` is empty", moms.mine.length, 0);
  check(g, 'each rule names its author', moms.others.every((r) => r.authorGuardianId === DAD), 'true');

  // other guardian can read but never write
  const momUpdate = await asMom((q) => q(`UPDATE guardian_house_rule SET body='x' WHERE author_guardian_id=$1 RETURNING id`, [DAD]));
  check(g, "MOM's UPDATE of DAD's rule affects zero rows", momUpdate.length, 0);
  const momDelete = await asMom((q) => q(`DELETE FROM guardian_house_rule WHERE author_guardian_id=$1 RETURNING id`, [DAD]));
  check(g, "MOM's DELETE of DAD's rule affects zero rows", momDelete.length, 0);
  let forged = false;
  try { await asMom((q) => q(`INSERT INTO guardian_house_rule (child_id, author_guardian_id, category, body) VALUES ($1,$2,'bedtime','forged')`, [CA, DAD])); }
  catch { forged = true; }
  check(g, "MOM cannot INSERT a rule in DAD's name", forged, 'true');
  check(g, "DAD's rules are intact", (await houseRulesFor(pool, DAD, CA)).mine.length, 2);

  // who else can see the list
  const sel = `SELECT count(*)::int n FROM guardian_house_rule`;
  check(g, 'the child sees zero rows', (await asChild((q) => q(sel)))[0].n, 0);
  check(g, 'a sitter sees zero rows', (await asSitter((q) => q(sel)))[0].n, 0);
  check(g, 'a step-parent sees zero rows', (await asStep((q) => q(sel)))[0].n, 0);
  check(g, 'the system role sees zero rows', (await withSystemSession(pool, (q) => q(sel)))[0].n, 0);
  check(g, "a guardian of ANOTHER family sees none of family A's rules", (await asStranger((q) => q(sel)))[0].n, 0);
  check(g, "...and houseRulesFor on CA returns nothing for the stranger", (await houseRulesFor(pool, STRANGER, CA)).others.length, 0);

  // cross-family: a guardian cannot write a rule for a child they have no edge to
  await setLearnSettings(pool, STRANGER, { rulesList: true });
  let crossThrew = false;
  try { await setHouseRules(pool, STRANGER, CA, [{ category: 'bedtime', text: 'sneaky' }]); } catch { crossThrew = true; }
  check(g, 'a stranger cannot write a rule for CA (no live edge)', crossThrew, 'true');
  await setHouseRules(pool, STRANGER, CB, [{ category: 'homework', text: 'Reading 20 min' }]);
  check(g, "family B's list is invisible to family A", (await houseRulesFor(pool, DAD, CB)).others.length, 0);
  check(g, "and family A's does not leak into B", (await houseRulesFor(pool, STRANGER, CB)).others.length, 0);

  // replace semantics
  await setHouseRules(pool, DAD, CA, [{ category: 'safety', text: 'Seat belt every ride' }]);
  const rep = await houseRulesFor(pool, DAD, CA);
  check(g, 'a PUT REPLACES the list rather than appending', rep.mine.map((r) => r.category).join(), 'safety');
  check(g, 'an empty list clears it', (await setHouseRules(pool, DAD, CA, [])).count, 0);
  check(g, '...and it is gone for the co-guardian too', (await houseRulesFor(pool, MOM, CA)).others.length, 0);

  // a shared list never outlives its opt-in
  await setHouseRules(pool, DAD, CA, rules);
  check(g, 'precondition: DAD shares two rules again', (await houseRulesFor(pool, MOM, CA)).others.length, 2);
  await setLearnSettings(pool, DAD, { rulesList: false });
  check(g, 'turning rulesList OFF deletes the shared rows in the same transaction', (await houseRulesFor(pool, MOM, CA)).others.length, 0);
  check(g, 'a write is refused again after opting out', (await setHouseRules(pool, DAD, CA, rules)).ok, 'false');

  let catThrew = false;
  try { await admin.query(`INSERT INTO guardian_house_rule (child_id, author_guardian_id, category, body) VALUES ($1,$2,'style','x')`, [CA, DAD]); }
  catch { catThrew = true; }
  check(g, 'the CHECK refuses a non-core category even for a superuser', catThrew, 'true');
  let lenThrew = false;
  try { await admin.query(`INSERT INTO guardian_house_rule (child_id, author_guardian_id, category, body) VALUES ($1,$2,'bedtime',$3)`, [CA, DAD, 'x'.repeat(201)]); }
  catch { lenThrew = true; }
  check(g, 'the CHECK refuses a 201-character body', lenThrew, 'true');
}

// ===========================================================================
// D · structural: FORCE RLS, no leak through exports, cascade on delete
// ===========================================================================
{
  const g = 'D structure';
  const t = await admin.query(
    `SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity FROM pg_class c
       JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname IN ('guardian_learn_settings','guardian_reflection','guardian_house_rule')
      ORDER BY 1`);
  check(g, 'all three tables exist', t.rows.length, 3);
  check(g, 'all three ENABLE row level security', t.rows.every((r) => r.relrowsecurity), 'true');
  check(g, 'all three FORCE row level security', t.rows.every((r) => r.relforcerowsecurity), 'true');
  const pol = await admin.query(`SELECT tablename, policyname FROM pg_policies WHERE tablename IN ('guardian_learn_settings','guardian_reflection','guardian_house_rule') ORDER BY 1,2`);
  check(g, 'settings and reflection each have exactly ONE policy (owner)', pol.rows.filter((p) => p.tablename !== 'guardian_house_rule').length, 2);
  check(g, 'house rules have exactly two (author, co-guardian read)', pol.rows.filter((p) => p.tablename === 'guardian_house_rule').map((p) => p.policyname).join(), 'house_rule_author,house_rule_coguardian_read');
  const hc = await admin.query(`SELECT observed FROM health_check WHERE check_name='rls_unforced'`);
  check(g, 'health_check rls_unforced is zero with the new tables covered', hc.rows[0].observed, '0');

  // No export function may read the new tables. (Source guard: the court/raw/
  // certified exports are explicit queries in pool.ts; none may mention them.)
  const src = readFileSync(new URL('../src/pool.ts', import.meta.url), 'utf8');
  const bodyOf = (name) => {
    const i = src.indexOf(`export async function ${name}`);
    const j = src.indexOf('\nexport ', i + 10);
    return src.slice(i, j);
  };
  for (const fn of ['rawExportBundleFor', 'certifiedExportBundleFor']) {
    const b = bodyOf(fn);
    check(g, `${fn} exists`, b.length > 100, 'true');
    check(g, `${fn} never touches a Parent Learn table`, /guardian_reflection|guardian_learn_settings|guardian_house_rule/.test(b), 'false');
  }
  check(g, 'no migration after 0035 or view in 0035 selects FROM guardian_reflection',
    (readFileSync(new URL('../../../db/migrations/0035_parent_learn.sql', import.meta.url), 'utf8').match(/FROM\s+guardian_reflection/gi) ?? []).length, 0);

  // Deleting the user cascades everything away.
  await admin.query(`DELETE FROM guardian_reflection WHERE guardian_id=$1`, [DAD]);
  await saveReflection(pool, DAD, '2026-11-06', 1, 1).catch(() => {});
  await setLearnSettings(pool, DAD, { rulesList: true });
  await setHouseRules(pool, DAD, CA, [{ category: 'bedtime', text: 'x' }]);
  await admin.query(`DELETE FROM guardianship WHERE user_id=$1`, [DAD]);
  await admin.query(`DELETE FROM app_user WHERE id=$1`, [DAD]);
  const left = (await admin.query(
    `SELECT (SELECT count(*) FROM guardian_learn_settings WHERE guardian_id=$1)
          + (SELECT count(*) FROM guardian_reflection WHERE guardian_id=$1)
          + (SELECT count(*) FROM guardian_house_rule WHERE author_guardian_id=$1) AS n`, [DAD])).rows[0].n;
  check(g, 'deleting the account cascades all three tables', left, '0');
}

await admin.query('BEGIN');
await reset();
await admin.query('COMMIT');
await admin.end();
await pool.end();

let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
