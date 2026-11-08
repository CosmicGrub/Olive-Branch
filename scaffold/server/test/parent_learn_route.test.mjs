/**
 * server/routes.mjs — Parent Learn routes, against a REAL Postgres.
 * db/migrations/0035_parent_learn.sql; packages/parent-learn/src/learn.ts.
 *
 * Routes:
 *   GET/PUT          /v1/learn/settings
 *   GET/PUT/DELETE   /v1/learn/reflections   (+ DELETE .../reflections/:day)
 *   GET/PUT          /v1/children/:childId/learn/house-rules
 *
 * Proves, through the real Api + registerRoutes + real RLS:
 *   (a) 401 with no token; every route is guardian-only — a child, sitter,
 *       step-parent and coordinator are refused (403) before any data moves.
 *   (b) settings default to the private defaults, PUT is a validated partial
 *       patch (unknown field, wrong type, bad enum, empty body -> 400).
 *   (c) a reflection is only stored once the guardian opted in (409
 *       otherwise), is validated (day, 0-100 integers, unknown keys -> 400)
 *       and is readable only by its author — the co-guardian's GET is empty.
 *   (d) house rules: refused until opted in (409); strict body validation;
 *       the co-guardian reads them as `others` but a PUT only ever replaces
 *       the CALLER's own list; turning the setting off removes them.
 *   (e) an unrelated guardian is refused on a child they have no edge to.
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

const DAD = '11111111-1111-4111-9111-0000000000e1';
const MOM = '22222222-2222-4222-9222-0000000000e1';
const SITTER = '77777777-7777-4777-9777-0000000000e1';
const STEP = '88888888-8888-4888-9888-0000000000e1';
const COORD = '44444444-4444-4444-9444-0000000000e1';
const STRANGER = '99999999-9999-4999-9999-0000000000e1';
const CHILD = '55555555-5555-4555-9555-0000000000e1';
const OTHER_CHILD = '55555555-5555-4555-9555-0000000000e2';
const USERS = [DAD, MOM, SITTER, STEP, COORD, STRANGER];

async function cleanup() {
  await admin.query(`DELETE FROM guardian_house_rule WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM guardian_reflection WHERE guardian_id = ANY($1::uuid[])`, [USERS]);
  await admin.query(`DELETE FROM guardian_learn_settings WHERE guardian_id = ANY($1::uuid[])`, [USERS]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [USERS]);
}
await cleanup();

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Mom','America/Denver'),
     ($3,'Sitter Sue','America/New_York'), ($4,'Stepdad Sam','America/New_York'),
     ($5,'Coordinator Cara','America/New_York'), ($6,'Stranger','America/New_York')`,
  [DAD, MOM, SITTER, STEP, COORD, STRANGER]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2019-04-02','America/Los_Angeles'), ($2,'Eli','2018-01-01','America/Denver')`,
  [CHILD, OTHER_CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1,$2,'guardian','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$3,'guardian','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$4,'sitter','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$5,'step_parent','{}',tstzrange(now() - interval '1 year', null)),
     ($1,$6,'coordinator','{}',tstzrange(now() - interval '1 year', null)),
     ($7,$8,'guardian','{}',tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, MOM, SITTER, STEP, COORD, OTHER_CHILD, STRANGER]);
await admin.query('COMMIT');

const SECRET = Buffer.from('e'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const tok = (userId, roleName, childId = null) =>
  issueSession(SECRET, { userId, roleName, childId, escalated: false }, NOW);
const T = {
  dad: tok(DAD, 'guardian'), mom: tok(MOM, 'guardian'), stranger: tok(STRANGER, 'guardian'),
  sitter: tok(SITTER, 'sitter'), step: tok(STEP, 'step_parent'), coord: tok(COORD, 'coordinator'),
  child: tok(null, 'child', CHILD),
};
const call = (method, path, token, body) => api.handle(
  method, path, token ? { authorization: `Bearer ${token}` } : {},
  body === undefined ? '' : JSON.stringify(body));
const today = new Date().toISOString().slice(0, 10);

// ===========================================================================
// A · authentication and guardian-only, on EVERY route
// ===========================================================================
{
  const g = 'A auth + guardian-only';
  const routes = [
    ['GET', '/v1/learn/settings'], ['PUT', '/v1/learn/settings', { messageCheck: true }],
    ['GET', '/v1/learn/reflections'], ['PUT', '/v1/learn/reflections', { day: today, warmth: 5, expectations: 5 }],
    ['DELETE', `/v1/learn/reflections/${today}`], ['DELETE', '/v1/learn/reflections'],
    ['GET', `/v1/children/${CHILD}/learn/house-rules`],
    ['PUT', `/v1/children/${CHILD}/learn/house-rules`, { rules: [] }],
  ];
  for (const [m, p, b] of routes) {
    check(g, `${m} ${p.replace(/[0-9a-f-]{36}/, ':id')} with no token -> 401`, (await call(m, p, null, b)).status, 401);
    for (const who of ['child', 'sitter', 'step', 'coord']) {
      const r = await call(m, p, T[who], b);
      check(g, `${m} ${p.replace(/[0-9a-f-]{36}/, ':id')} as ${who} -> 403`, r.status, 403);
    }
  }
  check(g, 'nothing was written by any refused call',
    (await admin.query(`SELECT (SELECT count(*) FROM guardian_learn_settings) + (SELECT count(*) FROM guardian_reflection)
       + (SELECT count(*) FROM guardian_house_rule) AS n`)).rows[0].n, '0');
}

// ===========================================================================
// B · settings
// ===========================================================================
{
  const g = 'B settings';
  const d = await call('GET', '/v1/learn/settings', T.dad);
  check(g, 'GET -> 200', d.status, 200);
  check(g, 'defaults: session / neutral / false / false',
    `${d.body.settings.reflection}/${d.body.settings.framing}/${d.body.settings.rulesList}/${d.body.settings.messageCheck}`,
    'session/neutral/false/false');
  const bad = [
    [{}, 'empty_body'], [[], 'body_must_be_object'], ['x', 'body_must_be_object'],
    [{ evil: 1 }, 'unknown_field'], [{ reflection: 'cloud' }, 'bad_reflection'],
    [{ framing: 'x' }, 'bad_framing'], [{ rulesList: 'yes' }, 'bad_rulesList'],
    [{ messageCheck: 1 }, 'bad_messageCheck'], [{ messageCheck: true, extra: 1 }, 'unknown_field'],
  ];
  for (const [b, why] of bad) {
    const r = await call('PUT', '/v1/learn/settings', T.dad, b);
    check(g, `PUT ${JSON.stringify(b)} -> 400 ${why}`, `${r.status} ${r.body.error}`, `400 ${why}`);
  }
  const ok = await call('PUT', '/v1/learn/settings', T.dad, { messageCheck: true });
  check(g, 'a valid patch -> 200', ok.status, 200);
  check(g, '...and returns the merged settings', `${ok.body.settings.messageCheck}/${ok.body.settings.reflection}`, 'true/session');
  const again = await call('GET', '/v1/learn/settings', T.dad);
  check(g, 'GET reflects the write', again.body.settings.messageCheck, 'true');
  check(g, "the co-guardian's settings are separate", (await call('GET', '/v1/learn/settings', T.mom)).body.settings.messageCheck, 'false');
}

// ===========================================================================
// C · reflections: opt-in, validation, author-only
// ===========================================================================
{
  const g = 'C reflections';
  const body = { day: today, warmth: 70, expectations: 60 };
  const off = await call('PUT', '/v1/learn/reflections', T.dad, body);
  check(g, 'session-only (default): PUT -> 409 reflection_storage_off', `${off.status} ${off.body.error}`, '409 reflection_storage_off');
  check(g, 'and GET stays empty', (await call('GET', '/v1/learn/reflections', T.dad)).body.reflections.length, 0);

  await call('PUT', '/v1/learn/settings', T.dad, { reflection: 'saved' });
  const bads = [
    [{ ...body, day: '2026-13-01' }, 'bad_day'], [{ ...body, day: '2026-02-30' }, 'bad_day'],
    [{ ...body, day: 'yesterday' }, 'bad_day'], [{ ...body, day: '1999-12-31' }, 'bad_day'],
    [{ ...body, day: '2999-01-01' }, 'bad_day'], [{ ...body, warmth: 101 }, 'bad_warmth'],
    [{ ...body, warmth: -1 }, 'bad_warmth'], [{ ...body, warmth: 5.5 }, 'bad_warmth'],
    [{ ...body, expectations: '50' }, 'bad_expectations'], [{ day: today, warmth: 5 }, 'bad_expectations'],
    [{ ...body, mood: 'sad' }, 'unknown_field'], [[], 'body_must_be_object'],
  ];
  for (const [b, why] of bads) {
    const r = await call('PUT', '/v1/learn/reflections', T.dad, b);
    check(g, `PUT ${JSON.stringify(b).slice(0, 60)} -> 400 ${why}`, `${r.status} ${r.body.error}`, `400 ${why}`);
  }
  const ok = await call('PUT', '/v1/learn/reflections', T.dad, body);
  check(g, "opted in: PUT -> 200", ok.status, 200);
  const list = await call('GET', '/v1/learn/reflections', T.dad);
  check(g, 'GET returns it', `${list.body.reflections.length}/${list.body.reflections[0].day}/${list.body.reflections[0].warmth}`, `1/${today}/70`);
  check(g, "the CO-GUARDIAN's GET is empty (author-only)", (await call('GET', '/v1/learn/reflections', T.mom)).body.reflections.length, 0);
  check(g, "an unrelated guardian's GET is empty", (await call('GET', '/v1/learn/reflections', T.stranger)).body.reflections.length, 0);

  const del = await call('DELETE', `/v1/learn/reflections/${today}`, T.dad);
  check(g, 'DELETE :day -> 200 existed', `${del.status} ${del.body.existed}`, '200 true');
  const del2 = await call('DELETE', `/v1/learn/reflections/${today}`, T.dad);
  check(g, 'DELETE again is idempotent', `${del2.status} ${del2.body.existed}`, '200 false');
  check(g, 'DELETE with a bad day -> 400', (await call('DELETE', '/v1/learn/reflections/not-a-day', T.dad)).status, 400);
  await call('PUT', '/v1/learn/reflections', T.dad, body);
  await call('PUT', '/v1/learn/reflections', T.dad, { ...body, day: '2026-01-02' });
  const clr = await call('DELETE', '/v1/learn/reflections', T.dad);
  check(g, 'DELETE all clears everything and reports the count', `${clr.status} ${clr.body.removed}`, '200 2');
  check(g, 'MOM clearing hers cannot touch DAD\'s', await (async () => {
    await call('PUT', '/v1/learn/reflections', T.dad, body);
    await call('DELETE', '/v1/learn/reflections', T.mom);
    return (await call('GET', '/v1/learn/reflections', T.dad)).body.reflections.length;
  })(), 1);
}

// ===========================================================================
// D · house rules
// ===========================================================================
{
  const g = 'D house rules';
  const path = `/v1/children/${CHILD}/learn/house-rules`;
  const good = { rules: [{ category: 'bedtime', text: '8:00 on school nights' }, { category: 'screens', text: 'No screens at dinner' }] };
  const off = await call('PUT', path, T.dad, good);
  check(g, 'rules list off (default): PUT -> 409 rules_list_off', `${off.status} ${off.body.error}`, '409 rules_list_off');

  await call('PUT', '/v1/learn/settings', T.dad, { rulesList: true });
  const bads = [
    [{}, 'bad_rules'], [{ rules: 'x' }, 'bad_rules'], [{ rules: [{ category: 'style', text: 'x' }] }, 'bad_rules'],
    [{ rules: [{ category: 'bedtime', text: '' }] }, 'bad_rules'], [{ rules: [{ category: 'bedtime', text: 'x'.repeat(201) }] }, 'bad_rules'],
    [{ rules: [{ category: 'bedtime', text: 'ok', note: 'extra' }] }, 'bad_rules'],
    [{ rules: Array.from({ length: 21 }, () => ({ category: 'bedtime', text: 'x' })) }, 'bad_rules'],
    [{ rules: [], extra: 1 }, 'unknown_field'], [[], 'body_must_be_object'], [{ rules: [null] }, 'bad_rules'],
  ];
  for (const [b, why] of bads) {
    const r = await call('PUT', path, T.dad, b);
    check(g, `PUT ${JSON.stringify(b).slice(0, 55)} -> 400 ${why}`, `${r.status} ${r.body.error}`, `400 ${why}`);
  }
  const ok = await call('PUT', path, T.dad, good);
  check(g, 'opted in: PUT -> 200 with the count', `${ok.status} ${ok.body.count}`, '200 2');
  const dad = await call('GET', path, T.dad);
  check(g, 'DAD GET: two `mine`, no `others`', `${dad.body.mine.length}/${dad.body.others.length}`, '2/0');
  const mom = await call('GET', path, T.mom);
  check(g, "MOM GET: DAD's two as `others`, none `mine`", `${mom.body.others.length}/${mom.body.mine.length}`, '2/0');

  // MOM is not opted in: her PUT is refused, and cannot touch DAD's list.
  const momPut = await call('PUT', path, T.mom, { rules: [{ category: 'safety', text: 'Seat belt' }] });
  check(g, "MOM (not opted in) PUT -> 409", momPut.status, 409);
  await call('PUT', '/v1/learn/settings', T.mom, { rulesList: true });
  const momPut2 = await call('PUT', path, T.mom, { rules: [{ category: 'safety', text: 'Seat belt' }] });
  check(g, 'MOM opted in: PUT -> 200', momPut2.status, 200);
  const dad2 = await call('GET', path, T.dad);
  check(g, "MOM's PUT replaced only HER list: DAD still has his two", `${dad2.body.mine.length}/${dad2.body.others.length}`, '2/1');

  check(g, 'the child path with a sitter is refused', (await call('GET', path, T.sitter)).status, 403);
  check(g, 'an unrelated guardian on this child -> 403 (no edge)', (await call('GET', path, T.stranger)).status, 403);
  check(g, 'an unrelated guardian PUT on this child -> 403', (await call('PUT', path, T.stranger, good)).status, 403);
  const strangerOwn = await call('GET', `/v1/children/${OTHER_CHILD}/learn/house-rules`, T.stranger);
  check(g, "the stranger's OWN child shows none of family A's rules", `${strangerOwn.status}/${strangerOwn.body.others.length}`, '200/0');
  check(g, "DAD cannot read the stranger's child", (await call('GET', `/v1/children/${OTHER_CHILD}/learn/house-rules`, T.dad)).status, 403);

  await call('PUT', '/v1/learn/settings', T.dad, { rulesList: false });
  const mom2 = await call('GET', path, T.mom);
  check(g, "DAD turning the setting off removes his list from MOM's view", `${mom2.body.others.length}`, '0');
  check(g, 'and MOM still has her own', mom2.body.mine.length, 1);
}

await cleanup();
await admin.end();
await pool.end();

let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
