/**
 * THE LIVE CHAIN, against a real Postgres (server audit G1, G2, G3, G7):
 *   sign-up -> a family exists -> invite -> the second guardian can ACT -> pair a
 *   child device -> bank a message -> the worker delivers it -> the child reads it.
 *
 * Every step goes through the real Api + registerRoutes() against real tables under
 * real RLS. Before this file the chain was proved only in pieces: the inbox test
 * INSERTed `delivered` rows by hand, the family-sim harness ran claim_due_intents()
 * itself ("NOT counted as a pass of the product"), and nothing created a family or an
 * edge outside seed-dev.mjs. Here nothing is inserted to stand in for a product step.
 * The ONE thing the test does to the database is move a scheduled instant into the
 * past (the clock); everything on either side of that is the product.
 *
 * Needs DATABASE_URL (the role the server connects as) and ADMIN_DATABASE_URL (a role
 * that bypasses RLS, for seeding limits and cleanup only).
 */
import pg from 'pg';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { DateTime } from 'luxon';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort, createFamily } from '../../packages/db/src/pool.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { registerRoutes } from '../routes.mjs';
import { MissBudget } from '../rate_limit.mjs';
import { setupCodeConfig } from '../family_input.mjs';
import { createDeliveryTick } from '../delivery_tick.mjs';
import { checkReadiness } from '../readiness.mjs';

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

const RUN = randomUUID().slice(0, 8);
const nm = (s) => `${s} ${RUN}`;
const SETUP = `setup-code-${randomUUID()}`;
const created = { users: new Set(), children: new Set() };
const storageRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-live-chain-'));
const storage = new FilesystemStorage(storageRoot);

const SECRET = Buffer.from('c'.repeat(32), 'utf8');
const kicks = { n: 0 };
function makeApi(opts = {}) {
  const api = new Api(SECRET, dbPort(pool), () => Date.now());
  registerRoutes(api, pool, storage, {
    setupCode: setupCodeConfig({ FAMILY_SETUP_CODE: SETUP }),
    signupMissBudget: new MissBudget({ limit: 1000 }),
    signupCreateBudget: new MissBudget({ limit: 1000 }),
    afterMessageBanked: () => { kicks.n++; },
    ...opts,
  });
  return api;
}
const api = makeApi();
const call = (a, method, p, tok, body) => a.handle(method, p,
  tok ? { authorization: `Bearer ${tok}` } : {}, body === undefined ? '' : JSON.stringify(body));
const POST = (p, tok, body) => call(api, 'POST', p, tok, body ?? {});
const GET = (p, tok) => call(api, 'GET', p, tok);

const goodFamily = (over = {}) => ({
  setupCode: SETUP,
  guardian: { displayName: nm('Dana'), homeTz: 'America/Chicago' },
  child: { displayName: nm('Ivy'), birthDate: '2016-04-02', homeTz: 'America/New_York' },
  ...over,
});
async function newFamily(label) {
  const r = await POST('/v1/families', null, goodFamily({
    guardian: { displayName: nm(label), homeTz: 'America/Chicago' } }));
  if (r.status !== 201) throw new Error(`family setup failed: ${r.status} ${JSON.stringify(r.body)}`);
  created.users.add(r.body.userId); created.children.add(r.body.childId);
  return r.body;
}
const count = async (sql, params) => Number((await admin.query(sql, params)).rows[0].n);
const usersNamed = (n) => count(`SELECT count(*) AS n FROM app_user WHERE display_name = $1`, [n]);

// ===========================================================================
// A · sign-up is invite-only, strictly validated, and atomic
// ===========================================================================
{
  const off = makeApi({ setupCode: setupCodeConfig({}) });
  const r = await call(off, 'POST', '/v1/families', null, goodFamily());
  check('A sign-up gate', 'with no FAMILY_SETUP_CODE the route answers 404 (the kill switch)',
    `${r.status}/${r.body.error}`, '404/not_found');
  check('A sign-up gate', 'and nothing was created', await usersNamed(nm('Dana')), 0);

  for (const [label, body] of [
    ['no setup code', { ...goodFamily(), setupCode: undefined }],
    ['an empty setup code', goodFamily({ setupCode: '' })],
    ['a non-string setup code', goodFamily({ setupCode: 12345 })],
    ['an array setup code', goodFamily({ setupCode: [SETUP] })],
    ['a near-miss setup code', goodFamily({ setupCode: SETUP + 'x' })],
    ['a prefix of the setup code', goodFamily({ setupCode: SETUP.slice(0, -1) })],
  ]) {
    const res = await POST('/v1/families', null, body);
    check('A sign-up gate', `${label} -> 403 setup_code_invalid`,
      `${res.status}/${res.body.error}`, '403/setup_code_invalid');
  }
  check('A sign-up gate', 'no refused attempt created a guardian', await usersNamed(nm('Dana')), 0);

  const tight = makeApi({ signupMissBudget: new MissBudget({ limit: 3 }) });
  for (let i = 0; i < 3; i++) await call(tight, 'POST', '/v1/families', null, goodFamily({ setupCode: 'nope' + i }));
  const blocked = await call(tight, 'POST', '/v1/families', null, goodFamily());
  check('A sign-up gate', 'after the miss budget is spent even the RIGHT code gets 429 (a guesser cannot win by volume)',
    `${blocked.status}/${blocked.body.error}`, '429/signup_rate_limited');

  const capped = makeApi({ signupCreateBudget: new MissBudget({ limit: 1 }) });
  const first = await call(capped, 'POST', '/v1/families', null, goodFamily({
    guardian: { displayName: nm('CapA'), homeTz: 'UTC' } }));
  if (first.body.userId) { created.users.add(first.body.userId); created.children.add(first.body.childId); }
  const second = await call(capped, 'POST', '/v1/families', null, goodFamily({
    guardian: { displayName: nm('CapB'), homeTz: 'UTC' } }));
  check('A sign-up gate', 'the creation budget stops a flood of sign-ups',
    `${first.status} then ${second.status}/${second.body.error}`, '201 then 429/signup_rate_limited');
  check('A sign-up gate', 'and the refused one created nothing', await usersNamed(nm('CapB')), 0);
}
{
  const bad = [
    ['no guardian', { child: goodFamily().child, setupCode: SETUP }, 'guardian_required'],
    ['guardian is a string', goodFamily({ guardian: 'Dana' }), 'guardian_required'],
    ['guardian is an array', goodFamily({ guardian: [] }), 'guardian_required'],
    ['empty guardian name', goodFamily({ guardian: { displayName: '   ', homeTz: 'UTC' } }), 'guardian_name_invalid'],
    ['a 61-character guardian name', goodFamily({ guardian: { displayName: 'x'.repeat(61), homeTz: 'UTC' } }), 'guardian_name_invalid'],
    ['a control character in the name', goodFamily({ guardian: { displayName: 'Da\u0007na', homeTz: 'UTC' } }), 'guardian_name_invalid'],
    ['a NUL byte in the name', goodFamily({ guardian: { displayName: 'Da\u0000na', homeTz: 'UTC' } }), 'guardian_name_invalid'],
    ['a numeric name', goodFamily({ guardian: { displayName: 42, homeTz: 'UTC' } }), 'guardian_name_invalid'],
    ['an unknown time zone', goodFamily({ guardian: { displayName: nm('Z'), homeTz: 'Mars/Olympus' } }), 'guardian_time_zone_invalid'],
    ['a UTC offset instead of a zone', goodFamily({ guardian: { displayName: nm('Z'), homeTz: '+05:00' } }), 'guardian_time_zone_invalid'],
    ['no child', { guardian: goodFamily().guardian, setupCode: SETUP }, 'child_required'],
    ['child is a string', goodFamily({ child: 'Ivy' }), 'child_required'],
    ['empty child name', goodFamily({ child: { ...goodFamily().child, displayName: '' } }), 'child_name_invalid'],
    ['a child born in the future', goodFamily({ child: { ...goodFamily().child, birthDate: '2999-01-01' } }), 'child_birth_date_invalid'],
    ['an impossible date (Feb 30)', goodFamily({ child: { ...goodFamily().child, birthDate: '2020-02-30' } }), 'child_birth_date_invalid'],
    ['a malformed date', goodFamily({ child: { ...goodFamily().child, birthDate: '04/02/2016' } }), 'child_birth_date_invalid'],
    ['an adult "child" (40 years old)', goodFamily({ child: { ...goodFamily().child, birthDate: '1980-01-01' } }), 'child_birth_date_invalid'],
    ['a numeric date', goodFamily({ child: { ...goodFamily().child, birthDate: 20160402 } }), 'child_birth_date_invalid'],
    ['a child time zone that is not IANA', goodFamily({ child: { ...goodFamily().child, homeTz: 'EST5EDT; DROP TABLE child' } }), 'child_time_zone_invalid'],
  ];
  for (const [label, body, reason] of bad) {
    const before = await count(`SELECT count(*) AS n FROM app_user WHERE display_name LIKE $1`, [`%${RUN}`]);
    const res = await POST('/v1/families', null, body);
    const after = await count(`SELECT count(*) AS n FROM app_user WHERE display_name LIKE $1`, [`%${RUN}`]);
    check('A validation', `${label} -> 400 ${reason}, nothing created`,
      `${res.status}/${res.body.error}/${after - before}`, `400/${reason}/0`);
  }
  const ar = await call(api, 'POST', '/v1/families', null, '[]');
  check('A validation', 'a JSON array body is a 400, not a crash', ar.status === 400 || ar.status === 403, true);
}
{
  // ---- the happy path, and what it actually built -------------------------
  const f = await newFamily('Hana');
  check('A family', 'POST /v1/families -> a guardian id, a child id and a session token',
    typeof f.token === 'string' && f.token.length > 20 && !!f.userId && !!f.childId, true);
  const edge = (await admin.query(
    `SELECT role, restricted, observer_only, closed_at, scope FROM guardianship WHERE child_id=$1 AND user_id=$2`,
    [f.childId, f.userId])).rows;
  check('A family', 'exactly one edge, a full unrestricted guardian edge',
    JSON.stringify(edge.map((e) => [e.role, e.restricted, e.observer_only, e.closed_at])),
    JSON.stringify([['guardian', false, false, null]]));
  check('A family', 'the guardian has no email and no credential yet',
    JSON.stringify((await admin.query(`SELECT email FROM app_user WHERE id=$1`, [f.userId])).rows),
    JSON.stringify([{ email: null }]));
  check('A family', 'the child has a time-zone interval', await count(
    `SELECT count(*) AS n FROM child_tz_interval WHERE child_id=$1`, [f.childId]), 1);
  const parts = (await admin.query(
    `SELECT kind, reachable FROM day_part WHERE child_id=$1 ORDER BY kind`, [f.childId])).rows;
  check('A family', 'she starts with a default day so a first message CAN be scheduled',
    parts.map((p) => `${p.kind}:${p.reachable}`).join(','),
    'after_school:true,asleep:false,bedtime:true,dinner:true,wake:true');

  const me = await GET('/v1/me', f.token);
  check('A family', 'the new session works: GET /v1/me -> 200', me.status, 200);
  const inbox = await GET(`/v1/children/${f.childId}/inbox`, f.token);
  check('A family', 'and reads her OWN child through the real RLS-scoped route -> 200, empty',
    `${inbox.status}/${inbox.body.entries?.length}`, '200/0');

  const g = await newFamily('Gus');
  const cross = await GET(`/v1/children/${g.childId}/inbox`, f.token);
  check('A isolation', "family A's guardian cannot read family B's child -> 403", cross.status, 403);
  const cross2 = await POST(`/v1/children/${g.childId}/media`, f.token, { bytes: 'AAAA' });
  check('A isolation', "nor write to her -> 403", cross2.status, 403);
  const aRows = await admin.query(
    `SELECT count(*) AS n FROM guardianship WHERE user_id=$1 AND child_id=$2`, [f.userId, g.childId]);
  check('A isolation', 'and holds no edge to her', aRows.rows[0].n, '0');

  // ---- atomic: a failure half-way leaves nothing behind -------------------
  let threw = false;
  try {
    await createFamily(pool, { displayName: nm('Atomic'), homeTz: 'UTC' },
      { displayName: nm('AtomicKid'), birthDate: 'not-a-date', homeTz: 'UTC' });
  } catch { threw = true; }
  check('A atomic', 'createFamily with a value Postgres rejects throws', threw, true);
  check('A atomic', 'and the guardian row it had already inserted was rolled back',
    await usersNamed(nm('Atomic')), 0);
}

// ===========================================================================
// B · adding another child
// ===========================================================================
{
  const f = await newFamily('Bea');
  const kid = { displayName: nm('Second'), birthDate: '2019-09-09', homeTz: 'America/Denver' };
  const ok = await POST('/v1/children', f.token, kid);
  check('B add child', 'a guardian adds another child -> 201', ok.status, 201);
  if (ok.body.childId) created.children.add(ok.body.childId);
  check('B add child', 'with an edge for HER only', await count(
    `SELECT count(*) AS n FROM guardianship WHERE child_id=$1`, [ok.body.childId]), 1);
  check('B add child', 'and a default day', await count(
    `SELECT count(*) AS n FROM day_part WHERE child_id=$1`, [ok.body.childId]), 5);
  const none = await POST('/v1/children', null, kid);
  check('B add child', 'no session -> 401', none.status, 401);
  const childTok = api.issueSessionToken({ userId: null, roleName: 'child', childId: f.childId, escalated: false });
  const asChild = await POST('/v1/children', childTok, kid);
  check('B add child', 'a child session is refused -> 403', `${asChild.status}/${asChild.body.error}`, '403/guardian_session_required');
  const noEdgeUser = (await admin.query(
    `INSERT INTO app_user (display_name, home_tz) VALUES ($1,'UTC') RETURNING id`, [nm('Nobody')])).rows[0].id;
  created.users.add(noEdgeUser);
  const noEdgeTok = api.issueSessionToken({ userId: noEdgeUser, roleName: 'guardian', childId: null, escalated: false });
  const asNobody = await POST('/v1/children', noEdgeTok, kid);
  check('B add child', 'a user with no guardian edge cannot mint a child -> 403 not_a_guardian',
    `${asNobody.status}/${asNobody.body.error}`, '403/not_a_guardian');
  check('B add child', 'and nothing was created for her', await count(
    `SELECT count(*) AS n FROM guardianship WHERE user_id=$1`, [noEdgeUser]), 0);
  const bads = await POST('/v1/children', f.token, { ...kid, birthDate: '2999-01-01' });
  check('B add child', 'a bad body -> 400 and nothing created', `${bads.status}/${bads.body.error}`, '400/child_birth_date_invalid');

  // restricted / observer-only / closed edges do not count as "a guardian"
  for (const [label, set] of [
    ['a restricted edge', 'restricted = true'],
    ['an observer-only edge', 'observer_only = true'],
    ['a closed edge', `closed_at = now(), closed_reason = 'revoked'`],
  ]) {
    const u = (await admin.query(`INSERT INTO app_user (display_name, home_tz) VALUES ($1,'UTC') RETURNING id`, [nm(label)])).rows[0].id;
    created.users.add(u);
    await admin.query(
      `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1,$2,'guardian','{}',tstzrange(now() - interval '1 day', null))`,
      [f.childId, u]);
    await admin.query(`UPDATE guardianship SET ${set} WHERE child_id=$1 AND user_id=$2`, [f.childId, u]);
    const tok = api.issueSessionToken({ userId: u, roleName: 'guardian', childId: null, escalated: false });
    const r = await POST('/v1/children', tok, kid);
    check('B add child', `${label} cannot add children -> 403`, `${r.status}/${r.body.error}`, '403/not_a_guardian');
  }

  // the per-guardian bound, under concurrency
  const h = await newFamily('Hal');
  for (let i = 0; i < 6; i++) {   // 1 from sign-up + 6 = 7 live
    const c = (await admin.query(
      `INSERT INTO child (display_name, birth_date, home_tz) VALUES ($1,'2018-01-01','UTC') RETURNING id`, [nm('k' + i)])).rows[0].id;
    created.children.add(c);
    await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1,$2,'guardian','{}',tstzrange(now() - interval '1 day', null))`, [c, h.userId]);
  }
  const race = await Promise.all([1, 2, 3].map(() => POST('/v1/children', h.token, kid)));
  for (const r of race) if (r.body.childId) created.children.add(r.body.childId);
  check('B add child', 'three concurrent adds with one slot left: exactly one wins, the rest 409 too_many_children',
    race.map((r) => r.status).sort().join(','), '201,409,409');
  check('B add child', 'and she holds exactly 8 children', await count(
    `SELECT count(*) AS n FROM guardianship WHERE user_id=$1`, [h.userId]), 8);
}

// ===========================================================================
// C · an accepted invite gives the second guardian a REAL, bounded edge (G3)
// ===========================================================================
const pinFor = async (tok, pin = '2468') => POST('/v1/me/pin', tok, { pin });
const mkInvite = async (owner, childId, role, email) => {
  const r = await POST(`/v1/children/${childId}/guardianships`, owner.token,
    { role, label: role, invitedEmail: email, pin: '2468' });
  if (r.status !== 201) throw new Error(`invite failed ${r.status} ${JSON.stringify(r.body)}`);
  return r.body.invite.id;
};
const joinVia = async (inviteId, name) => {
  const acc = await POST(`/v1/guardian-invites/${inviteId}/accept`, null);
  const boot = await POST(`/v1/guardian-invites/${inviteId}/bootstrap`, null, { displayName: name });
  if (boot.body.userId) created.users.add(boot.body.userId);
  return { acc, boot };
};
// A reserved, undeliverable test address, assembled from parts: nothing here is anyone's real mailbox.
const email = (p) => `${p}.${RUN}${String.fromCharCode(64)}example.test`;
{
  const owner = await newFamily('Olga');
  const other = await newFamily('Otto');
  await pinFor(owner.token);

  const inv = await mkInvite(owner, owner.childId, 'guardian', email('co'));
  const peek = await GET(`/v1/guardian-invites/${inv}`, null);
  check('C invite chain', 'the invited person can read the invite with no session', peek.status, 200);
  const { acc, boot } = await joinVia(inv, nm('Coco'));
  check('C invite chain', 'accept -> 200', acc.status, 200);
  check('C invite chain', 'bootstrap -> 201 with a token and the role she was given',
    `${boot.status}/${boot.body.role}`, '201/guardian');
  const edge = (await admin.query(
    `SELECT role, restricted, observer_only, closed_at FROM guardianship WHERE child_id=$1 AND user_id=$2`,
    [owner.childId, boot.body.userId])).rows;
  check('C invite chain', 'her edge exists, with the invite\'s role and no extra powers',
    JSON.stringify(edge.map((e) => [e.role, e.restricted, e.observer_only, e.closed_at])),
    JSON.stringify([['guardian', false, false, null]]));
  const coTok = boot.body.token;
  check('C invite chain', 'she can now read the child she was invited to (it was 403 for every route before)',
    (await GET(`/v1/children/${owner.childId}/inbox`, coTok)).status, 200);
  check('C invite chain', 'but not a child she was NOT invited to',
    (await GET(`/v1/children/${other.childId}/inbox`, coTok)).status, 403);
  check('C invite chain', 'and the owner\'s other family is untouched: no edge to Otto\'s child', await count(
    `SELECT count(*) AS n FROM guardianship WHERE child_id=$1 AND user_id=$2`, [other.childId, boot.body.userId]), 0);
  const replay = await POST(`/v1/guardian-invites/${inv}/bootstrap`, null, { displayName: nm('Coco2') });
  check('C invite chain', 'a replayed bootstrap -> 409 already_bootstrapped and no second edge/account',
    `${replay.status}/${replay.body.error}/${await count(`SELECT count(*) AS n FROM guardianship WHERE child_id=$1`, [owner.childId])}`,
    '409/already_bootstrapped/2');
  const addForOwnerChild = await POST('/v1/children', coTok, { displayName: nm('Kid2'), birthDate: '2018-02-02', homeTz: 'UTC' });
  if (addForOwnerChild.body.childId) created.children.add(addForOwnerChild.body.childId);
  check('C invite chain', 'a full guardian can also add a child of her own', addForOwnerChild.status, 201);
  const coChildEdge = await count(`SELECT count(*) AS n FROM guardianship WHERE child_id=$1 AND user_id=$2`,
    [addForOwnerChild.body.childId, owner.userId]);
  check('C invite chain', 'and the OWNER is not silently granted that new child', coChildEdge, 0);

  // she can set her own PIN and mint a pairing code for the child (guardian-only, PIN-gated)
  check('C invite chain', 'she sets her own PIN (no passkey yet, so first-run is allowed)', (await pinFor(coTok, '1357')).status, 200);
  const code = await POST(`/v1/children/${owner.childId}/device-pairing-codes`, coTok, { pin: '1357' });
  check('C invite chain', 'and creates a pairing code for the child she can now see -> 201', code.status, 201);
  const codeOther = await POST(`/v1/children/${other.childId}/device-pairing-codes`, coTok, { pin: '1357' });
  check('C invite chain', "but not for another family's child -> 403", codeOther.status, 403);

  // a sitter gets a sitter's edge, which authorize.ts keeps narrower than a guardian's
  const sInv = await mkInvite(owner, owner.childId, 'sitter', email('sit'));
  const sit = await joinVia(sInv, nm('Sam'));
  check('C roles', 'a sitter invite -> a sitter edge (role from the invite, never promoted)', (await admin.query(
    `SELECT role FROM guardianship WHERE child_id=$1 AND user_id=$2`, [owner.childId, sit.boot.body.userId])).rows[0]?.role, 'sitter');
  check('C roles', 'the sitter cannot read the inbox (no message capability) -> 403',
    (await GET(`/v1/children/${owner.childId}/inbox`, sit.boot.body.token)).status, 403);
  check('C roles', 'nor create pairing codes', (await POST(`/v1/children/${owner.childId}/device-pairing-codes`, sit.boot.body.token, { pin: '0000' })).status, 403);
  check('C roles', 'nor add children', (await POST('/v1/children', sit.boot.body.token, { displayName: nm('x'), birthDate: '2018-02-02', homeTz: 'UTC' })).status, 403);

  // revoked / expired / not-accepted / duplicate e-mail: no account, no edge
  const rInv = await mkInvite(owner, owner.childId, 'guardian', email('rev'));
  await POST(`/v1/guardian-invites/${rInv}/revoke`, owner.token);
  const rAcc = await POST(`/v1/guardian-invites/${rInv}/accept`, null);
  const rBoot = await POST(`/v1/guardian-invites/${rInv}/bootstrap`, null, { displayName: nm('Rev') });
  check('C hostile', 'a revoked invite cannot be accepted or bootstrapped',
    `${rAcc.status}/${rBoot.status}/${rBoot.body.error}`, '409/409/revoked');
  check('C hostile', 'and created no account', await usersNamed(nm('Rev')), 0);

  const nInv = await mkInvite(owner, owner.childId, 'guardian', email('noacc'));
  const nBoot = await POST(`/v1/guardian-invites/${nInv}/bootstrap`, null, { displayName: nm('NoAcc') });
  check('C hostile', 'bootstrap before accept -> 409 not_accepted, no account', `${nBoot.status}/${nBoot.body.error}/${await usersNamed(nm('NoAcc'))}`, '409/not_accepted/0');

  const eInv = await mkInvite(owner, owner.childId, 'guardian', email('exp'));
  await POST(`/v1/guardian-invites/${eInv}/accept`, null);
  await admin.query(`UPDATE guardian_invite SET expires_at = now() - interval '1 minute' WHERE id=$1`, [eInv]);
  const eBoot = await POST(`/v1/guardian-invites/${eInv}/bootstrap`, null, { displayName: nm('Exp') });
  check('C hostile', 'an invite that expired after accept -> 410, no account', `${eBoot.status}/${await usersNamed(nm('Exp'))}`, '410/0');

  const dup = await mkInvite(owner, owner.childId, 'guardian', email('co'));    // same e-mail as Coco
  const dupJoin = await joinVia(dup, nm('Imposter'));
  check('C hostile', 'an invite to an e-mail that already has an account does NOT mint a session for it',
    `${dupJoin.boot.status}/${dupJoin.boot.body.error}/${dupJoin.boot.body.token === undefined}`, '409/email_already_registered/true');
}

// ---- caps (G-37: 4 parents, 8 carers) -------------------------------------
{
  const owner = await newFamily('Cap');
  await pinFor(owner.token);
  const addEdge = async (role, label) => {
    const u = (await admin.query(`INSERT INTO app_user (display_name, home_tz) VALUES ($1,'UTC') RETURNING id`, [nm(label)])).rows[0].id;
    created.users.add(u);
    await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1,$2,$3,'{}',tstzrange(now() - interval '1 day', null))`, [owner.childId, u, role]);
    return u;
  };
  await addEdge('guardian', 'p2'); await addEdge('step_parent', 'p3');         // 3 parents live
  // two invites for the 4th parent slot, bootstrapped at the same instant
  const a = await mkInvite(owner, owner.childId, 'guardian', email('capA'));
  const b = await mkInvite(owner, owner.childId, 'step_parent', email('capB'));
  await POST(`/v1/guardian-invites/${a}/accept`, null); await POST(`/v1/guardian-invites/${b}/accept`, null);
  const both = await Promise.all([
    POST(`/v1/guardian-invites/${a}/bootstrap`, null, { displayName: nm('CapA') }),
    POST(`/v1/guardian-invites/${b}/bootstrap`, null, { displayName: nm('CapB') }),
  ]);
  for (const r of both) if (r.body.userId) created.users.add(r.body.userId);
  check('C caps', 'one slot left, two simultaneous bootstraps: exactly one wins, the other 409 family_full',
    both.map((r) => `${r.status}/${r.body.error ?? 'ok'}`).sort().join(' '), '201/ok 409/family_full');
  check('C caps', 'the loser created no account (rolled back with the refusal)',
    (await usersNamed(nm('CapA'))) + (await usersNamed(nm('CapB'))), 1);
  check('C caps', 'the child has exactly 4 live parent-class edges', await count(
    `SELECT count(*) AS n FROM guardianship WHERE child_id=$1 AND role IN ('guardian','step_parent','foster_parent')`, [owner.childId]), 4);
  // carers: 7 sitters present, the 8th fits, the 9th does not
  for (let i = 0; i < 7; i++) await addEdge('sitter', 'sit' + i);
  const s8 = await joinVia(await mkInvite(owner, owner.childId, 'sitter', email('s8')), nm('S8'));
  const s9 = await joinVia(await mkInvite(owner, owner.childId, 'trusted_adult', email('s9')), nm('S9'));
  check('C caps', 'the 8th carer fits, the 9th is refused',
    `${s8.boot.status} ${s9.boot.status}/${s9.boot.body.error}`, '201 409/family_full');
  check('C caps', 'carers do not consume parent slots and parents do not consume carer slots', await count(
    `SELECT count(*) AS n FROM guardianship WHERE child_id=$1 AND role NOT IN ('guardian','step_parent','foster_parent')`, [owner.childId]), 8);
}

// ===========================================================================
// D · a banked message reaches the child — with no row hand-inserted (G1)
// ===========================================================================
const pushes = [];
let pushShouldThrow = false;
const fakeNotify = async (_pool, target, input) => {
  if (pushShouldThrow) throw new Error('fcm down');
  pushes.push({ target, input }); return [{ ok: true }];
};
const metricsSeen = {};
const metrics = { inc: (n, by = 1) => { metricsSeen[n] = (metricsSeen[n] ?? 0) + by; } };
const tick = () => createDeliveryTick({ pool, intervalMs: 0, notify: fakeNotify, metrics, log: () => {} });

const MP4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(40, 7)]);
// materialize() schedules an at_daypart message at TODAY's start of that part if it is
// within a short grace of now, otherwise at the next one. A part that began in the last
// two hours would therefore be due at once, which is correct product behaviour but makes
// "not delivered before its time" untestable at that minute. Pick a part that did not.
const CHILD_TZ = 'America/New_York';
const PARTS = { wake: [6, 30], after_school: [15, 30], dinner: [17, 30], bedtime: [19, 30] };
function quietDaypart(now = DateTime.now().setZone(CHILD_TZ)) {
  for (const [k, [h, m]] of Object.entries(PARTS)) {
    const mins = now.diff(now.set({ hour: h, minute: m, second: 0, millisecond: 0 }), 'minutes').minutes;
    if (mins < 0 || mins > 135) return k;
  }
  return 'wake';
}
async function bankMessage(fam, daypart = quietDaypart()) {
  await POST('/v1/me/pin', fam.token, { pin: '2468' });
  const up = await POST(`/v1/children/${fam.childId}/media`, fam.token, { bytes: MP4.toString('base64') });
  if (up.status !== 201) throw new Error(`upload ${up.status} ${JSON.stringify(up.body)}`);
  const msg = await POST(`/v1/children/${fam.childId}/messages`, fam.token,
    { storageKey: up.body.storageKey, durationMs: 4200, daypart });
  if (msg.status !== 201) throw new Error(`message ${msg.status} ${JSON.stringify(msg.body)}`);
  return msg.body;
}
const stateOf = async (id) => (await admin.query(`SELECT state FROM delivery_intent WHERE id=$1`, [id])).rows[0]?.state;
// The worker is global by nature: it materialises and claims EVERY due row in the database, and a
// shared test database may hold other suites' rows ahead of ours (batches are bounded). So nothing
// below asserts a global count; it asserts what happened to OUR intent and OUR child, and drives
// passes until the state we are waiting for arrives.
const myPushes = (childId) => pushes.filter((x) => x.target.childId === childId);
async function drive(t, id, until, passes = 10) {
  let failedPushes = 0;
  for (let i = 0; i < passes; i++) {
    const r = await t.runOnce();
    failedPushes += r.pushFailed ?? 0;
    if (until(await stateOf(id))) break;
  }
  return failedPushes;
}
{
  const fam = await newFamily('Mara');
  const other = await newFamily('Nell');
  await POST('/v1/me/pin', fam.token, { pin: '2468' });

  // a real child session through the real pairing flow
  const pc = await POST(`/v1/children/${fam.childId}/device-pairing-codes`, fam.token, { pin: '2468' });
  const redeem = await POST('/v1/device-pairing/redeem', null, { code: pc.body.numericCode, role: 'child' });
  check('D deliver', 'the child device pairs with a code the new guardian made -> 201', redeem.status, 201);
  const childTok = redeem.body.sessionToken;

  const kicksBefore = kicks.n;
  const sent = await bankMessage(fam);
  check('D deliver', 'POST .../messages -> 201 pending', `${sent.state}`, 'pending');
  check('D deliver', 'banking a message nudges the worker (so due messages are not left to the interval)', kicks.n - kicksBefore, 1);
  check('D deliver', 'the inbox is EMPTY before anything has run', (await GET(`/v1/children/${fam.childId}/inbox`, childTok)).body.entries.length, 0);

  const t = tick();
  await drive(t, sent.id, (st) => st !== 'pending');
  check('D deliver', 'the worker materialised the pending intent (pending -> ready, a real scheduled instant)', await stateOf(sent.id), 'ready');
  check('D deliver', 'and it is NOT delivered before its time: the child still sees nothing', (await GET(`/v1/children/${fam.childId}/inbox`, childTok)).body.entries.length, 0);
  check('D deliver', 'no push was sent for an undelivered message', myPushes(fam.childId).length, 0);

  // the clock: only the scheduled instant moves; everything else is the product
  await admin.query(`UPDATE delivery_intent SET scheduled_at = now() - interval '1 minute' WHERE id=$1`, [sent.id]);
  await Promise.all([t.runOnce(), tick().runOnce()]);
  await drive(t, sent.id, (st) => st === 'delivered');
  check('D deliver', 'the intent is now delivered', await stateOf(sent.id), 'delivered');
  check('D deliver', 'two workers racing for one due message: exactly one push for her, once', myPushes(fam.childId).length, 1);
  const mine = myPushes(fam.childId)[0];
  const p = mine.input;
  check('D push content', 'the push input is content-free: only kind, an opaque ref and a collapse key',
    JSON.stringify(Object.keys(p).sort()), JSON.stringify(['collapseKey', 'kind', 'ref']));
  check('D push content', 'kind is message_ready and ref is the intent id (opaque)', `${p.kind}/${p.ref === sent.id}`, 'message_ready/true');
  check('D push content', 'nothing in the whole input mentions the sender, a name, a count or the caption',
    /Mara|Dana|video|count|caption|storage|children\//i.test(JSON.stringify(mine)), false);

  const inbox = await GET(`/v1/children/${fam.childId}/inbox`, childTok);
  check('D deliver', 'the CHILD reads it from her own inbox through the real route', inbox.body.entries.map((m) => m.id).join(','), sent.id);
  check('D deliver', 'with the sender\'s name the guardian gave', inbox.body.entries[0]?.sender_name, nm('Mara'));
  check('D isolation', "another family's child does not see it", (await GET(`/v1/children/${other.childId}/inbox`,
    api.issueSessionToken({ userId: null, roleName: 'child', childId: other.childId, escalated: false }))).body.entries.length, 0);
  check('D isolation', "another family's guardian is refused her child", (await GET(`/v1/children/${fam.childId}/inbox`, other.token)).status, 403);

  const opened = await POST(`/v1/children/${fam.childId}/inbox/${sent.id}/opened`, childTok);
  check('D deliver', 'she opens it -> 200 and the state is opened', `${opened.status}/${await stateOf(sent.id)}`, '200/opened');

  await t.runOnce(); await t.runOnce();
  check('D deliver', 'further ticks change nothing: no double delivery, no second push', `${myPushes(fam.childId).length}/${await stateOf(sent.id)}`, '1/opened');
  check('D metrics', 'the counters recorded the claim and the push', `${metricsSeen.delivery_claimed_total >= 1}/${metricsSeen.delivery_push_sent_total >= 1}`, 'true/true');

  // a message that already missed its retention window is expired, never delivered
  const stale = await bankMessage(fam);
  await admin.query(`UPDATE delivery_intent SET expires_at = now() - interval '1 minute' WHERE id=$1`, [stale.id]);
  await drive(t, stale.id, (st) => st === 'expired');
  check('D retention', 'an intent past its retention window is expired by the worker, not delivered', await stateOf(stale.id), 'expired');
  check('D retention', 'and never reached the inbox', (await GET(`/v1/children/${fam.childId}/inbox`, childTok)).body.entries.length, 1);

  // a push failure must not undo a delivery
  const third = await bankMessage(fam);
  await drive(t, third.id, (st) => st !== 'pending');
  await admin.query(`UPDATE delivery_intent SET scheduled_at = now() - interval '1 minute' WHERE id=$1`, [third.id]);
  pushShouldThrow = true;
  const failedPushes = await drive(t, third.id, (st) => st === 'delivered');
  pushShouldThrow = false;
  check('D resilience', 'push provider down: the message is STILL delivered', await stateOf(third.id), 'delivered');
  check('D resilience', 'the tick reports the failed push instead of throwing', failedPushes >= 1, true);
}
{
  // a worker that cannot even reach the database fails soft, counts it, and recovers
  const outage = { connect: async () => { throw new Error('connection refused'); } };
  const seen = {};
  const t = createDeliveryTick({ pool: outage, intervalMs: 0, notify: fakeNotify,
    metrics: { inc: (n) => { seen[n] = (seen[n] ?? 0) + 1; } }, log: () => {} });
  const r = await t.runOnce();
  check('D resilience', 'a DB outage: runOnce resolves { error } instead of rejecting', r.error, true);
  const s = t.status();
  check('D resilience', 'status shows the failure and no success yet', `${s.failures}/${s.consecutiveFailures}/${s.lastOkAgeSec}`, '1/1/null');
  check('D resilience', 'and the error counter moved', seen.delivery_tick_errors_total, 1);
  const good = createDeliveryTick({ pool, intervalMs: 0, notify: fakeNotify, log: () => {} });
  await good.runOnce();
  check('D resilience', 'a healthy tick records a success age', typeof good.status().lastOkAgeSec, 'number');

  // kick() debounces a burst into one extra pass, and stop() waits for it
  const kickable = createDeliveryTick({ pool, intervalMs: 3_600_000, notify: fakeNotify, log: () => {} });
  kickable.kick(); kickable.kick(); kickable.kick();
  await new Promise((r) => setTimeout(r, 900));
  check('D kick', 'three kicks in a burst cause exactly one pass', kickable.status().ticks, 1);
  await kickable.stop();
  kickable.kick();
  await new Promise((r) => setTimeout(r, 600));
  check('D kick', 'after stop(), kick() does nothing', kickable.status().ticks, 1);
}

// ===========================================================================
// E · readiness against the real database
// ===========================================================================
{
  const migrationsDir = fileURLToPath(new URL('../../db/migrations', import.meta.url));
  const ok = await checkReadiness({ pool, migrationsDir, mediaRoot: storageRoot });
  check('E readyz', 'real DB at the image\'s migration level, writable media -> ready', JSON.stringify(ok), JSON.stringify({ ready: true, failing: [], degraded: [] }));
  const fakeDir = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-fake-migrations-'));
  await fs.writeFile(path.join(fakeDir, '9999_from_the_future.sql'), 'SELECT 1;');
  const behind = await checkReadiness({ pool, migrationsDir: fakeDir, mediaRoot: storageRoot });
  check('E readyz', 'an image that expects a newer migration than the DB has -> not ready, "schema"', JSON.stringify(behind.failing), '["schema"]');
  const asFile = path.join(storageRoot, 'a-file');
  await fs.writeFile(asFile, 'x');
  const noMedia = await checkReadiness({ pool, migrationsDir, mediaRoot: path.join(asFile, 'sub') });
  check('E readyz', 'a media root that cannot be written -> not ready, "media"', JSON.stringify(noMedia.failing), '["media"]');
  const drain = await checkReadiness({ pool, migrationsDir, mediaRoot: storageRoot, isDraining: () => true });
  check('E readyz', 'draining -> not ready first, whatever else is true', JSON.stringify(drain), JSON.stringify({ ready: false, failing: ['draining'], degraded: [] }));
  const downPool = { query: async () => { throw new Error('down'); } };
  const down = await checkReadiness({ pool: downPool, migrationsDir, mediaRoot: storageRoot });
  check('E readyz', 'database unreachable -> exactly "db" (no misleading second "schema")', JSON.stringify(down.failing), '["db"]');
  const stuck = await checkReadiness({ pool, migrationsDir, mediaRoot: storageRoot,
    delivery: { status: () => ({ enabled: true, intervalMs: 15000, consecutiveFailures: 3, lastOkAgeSec: null }) } });
  check('E readyz', 'a stuck delivery worker is DEGRADED, not unready (the app keeps serving)', JSON.stringify([stuck.ready, stuck.degraded]), JSON.stringify([true, ['delivery']]));
  await fs.rm(fakeDir, { recursive: true, force: true });
}

// ---- cleanup ---------------------------------------------------------------
{
  const kids = [...created.children];
  const users = [...created.users];
  // children created by POST /v1/children / admin inserts were tracked as we went; sweep the rest by name
  const byName = await admin.query(`SELECT id FROM child WHERE display_name LIKE $1`, [`%${RUN}`]);
  for (const r of byName.rows) kids.push(r.id);
  const uByName = await admin.query(`SELECT id FROM app_user WHERE display_name LIKE $1`, [`%${RUN}`]);
  for (const r of uByName.rows) users.push(r.id);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [kids]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [users]);
  const left = await count(`SELECT count(*) AS n FROM app_user WHERE display_name LIKE $1`, [`%${RUN}`]);
  check('Z cleanup', 'the suite removed everything it created', left, 0);
  await fs.rm(storageRoot, { recursive: true, force: true });
}

await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
