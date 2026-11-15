/**
 * THE LIVE CHAIN, against a real Postgres (server audit G1, G2, G3, G7), on top of the
 * identity lane (sign-up, children, inviter-confirmed guardianship) and the delivery lane
 * (the worker):
 *   sign-up -> a family exists -> invite -> accept -> bootstrap (an account, NO access) ->
 *   the inviter confirms -> the second guardian can ACT -> pair a child device -> bank a
 *   message -> the worker delivers it -> the child reads it.
 *
 * Every step goes through the real Api + registerRoutes() against real tables under
 * real RLS. Sign-up and child creation are the identity lane's routes (their own
 * validation and abuse cases are identity_chain_route.test.mjs); this file proves what the
 * live chain adds on top: the G-37 family caps and the inviter re-check at the one place an
 * invited adult's edge is made, the server's in-process host for the ONE delivery worker
 * (scheduler.mjs runDeliverSweep) including the content-free push, and readiness. Nothing is
 * inserted to stand in for a product step. The ONE thing the test does to the database is
 * move a scheduled instant into the past (the clock); everything on either side of that is
 * the product.
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
import { createPool, dbPort, issueSignupAllowance, setSignupPolicy, deliveryBacklog }
  from '../../packages/db/src/pool.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { registerRoutes } from '../routes.mjs';
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
const created = { users: new Set(), children: new Set() };
const storageRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-live-chain-'));
const storage = new FilesystemStorage(storageRoot);

const SECRET = Buffer.from('c'.repeat(32), 'utf8');
const kicks = { n: 0 };
// strictIds ON: exactly how server/index.mjs boots the real server.
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, storage, { afterMessageBanked: () => { kicks.n++; } });
const call = (a, method, p, tok, body) => a.handle(method, p,
  tok ? { authorization: `Bearer ${tok}` } : {}, body === undefined ? '' : JSON.stringify(body));
const POST = (p, tok, body) => call(api, 'POST', p, tok, body ?? {});
const GET = (p, tok) => call(api, 'GET', p, tok);

// Sign-up policy is global; make sure a previous run or suite did not leave it off.
await setSignupPolicy(pool, { enabled: true, maxAccounts: null });

// A family made ONLY through the product: an operator allowance, POST /v1/auth/signup,
// POST /v1/children. Returns the guardian's session, ids and PIN.
const PIN = '2468';
async function newFamily(label, childTz = 'America/New_York') {
  const { token: allowance } = await issueSignupAllowance(pool, { label: `live-${RUN}` });
  const su = await POST('/v1/auth/signup', null, {
    allowanceToken: allowance, displayName: nm(label), homeTz: 'America/Chicago', pin: PIN });
  if (su.status !== 201) throw new Error(`sign-up failed: ${su.status} ${JSON.stringify(su.body)}`);
  created.users.add(su.body.userId);
  const kid = await POST('/v1/children', su.body.token, {
    displayName: nm('Ivy'), birthDate: '2016-04-02', homeTz: childTz, pin: PIN });
  if (kid.status !== 201) throw new Error(`child failed: ${kid.status} ${JSON.stringify(kid.body)}`);
  created.children.add(kid.body.child.id);
  return { token: su.body.token, userId: su.body.userId, childId: kid.body.child.id };
}
const count = async (sql, params) => Number((await admin.query(sql, params)).rows[0].n);
const usersNamed = (n) => count(`SELECT count(*) AS n FROM app_user WHERE display_name = $1`, [n]);

// ===========================================================================
// C · an invited adult gets a REAL, bounded edge, and only at the inviter's confirm
// ===========================================================================
const mkInvite = async (owner, childId, role, email) => {
  const r = await POST(`/v1/children/${childId}/guardianships`, owner.token,
    { role, label: role, invitedEmail: email, pin: PIN });
  if (r.status !== 201) throw new Error(`invite failed ${r.status} ${JSON.stringify(r.body)}`);
  return r.body.invite.id;
};
// accept + bootstrap: an ACCOUNT, no access
const joinVia = async (inviteId, name) => {
  const acc = await POST(`/v1/guardian-invites/${inviteId}/accept`, null);
  const boot = await POST(`/v1/guardian-invites/${inviteId}/bootstrap`, null, { displayName: name });
  if (boot.body.userId) created.users.add(boot.body.userId);
  return { acc, boot };
};
const confirm = (owner, inviteId) => POST(`/v1/guardian-invites/${inviteId}/confirm`, owner.token, { pin: PIN });
// A reserved, undeliverable test address, assembled from parts: nothing here is anyone's real mailbox.
const email = (p) => `${p}.${RUN}${String.fromCharCode(64)}example.test`;
{
  const owner = await newFamily('Olga');
  const other = await newFamily('Otto');

  const inv = await mkInvite(owner, owner.childId, 'guardian', email('co'));
  const peek = await GET(`/v1/guardian-invites/${inv}`, null);
  check('C invite chain', 'the invited person can read the invite with no session', peek.status, 200);
  const { acc, boot } = await joinVia(inv, nm('Coco'));
  check('C invite chain', 'accept -> 200', acc.status, 200);
  check('C invite chain', 'bootstrap -> 201 with a session and an account',
    `${boot.status}/${typeof boot.body.token}/${typeof boot.body.userId}`, '201/string/string');
  check('C invite chain', 'bootstrap creates NO edge: account first, access second', await count(
    `SELECT count(*) AS n FROM guardianship WHERE child_id=$1 AND user_id=$2`, [owner.childId, boot.body.userId]), 0);
  const coTok = boot.body.token;
  check('C invite chain', 'until the inviter confirms she cannot read the child -> 403',
    (await GET(`/v1/children/${owner.childId}/inbox`, coTok)).status, 403);
  check('C invite chain', 'the inviter\'s confirm needs the inviter\'s OWN PIN (a wrong PIN -> not 200)',
    (await POST(`/v1/guardian-invites/${inv}/confirm`, owner.token, { pin: '0000' })).status === 200, false);
  check('C invite chain', 'a stranger\'s confirm is indistinguishable from "no such invite" -> 404',
    (await POST(`/v1/guardian-invites/${inv}/confirm`, other.token, { pin: PIN })).status, 404);
  const conf = await confirm(owner, inv);
  check('C invite chain', 'the inviter confirms -> 200 with the invite\'s role', `${conf.status}/${conf.body.role}`, '200/guardian');
  const edge = (await admin.query(
    `SELECT role, restricted, observer_only, closed_at FROM guardianship WHERE child_id=$1 AND user_id=$2`,
    [owner.childId, boot.body.userId])).rows;
  check('C invite chain', 'her edge exists, with the invite\'s role and no extra powers',
    JSON.stringify(edge.map((e) => [e.role, e.restricted, e.observer_only, e.closed_at])),
    JSON.stringify([['guardian', false, false, null]]));
  check('C invite chain', 'she can now read the child she was invited to',
    (await GET(`/v1/children/${owner.childId}/inbox`, coTok)).status, 200);
  check('C invite chain', 'but not a child she was NOT invited to',
    (await GET(`/v1/children/${other.childId}/inbox`, coTok)).status, 403);
  check('C invite chain', 'a second confirm does not mint a second edge (409 already_confirmed)',
    `${(await confirm(owner, inv)).status}/${await count(`SELECT count(*) AS n FROM guardianship WHERE child_id=$1`, [owner.childId])}`, '409/2');
  const replay = await POST(`/v1/guardian-invites/${inv}/bootstrap`, null, { displayName: nm('Coco2') });
  check('C invite chain', 'a replayed bootstrap -> 409 already_bootstrapped and no second account',
    `${replay.status}/${replay.body.error}/${await usersNamed(nm('Coco2'))}`, '409/already_bootstrapped/0');

  // she can set her own PIN and mint a pairing code for the child (guardian-only, PIN-gated)
  check('C invite chain', 'she sets her own PIN (no passkey yet, so first-run is allowed)', (await POST('/v1/me/pin', coTok, { pin: '1357' })).status, 200);
  const code = await POST(`/v1/children/${owner.childId}/device-pairing-codes`, coTok, { pin: '1357' });
  check('C invite chain', 'and creates a pairing code for the child she can now see -> 201', code.status, 201);
  const codeOther = await POST(`/v1/children/${other.childId}/device-pairing-codes`, coTok, { pin: '1357' });
  check('C invite chain', "but not for another family's child -> 403", codeOther.status, 403);

  // a sitter gets a sitter's edge, which authorize.ts keeps narrower than a guardian's
  const sInv = await mkInvite(owner, owner.childId, 'sitter', email('sit'));
  const sit = await joinVia(sInv, nm('Sam'));
  await confirm(owner, sInv);
  check('C roles', 'a sitter invite -> a sitter edge (role from the invite, never promoted)', (await admin.query(
    `SELECT role FROM guardianship WHERE child_id=$1 AND user_id=$2`, [owner.childId, sit.boot.body.userId])).rows[0]?.role, 'sitter');
  check('C roles', 'the sitter cannot read the inbox (no message capability) -> 403',
    (await GET(`/v1/children/${owner.childId}/inbox`, sit.boot.body.token)).status, 403);
  check('C roles', 'nor create pairing codes', (await POST(`/v1/children/${owner.childId}/device-pairing-codes`, sit.boot.body.token, { pin: '0000' })).status, 403);
  check('C roles', 'nor create children', (await POST('/v1/children', sit.boot.body.token, { displayName: nm('x'), birthDate: '2018-02-02', homeTz: 'UTC', pin: '0000' })).status === 201, false);

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

// ---- caps (G-37: 4 parents, 8 carers), enforced where the edge is made ------------
{
  const owner = await newFamily('Cap');
  const addEdge = async (role, label) => {
    const u = (await admin.query(`INSERT INTO app_user (display_name, home_tz) VALUES ($1,'UTC') RETURNING id`, [nm(label)])).rows[0].id;
    created.users.add(u);
    await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1,$2,$3,'{}',tstzrange(now() - interval '1 day', null))`, [owner.childId, u, role]);
    return u;
  };
  await addEdge('guardian', 'p2'); await addEdge('step_parent', 'p3');         // owner + 2 = 3 parents live
  // two invites for the 4th parent slot, both through accept + bootstrap, confirmed at the same instant
  const a = await mkInvite(owner, owner.childId, 'guardian', email('capA'));
  const b = await mkInvite(owner, owner.childId, 'step_parent', email('capB'));
  await joinVia(a, nm('CapInvA')); await joinVia(b, nm('CapInvB'));
  const both = await Promise.all([confirm(owner, a), confirm(owner, b)]);
  check('C caps', 'one slot left, two simultaneous confirms: exactly one wins, the other 409 family_full',
    both.map((r) => `${r.status}/${r.body.error ?? 'ok'}`).sort().join(' '), '200/ok 409/family_full');
  check('C caps', 'the child has exactly 4 live parent-class edges', await count(
    `SELECT count(*) AS n FROM guardianship WHERE child_id=$1 AND role IN ('guardian','step_parent','foster_parent')`, [owner.childId]), 4);
  const loser = both[0].status === 409 ? a : b;
  check('C caps', 'the refused invite was not consumed (nothing changed)', await count(
    `SELECT count(*) AS n FROM guardian_invite WHERE id=$1 AND confirmed_at IS NULL`, [loser]), 1);
  // carers: 7 sitters present, the 8th fits, the 9th does not
  for (let i = 0; i < 7; i++) await addEdge('sitter', 'sit' + i);
  const s8i = await mkInvite(owner, owner.childId, 'sitter', email('s8'));
  const s9i = await mkInvite(owner, owner.childId, 'trusted_adult', email('s9'));
  await joinVia(s8i, nm('S8')); await joinVia(s9i, nm('S9'));
  const s8 = await confirm(owner, s8i); const s9 = await confirm(owner, s9i);
  check('C caps', 'the 8th carer fits, the 9th is refused',
    `${s8.status} ${s9.status}/${s9.body.error}`, '200 409/family_full');
  check('C caps', 'carers do not consume parent slots and parents do not consume carer slots', await count(
    `SELECT count(*) AS n FROM guardianship WHERE child_id=$1 AND role NOT IN ('guardian','step_parent','foster_parent')`, [owner.childId]), 8);
}

// ---- the inviter's authority is re-checked when the edge is made --------------------
// An invite is a bearer grant that outlives its inviter's standing. Between "she has an
// account" (bootstrap) and "she has access" (confirm) the inviter may have been restricted
// (protective order), had her edge closed, or lost the guardian role; the confirm must then
// refuse, create nothing and leave the invite open. Each case uses its own family.
{
  const confirmAfter = async (setup) => {
    const owner = await newFamily('Inv');
    const invId = await mkInvite(owner, owner.childId, 'guardian', email('ia' + Math.random().toString(36).slice(2, 7)));
    const j = await joinVia(invId, nm('Heir') + Math.random().toString(36).slice(2, 6));
    await setup(owner);
    const edgesBefore = await count(`SELECT count(*) AS n FROM guardianship WHERE child_id=$1`, [owner.childId]);
    const conf = await confirm(owner, invId);
    const edges = await count(`SELECT count(*) AS n FROM guardianship WHERE child_id=$1`, [owner.childId]);
    const inv = (await admin.query(`SELECT confirmed_at FROM guardian_invite WHERE id=$1`, [invId])).rows[0];
    return { owner, invId, j, conf, edges, edgesBefore, inv };
  };
  const refused = (r) => `${r.conf.status}/${r.conf.body.error}/edges-unchanged=${r.edges === r.edgesBefore}/open=${r.inv.confirmed_at === null}`;

  // The route authorizes the inviter before the model checks standing: a CLOSED, EXPIRED or
  // deleted inviter edge fails the route's own guardian check (403 guardian_session_required /
  // not_a_guardian...), a restricted or demoted one reaches the model (403 inviter_not_guardian).
  // Either way: 403, nothing created, invite still open.
  const R403 = (r) => r.conf.status === 403 && r.edges === r.edgesBefore && r.inv.confirmed_at === null;
  const restricted = await confirmAfter((o) => admin.query(
    `UPDATE guardianship SET restricted = true, order_ref = 'test' WHERE child_id=$1 AND user_id=$2`, [o.childId, o.userId]));
  check('C inviter', 'inviter restricted (protective order) after the invitee has an account -> 403, no edge, invite not consumed', refused(restricted).startsWith('403/'), true);
  check('C inviter', '... and nothing was created or burned', R403(restricted), true);

  const closed = await confirmAfter((o) => admin.query(
    `UPDATE guardianship SET closed_at = now(), closed_reason = 'court_order' WHERE child_id=$1 AND user_id=$2`, [o.childId, o.userId]));
  check('C inviter', 'inviter edge CLOSED -> 403, nothing created', R403(closed), true);

  const expired = await confirmAfter((o) => admin.query(
    `UPDATE guardianship SET expires_at = now() - interval '1 minute' WHERE child_id=$1 AND user_id=$2`, [o.childId, o.userId]));
  check('C inviter', 'inviter edge EXPIRED -> 403, nothing created', R403(expired), true);

  const demoted = await confirmAfter((o) => admin.query(
    `UPDATE guardianship SET role = 'sitter' WHERE child_id=$1 AND user_id=$2`, [o.childId, o.userId]));
  check('C inviter', 'inviter no longer a guardian (now a sitter) -> 403, nothing created', R403(demoted), true);

  const gone = await confirmAfter((o) => admin.query(
    `DELETE FROM guardianship WHERE child_id=$1 AND user_id=$2`, [o.childId, o.userId]));
  check('C inviter', 'inviter edge gone entirely -> 403, nothing created', R403(gone), true);

  // not a permanent burn: restoring her standing lets the SAME invite through
  const again = await newFamily('Inv');
  const invId = await mkInvite(again, again.childId, 'guardian', email('restore'));
  const j = await joinVia(invId, nm('Late'));
  await admin.query(`UPDATE guardianship SET restricted = true, order_ref = 'test' WHERE child_id=$1 AND user_id=$2`, [again.childId, again.userId]);
  const first = await confirm(again, invId);
  await admin.query(`UPDATE guardianship SET restricted = false, order_ref = null WHERE child_id=$1 AND user_id=$2`, [again.childId, again.userId]);
  const second = await confirm(again, invId);
  check('C inviter', 'once her standing is restored the same invite works (the refusal changed nothing)',
    `${first.status} then ${second.status}`, '403 then 200');
  check('C inviter', 'a refusal body carries a reason code only (no names, e-mails or ids)',
    JSON.stringify(Object.keys(first.body)), '["error"]');
  void j;
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

  // a real child session through the real pairing flow
  const pc = await POST(`/v1/children/${fam.childId}/device-pairing-codes`, fam.token, { pin: '2468' });
  const redeem = await POST('/v1/device-pairing/redeem', null, { code: pc.body.numericCode, role: 'child' });
  check('D deliver', 'the child device pairs with a code the new guardian made -> 201', redeem.status, 201);
  const childTok = redeem.body.sessionToken;

  const kicksBefore = kicks.n;
  const sent = await bankMessage(fam);
  check('D deliver', 'POST .../messages -> 201, stored ready at send time (or pending for the worker to time)', ['ready', 'pending'].includes(sent.state), true);
  check('D deliver', 'banking a message nudges the worker (so due messages are not left to the interval)', kicks.n - kicksBefore, 1);
  check('D deliver', 'the inbox is EMPTY before anything has run', (await GET(`/v1/children/${fam.childId}/inbox`, childTok)).body.entries.length, 0);

  const t = tick();
  await drive(t, sent.id, (st) => st !== 'pending');
  check('D deliver', 'the intent has a real scheduled instant and waits (ready)', await stateOf(sent.id), 'ready');
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
  // Host-independent: the worker may run elsewhere (DELIVERY_IN_SERVER=0). A due row nobody has
  // claimed for 20 minutes is visible from the queue alone.
  {
    const fam = await newFamily('Queue');
    const m = await bankMessage(fam);
    await admin.query(`UPDATE delivery_intent SET state='ready', scheduled_at = now() - interval '20 minutes' WHERE id=$1`, [m.id]);
    const external = { status: () => ({ enabled: false }), backlog: () => deliveryBacklog(pool) };
    const stale = await checkReadiness({ pool, migrationsDir, mediaRoot: storageRoot, delivery: external });
    check('E readyz', 'a worker hosted elsewhere is judged by the queue: a due row 20 minutes old -> degraded, still ready',
      JSON.stringify([stale.ready, stale.degraded]), JSON.stringify([true, ['delivery']]));
    await tick().runOnce(); await tick().runOnce();
    const healed = await checkReadiness({ pool, migrationsDir, mediaRoot: storageRoot, delivery: external });
    check('E readyz', 'once the worker has claimed it the queue is healthy again (this row delivered)',
      `${await stateOf(m.id)}/${healed.degraded.includes('delivery')}`, 'delivered/false');
  }
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
  // paired_device.paired_via references device_pairing_code, which a child delete cascades
  // away: remove the devices this run paired first or the delete is refused.
  await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[]) OR target_id = ANY($2::uuid[])`, [kids, users]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [kids]);
  await admin.query(`DELETE FROM signup_allowance WHERE label = $1`, [`live-${RUN}`]);
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
