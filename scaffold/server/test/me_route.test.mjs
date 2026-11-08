/**
 * server/routes.mjs — GET /v1/me `yearsOld` (audit C-05: the child age gate
 * was inert because no live client ever learned her age). Real Postgres,
 * real Api.handle() — including the global child-payload sweep, which bans
 * the key `age` (packages/globalaudit GLOBAL_CHILD_FORBIDDEN) and is exactly
 * why this field is `yearsOld`.
 *
 *   A · a child session gets whole years computed server-side from
 *       child.birth_date, against her own home-zone calendar date; a
 *       birthday that is still tomorrow has not happened yet.
 *   B · the birth date itself never appears in the response.
 *   C · a guardian session gets yearsOld === null (a per-child signal).
 */
import pg from 'pg';
import { DateTime } from 'luxon';
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

const DAD = 'aaaaaaaa-1111-4a1a-9a1a-0000000000a5';
const FIVE = 'bbbbbbbb-2222-4b1b-9b1b-0000000000a5';      // turned 5 today
const ALMOST_SIX = 'cccccccc-3333-4c1c-9c1c-0000000000a5'; // turns 6 tomorrow
const CHILDREN = [FIVE, ALMOST_SIX];

const cleanup = async () => {
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [CHILDREN]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [CHILDREN]);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
};
await cleanup();

// Both children live in Pacific/Auckland so "today" is her zone's date, not
// the server's: compute the birth dates from the same zone the route uses.
const TZ = 'Pacific/Auckland';
const today = DateTime.now().setZone(TZ).startOf('day');
const isoDate = (d) => d.toISODate();
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'Five',$3,$5), ($2,'AlmostSix',$4,$5)`,
  [FIVE, ALMOST_SIX, isoDate(today.minus({ years: 5 })),
   isoDate(today.minus({ years: 6 }).plus({ days: 1 })), TZ]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [FIVE, DAD]);

const SECRET = Buffer.from('m'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);
const childTok = (id) => issueSession(SECRET,
  { userId: null, roleName: 'child', childId: id, escalated: false }, NOW);
const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const me = (tok) => api.handle('GET', '/v1/me', { authorization: `Bearer ${tok}` }, '');

{
  const five = await me(childTok(FIVE));
  check('A yearsOld', 'a child session is 200 (the child-payload sweep did not trip on the key)',
    five.status, 200);
  check('A yearsOld', 'a child whose 5th birthday is today is 5', five.body.yearsOld, 5);
  check('A yearsOld', 'it is an integer number, not a string', typeof five.body.yearsOld, 'number');

  const almost = await me(childTok(ALMOST_SIX));
  check('A yearsOld', 'a child whose 6th birthday is tomorrow is still 5', almost.body.yearsOld, 5);

  check('B privacy', 'no birth date field is returned to the child',
    JSON.stringify(five.body).includes(isoDate(today.minus({ years: 5 }))), false);
  check('B privacy', 'and the banned key `age` is not what carries it',
    'age' in five.body, false);
}
{
  const dad = await me(dadTok);
  check('C guardian', 'a guardian session -> 200', dad.status, 200);
  check('C guardian', 'yearsOld is null for a guardian caller', dad.body.yearsOld === null, true);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
