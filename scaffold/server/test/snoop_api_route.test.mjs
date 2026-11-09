/**
 * server/test/snoop_api_route.test.mjs — anti-snooping at the API, against REAL
 * Postgres and REAL row-level security through the real Api + registerRoutes +
 * registerGameTableRoutes wiring (server-snoop hardening, spec 4.4/4.5):
 *
 *   A  tripwire: every `:xId` path parameter AND every play / co-view / relay
 *      route is audited here (extends security_round2_route's IDOR table to the
 *      relay surface, which lives in game_tables.mjs)
 *   B  relay routes against real edges: not-yours, unknown and stranger are one answer
 *   C  re-check at mint time and session revocation
 *   D  credential failures are uniform
 *   E  the live schema: no network-identity columns or types, RLS forced
 *      everywhere, the app role is not a superuser and cannot bypass RLS
 */
import pg from 'pg';
import { randomUUID, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { promises as fs } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';
import { registerRoutes } from '../routes.mjs';
import { registerGameTableRoutes, deriveGameTableSecret } from '../game_tables.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const HERE = path.dirname(fileURLToPath(import.meta.url));
const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CA = 'f3000000-0000-4000-8000-00000000000a';
const CB = 'f3000000-0000-4000-8000-00000000000b';
const GA = 'f4000000-0000-4000-8000-000000000001';
const GB = 'f4000000-0000-4000-8000-000000000002';
const GX = 'f4000000-0000-4000-8000-000000000003'; // guardian whose edge is removed mid-test
const USERS = [GA, GB, GX];
async function cleanup() {
  await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[])`, [[CA, CB, ...USERS]]);
  await admin.query(`DELETE FROM device_pairing_code WHERE created_by = ANY($1::uuid[])`, [USERS]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CA, CB]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CA, CB]]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [USERS]);
}
await cleanup();
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES
  ($1,'Ann','America/Chicago'), ($2,'Bea','America/Chicago'), ($3,'Xan','America/Chicago')`, USERS);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ($1,'Aria','2016-04-02','America/New_York'), ($2,'Bo','2016-04-02','America/New_York')`, [CA, CB]);
const open = `tstzrange(now() - interval '1 year', null)`;
await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
  ($1,$2,'guardian','{}',${open}), ($1,$3,'guardian','{}',${open}), ($4,$5,'guardian','{}',${open})`,
  [CA, GA, GX, CB, GB]);

const storageRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-snoop-'));
const SECRET = randomBytes(32);
const tables = new Map();
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, new FilesystemStorage(storageRoot));
registerGameTableRoutes(api, { secret: deriveGameTableSecret(SECRET), tables });
const NOW = Date.now();
const tok = (p) => issueSession(SECRET, { userId: null, childId: null, escalated: false, ...p }, NOW);
const T = {
  GA: tok({ userId: GA, roleName: 'guardian' }), GB: tok({ userId: GB, roleName: 'guardian' }),
  GX: tok({ userId: GX, roleName: 'guardian' }),
  KA: tok({ roleName: 'child', childId: CA }), KB: tok({ roleName: 'child', childId: CB }),
};
const call = (method, p, t, body, headers = {}) => api.handle(method, p,
  { ...(t ? { authorization: `Bearer ${t}` } : {}), ...headers }, body === undefined ? '' : JSON.stringify(body));
const same = (a, b) => JSON.stringify([a.status, a.body]) === JSON.stringify([b.status, b.body]);

// ===========================================================================
// A · tripwire
// ===========================================================================
{
  const files = ['routes.mjs', 'game_tables.mjs', 'index.mjs'];
  const src = files.map((f) => readFileSync(path.join(HERE, '..', f), 'utf8')).join('\n');
  const found = [...new Set([...src.matchAll(/path:\s*[`'"]([^`'"]+)[`'"]/g)]
    .flatMap((m) => [...m[1].matchAll(/:(\w+Id)\b/g)].map((x) => x[1])))].filter((p) => p !== 'childId').sort();
  const AUDITED = {
    inviteId: 'guardian_invite (security_round2_route A)', codeId: 'device_pairing_code (security_round2_route A)',
    deviceId: 'revokePairedDevice (security_round2_route A)', sessionId: 'call_log (security_round2_route A)',
    messageId: 'delivery_intent (security_round2_route A)', expenseId: 'resolveExpense (security_round2_route A)',
    medicationId: 'recordDose (security_round2_route A)', itemId: 'setBagItemStatus (security_round2_route A)',
    letterId: 'letter (security_round2_route A)', artifactId: 'mediaArtifactFor (security_round2_route A)',
    passkeyId: 'deletePasskey (security_round2_route A)',
    tableId: 'relay table: in-memory, seat-bound; unknown / not-yours / not-pending are one 404 (this suite, B)',
  };
  check('A tripwire', 'every :xId path parameter across routes.mjs, game_tables.mjs and index.mjs is audited',
    found.filter((p) => !(p in AUDITED)).join(',') || 'none', 'none');
  check('A tripwire', 'and the audited table has no stale entries',
    Object.keys(AUDITED).filter((p) => !found.includes(p)).join(',') || 'none', 'none');

  const paths = [...src.matchAll(/(?:method:\s*['"](\w+)['"],\s*)?path:\s*[`'"]([^`'"]+)[`'"]/g)].map((m) => m[2]);
  const relayish = paths.filter((p) => /game-tables|co-view|coview|relay|\/play|sealed/i.test(p)).sort();
  check('A tripwire', 'the play / co-view / relay HTTP surface is exactly the two audited game-table routes',
    relayish.join(','), '/v1/game-tables,/v1/game-tables/:tableId/join');
  // every route registration carries skipOuterSession (infra tripwire's rule, restated for the relay surface)
  const gt = readFileSync(path.join(HERE, '..', 'game_tables.mjs'), 'utf8');
  check('A tripwire', 'both relay routes are skipOuterSession:true', (gt.match(/skipOuterSession: true/g) ?? []).length, 2);
}

// ===========================================================================
// B · uniform answers against real edges
// ===========================================================================
let tableA;
{
  const ok = await call('POST', '/v1/game-tables', T.GA, { game: 'sealed-v1', partnerChildId: CA });
  tableA = ok.body;
  check('B uniform', 'a guardian opens a sealed table with their own child (real edge)', ok.status, 200);
  check('B uniform', 'the room id is an unguessable capability, not an id of anyone',
    /^t_[A-Za-z0-9_-]{32}$/.test(ok.body.tableId) && !ok.body.tableId.includes(CA.slice(0, 8)), 'true');

  const toOther = await call('POST', '/v1/game-tables', T.GB, { game: 'sealed-v1', partnerChildId: CA });
  const toGhost = await call('POST', '/v1/game-tables', T.GB, { game: 'sealed-v1', partnerChildId: randomUUID() });
  check('B uniform', "another family's guardian cannot open a table with MY child: 403", toOther.status, 403);
  check('B uniform', "...and the answer is identical to opening one with a child that does not exist (no oracle)",
    same(toOther, toGhost), 'true');
  const adultVsAdult = await call('POST', '/v1/game-tables', T.GB, { game: 'sealed-v1', partnerUserId: GA });
  check('B uniform', 'a guardian cannot open a table with another guardian (400, no table made)', adultVsAdult.status, 400);

  const unknown = await call('POST', '/v1/game-tables/t_ghost/join', T.KA, {});
  const wrongKid = await call('POST', `/v1/game-tables/${tableA.tableId}/join`, T.KB, {});
  const wrongAdult = await call('POST', `/v1/game-tables/${tableA.tableId}/join`, T.GB, {});
  check('B uniform', 'unknown table: 404 not_found', `${unknown.status}/${unknown.body.error}`, '404/not_found');
  check('B uniform', "another family's CHILD sees the same 404", same(unknown, wrongKid), 'true');
  check('B uniform', "another family's GUARDIAN sees the same 404", same(unknown, wrongAdult), 'true');
  const malformed = await call('POST', '/v1/game-tables/%E0%A4%A/join', T.KA, {});
  check('B uniform', 'a malformed percent-escape in the table id is a clean 4xx, never a 500', malformed.status < 500, 'true');
  const noAuth = await call('POST', `/v1/game-tables/${tableA.tableId}/join`, undefined, {});
  check('B uniform', 'no session at all is 401, never reveals the table', `${noAuth.status}/${noAuth.body.error}`, '401/no_session');
  const forged = await call('POST', `/v1/game-tables/${tableA.tableId}/join`, T.KA.slice(0, -4) + 'AAAA', {});
  check('B uniform', 'a forged session is 401', forged.status, 401);
}

// ===========================================================================
// C · re-check at mint time, revocation
// ===========================================================================
{
  const mk = await call('POST', '/v1/game-tables', T.GX, { game: 'sealed-v1', partnerChildId: CA });
  check('C revoke', 'a co-guardian opens a table (edge live)', mk.status, 200);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1 AND user_id = $2`, [CA, GX]);
  const join = await call('POST', `/v1/game-tables/${mk.body.tableId}/join`, T.KA, {});
  check('C revoke', "the child's join is refused once the guardian's edge is gone (re-checked at mint time)",
    `${join.status}/${join.body.error}`, '403/not_authorized');
  const again = await call('POST', '/v1/game-tables', T.GX, { game: 'sealed-v1', partnerChildId: CA });
  check('C revoke', 'and the ex-guardian cannot open a new one', again.status, 403);

  // device revocation: a session minted for a paired device dies the moment the device is revoked
  const code = (await admin.query(`INSERT INTO device_pairing_code (role, numeric_code, target_id, created_by)
    VALUES ('child', '987654', $1, $2) RETURNING id`, [CA, GA])).rows[0].id;
  const dev = (await admin.query(`INSERT INTO paired_device (role, target_id, label, paired_via, credential_hash)
    VALUES ('child', $1, 'tablet', $2, $3) RETURNING id`, [CA, code, 'a'.repeat(64)])).rows[0].id;
  const devTok = tok({ roleName: 'child', childId: CA, deviceId: dev });
  const live = await call('POST', `/v1/game-tables/t_probe/join`, devTok, {});
  check('C revoke', 'a live device session is served (404 for a made-up table)', live.status, 404);
  await admin.query(`UPDATE paired_device SET revoked_at = now() WHERE id = $1`, [dev]);
  const dead = await call('POST', `/v1/game-tables/t_probe/join`, devTok, {});
  check('C revoke', 'the same session is 401 device_revoked immediately after revocation',
    `${dead.status}/${dead.body.error}`, '401/device_revoked');
  const deadCreate = await call('POST', '/v1/game-tables', devTok, { game: 'sealed-v1', partnerUserId: GA });
  check('C revoke', '...for the create route too', deadCreate.status, 401);
}

// ===========================================================================
// D · credential failures are uniform
// ===========================================================================
{
  const unknownDev = await call('POST', '/v1/auth/session/refresh', undefined, { deviceId: randomUUID(), deviceCredential: 'x'.repeat(40) });
  const code = (await admin.query(`INSERT INTO device_pairing_code (role, numeric_code, target_id, created_by)
    VALUES ('child', '123456', $1, $2) RETURNING id`, [CB, GB])).rows[0].id;
  const dev = (await admin.query(`INSERT INTO paired_device (role, target_id, label, paired_via, credential_hash)
    VALUES ('child', $1, 'tablet', $2, $3) RETURNING id`, [CB, code, 'b'.repeat(64)])).rows[0].id;
  const wrongCred = await call('POST', '/v1/auth/session/refresh', undefined, { deviceId: dev, deviceCredential: 'y'.repeat(40) });
  check('D creds', 'an unknown device id and a known id with a wrong credential are one answer',
    same(unknownDev, wrongCred), 'true');
  check('D creds', '...401 invalid_device_credential', `${wrongCred.status}/${wrongCred.body.error}`, '401/invalid_device_credential');
  const garbageId = await call('POST', '/v1/auth/session/refresh', undefined, { deviceId: "'; DROP TABLE x;--", deviceCredential: 'z'.repeat(40) });
  check('D creds', 'a garbage device id is the same 401 (never a Postgres cast 500)', same(unknownDev, garbageId), 'true');
  const src = readFileSync(path.join(HERE, '..', '..', 'packages', 'db', 'src', 'pool.ts'), 'utf8');
  check('D creds', 'the device credential is compared with timingSafeEqual over SHA-256 digests',
    /refreshPairedDeviceSession[\s\S]{0,1800}timingSafeEqual\(presented, stored\)/.test(src), 'true');
  check('D creds', 'a session MAC is compared in constant time', /timingSafeEqual\(mac, expect\)/.test(
    readFileSync(path.join(HERE, '..', '..', 'packages', 'auth', 'src', 'auth.ts'), 'utf8')), 'true');
  check('D creds', 'a join token is compared in constant time', /timingSafeEqual\(mac, expect\)/.test(
    readFileSync(path.join(HERE, '..', '..', 'packages', 'game-sync', 'src', 'table.ts'), 'utf8')), 'true');
}

// ===========================================================================
// E · the live schema
// ===========================================================================
{
  const cols = (await admin.query(`SELECT table_name, column_name FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name ~* '(^|_)(ip|ipaddress|ssid|bssid|mac|hostname|latitude|longitude|geo|geolocation|wifi|lan|user_agent|remote_addr)(_|$)'`)).rows;
  check('E schema', 'no column in the live database stores network identity',
    cols.map((c) => `${c.table_name}.${c.column_name}`).join(',') || 'none', 'none');
  const types = (await admin.query(`SELECT count(*)::int AS n FROM information_schema.columns
    WHERE table_schema = 'public' AND data_type IN ('inet','cidr','macaddr','macaddr8','point','USER-DEFINED') AND udt_name IN ('inet','cidr','macaddr','macaddr8','point','geography','geometry')`)).rows[0].n;
  check('E schema', 'no inet / cidr / macaddr / geography column exists', types, 0);
  const unforced = (await admin.query(`SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity AND NOT c.relforcerowsecurity`)).rows;
  check('E schema', 'row-level security is FORCED on every table that has it enabled',
    unforced.map((r) => r.relname).join(',') || 'none', 'none');
  const forced = (await admin.query(`SELECT count(*)::int AS n FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relforcerowsecurity`)).rows[0].n;
  check('E schema', 'forced-RLS tables number at least 41 (a regression that drops one is caught)', forced >= 41, 'true');
  const role = (await pool.query(`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user`)).rows[0];
  check('E schema', 'the app role is NOSUPERUSER and NOBYPASSRLS', `${role.rolsuper}/${role.rolbypassrls}`, 'false/false');
  const funcs = (await admin.query(`SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c ~* '^(app|olive)\\.')`)).rows;
  check('E schema', 'no function-level SET of a custom GUC (the non-superuser migrator rule)',
    funcs.map((r) => r.proname).join(',') || 'none', 'none');
}

await cleanup();
await admin.end();
await pool.end();
await fs.rm(storageRoot, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
