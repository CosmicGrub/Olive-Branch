/**
 * server/test/security_round2_route.test.mjs — the database-backed half of the
 * round-2 security audit fixes, driven through the REAL Api + registerRoutes
 * wiring (api.handle) against REAL Postgres and REAL row-level security.
 * (The pure half is server/test/security_round2.test.mjs; the table-by-table
 * RLS matrix is packages/db/test/edge_rls.test.mjs.)
 *
 *   A  S-B5   IDOR: another family's medication / expense / bag item, and a
 *             tripwire that every `:xId` path parameter has been audited
 *   B  S-B3   passkeys: PIN step-up, user-verification flag, cap, list, delete
 *   C  S-B3   the security-event feed (co-guardian sees it, others do not)
 *             and the PIN-gated raw/certified export
 *   D  S-B1   pairing-code redeem: the global miss budget
 *   E  S-B6/8 uploads: magic bytes, image size, in-flight cap, byte quota
 *   F  S-B9   message storageKey validation (prefix, ledger, uploader, blob, reuse)
 *   G  S-B8   the orphan sweeper + the served MIME
 *   H  S-B14  malformed uuid path parameters are 400 on the real Api
 */
import pg from 'pg';
import { randomUUID, randomBytes, createHash, generateKeyPairSync } from 'node:crypto';
import { promises as fs, readFileSync } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { issueSession, hashPin } from '../../packages/auth/src/auth.mjs';
import { registerRoutes, RP_ID, RP_ORIGIN } from '../routes.mjs';
import { MissBudget, InFlightLimiter } from '../rate_limit.mjs';
import { serveSignedMedia } from '../signed_media.mjs';
import { runOrphanMediaSweep } from '../../tools/scheduler.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const HERE = path.dirname(fileURLToPath(import.meta.url));
const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CA = 'f1000000-0000-4000-8000-00000000000a';
const CB = 'f1000000-0000-4000-8000-00000000000b';
const GA1 = 'f2000000-0000-4000-8000-000000000001';   // guardian of CA, has a PIN
const GA2 = 'f2000000-0000-4000-8000-000000000002';   // co-guardian of CA, has a PIN
const GB  = 'f2000000-0000-4000-8000-000000000003';   // guardian of CB, has a PIN
const NEWU = 'f2000000-0000-4000-8000-000000000004';  // brand-new account: no PIN, no passkey (bootstrap)
const STR = 'f2000000-0000-4000-8000-000000000005';   // guardian with no edge
const USERS = [GA1, GA2, GB, NEWU, STR];
const PIN = '135790';

async function cleanup() {
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete');
  for (const t of ['message_log', 'expense', 'export_record', 'medication_dose', 'medication',
                   'exchange_bag_item', 'delivery_intent', 'media_artifact', 'day_part',
                   'device_pairing_code', 'paired_device']) {
    if (['device_pairing_code', 'paired_device'].includes(t)) continue;
    await admin.query(`DELETE FROM ${t} WHERE child_id = ANY($1::uuid[])`, [[CA, CB]]);
  }
  await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete');
  await admin.query(`DELETE FROM media_upload WHERE child_id = ANY($1::uuid[])`, [[CA, CB]]);
  await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[])`, [[CA, CB, ...USERS]]);
  await admin.query(`DELETE FROM device_pairing_code WHERE created_by = ANY($1::uuid[])`, [USERS]);
  await admin.query(`DELETE FROM guardian_invite WHERE invited_by = ANY($1::uuid[])`, [USERS]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CA, CB]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CA, CB]]);   // security_event cascades
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [USERS]);
}
await cleanup();

await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Ann','America/Chicago'), ($2,'Alex','America/Chicago'), ($3,'Bea','America/Chicago'),
     ($4,'Newbie','America/Chicago'), ($5,'Stranger','America/Chicago')`, USERS);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Aria','2016-04-02','America/New_York'), ($2,'Bo','2016-04-02','America/New_York')`, [CA, CB]);
const open = `tstzrange(now() - interval '1 year', null)`;
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1,$2,'guardian','{}',${open}), ($1,$3,'guardian','{}',${open}), ($4,$5,'guardian','{}',${open})`,
  [CA, GA1, GA2, CB, GB]);
await admin.query(
  `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
   VALUES ($1,'bedtime','20:30','21:00','{0,1,2,3,4,5,6}', true, '[2020-01-01,2099-01-01)')`, [CA]);
for (const u of [GA1, GA2, GB]) {
  await admin.query(`INSERT INTO pin_credential (user_id, pin_hash) VALUES ($1, $2)`, [u, hashPin(PIN)]);
}
// Family B's private objects, owned by GB.
const medB = (await admin.query(
  `INSERT INTO medication (child_id, name, dose, slots) VALUES ($1,'BMed','1 tab','["am"]'::jsonb) RETURNING id`, [CB])).rows[0].id;
const medA = (await admin.query(
  `INSERT INTO medication (child_id, name, dose, slots) VALUES ($1,'AMed','1 tab','["am"]'::jsonb) RETURNING id`, [CA])).rows[0].id;
const expB = (await admin.query(
  `INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule, description)
   VALUES ($1,$2,500,'other',current_date,'{}'::jsonb,'b-expense') RETURNING id`, [CB, GB])).rows[0].id;
const bagB = (await admin.query(
  `INSERT INTO exchange_bag_item (child_id, label) VALUES ($1,'b-bag') RETURNING id`, [CB])).rows[0].id;

const storageRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-sec2-route-'));
const storage = new FilesystemStorage(storageRoot);
const SECRET = randomBytes(32);
let clock = 1_000_000;
const missBudget = new MissBudget({ limit: 3, windowMs: 60_000, now: () => clock });
const uploadLimiter = new InFlightLimiter({ max: 1 });
const QUOTA = 3000;
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, storage, {
  pairingMissBudget: missBudget, uploadLimiter, mediaChildQuotaBytes: QUOTA,
});

const NOW = Date.now();
const tok = (userId, roleName = 'guardian') =>
  issueSession(SECRET, { userId, roleName, childId: null, escalated: false }, NOW);
const childTok = (childId) => issueSession(SECRET, { userId: null, roleName: 'child', childId, escalated: false }, NOW);
const T = { GA1: tok(GA1), GA2: tok(GA2), GB: tok(GB), NEWU: tok(NEWU), STR: tok(STR), KID: childTok(CA) };
const call = (method, p, t, body, headers = {}) => api.handle(method, p,
  { ...(t ? { authorization: `Bearer ${t}` } : {}), ...headers },
  body === undefined ? '' : JSON.stringify(body));
const withPin = { 'x-guardian-pin': PIN };

// ===========================================================================
// A · S-B5 — IDOR
// ===========================================================================
{
  const before = (await admin.query(`SELECT count(*)::int AS n FROM medication_dose`)).rows[0].n;
  const idor = await call('POST', `/v1/children/${CA}/medications/${medB}/doses`, T.GA1, { slot: 'am' });
  check('A IDOR', "family A's guardian logging a dose against FAMILY B's medication id is 404 medication_not_found",
    `${idor.status}/${idor.body.error}`, '404/medication_not_found');
  check('A IDOR', 'the 404 discloses nothing (no display name, no by/at fields)', Object.keys(idor.body).join(), 'error');
  check('A IDOR', 'no dose row was written anywhere',
    (await admin.query(`SELECT count(*)::int AS n FROM medication_dose`)).rows[0].n, before);
  // The audit's exact exploit: B's real dose exists; A's guardian tries to "mark it given" / read the name.
  const bReal = await call('POST', `/v1/children/${CB}/medications/${medB}/doses`, T.GB, { slot: 'am' });
  check('A IDOR', "positive control: family B's own guardian logs B's dose", bReal.status, 201);
  const idor2 = await call('POST', `/v1/children/${CA}/medications/${medB}/doses`, T.GA1, { slot: 'am' });
  check('A IDOR', "and now that B's dose exists, A's guardian still gets 404 — NOT 409 already_administered with B's parent's name",
    `${idor2.status}/${idor2.body.by ?? 'no-name'}`, '404/no-name');
  const aReal = await call('POST', `/v1/children/${CA}/medications/${medA}/doses`, T.GA1, { slot: 'am' });
  check('A IDOR', "positive control: A's guardian logs A's own medication", aReal.status, 201);
  const aAgain = await call('POST', `/v1/children/${CA}/medications/${medA}/doses`, T.GA2, { slot: 'am' });
  check('A IDOR', 'and the real double-dose guard still works for the co-guardian (409)', `${aAgain.status}/${aAgain.body.error}`, '409/already_administered');
  check('A IDOR', '...naming the co-guardian by name, inside the SAME family', aAgain.body.by, 'Ann');

  const exp = await call('POST', `/v1/children/${CA}/expenses/${expB}/accept`, T.GA1, {});
  check('A IDOR', "resolving FAMILY B's expense under family A's child is 404 expense_not_found", `${exp.status}/${exp.body.error}`, '404/expense_not_found');
  check('A IDOR', "and B's expense is untouched",
    (await admin.query(`SELECT status FROM expense WHERE id = $1`, [expB])).rows[0].status, 'proposed');
  const bag = await call('POST', `/v1/children/${CA}/exchange/bag-items/${bagB}`, T.GA1, { sent: true });
  check('A IDOR', "setting FAMILY B's bag item under family A's child is 404 bag_item_not_found", `${bag.status}/${bag.body.error}`, '404/bag_item_not_found');
  check('A IDOR', "and B's bag item is untouched",
    (await admin.query(`SELECT sent FROM exchange_bag_item WHERE id = $1`, [bagB])).rows[0].sent, false);
  const crossArtifact = await call('GET', `/v1/children/${CA}/messages/${randomUUID()}/media`, T.GA1);
  check('A IDOR', 'an unknown / other-family artifact id is 404 artifact_not_found', `${crossArtifact.status}/${crossArtifact.body.error}`, '404/artifact_not_found');
  const crossSession = await call('POST', `/v1/children/${CA}/calls/${randomUUID()}/end`, T.GA1, {});
  check('A IDOR', "ending someone else's call session ends nothing (ended:false)", `${crossSession.status}/${crossSession.body.ended}`, '200/false');

  // Tripwire: every :xId path parameter registered in routes.mjs has been audited here.
  const src = readFileSync(path.join(HERE, '..', 'routes.mjs'), 'utf8');
  const found = [...new Set([...src.matchAll(/path:\s*[`'"]([^`'"]+)[`'"]/g)]
    .flatMap((m) => [...m[1].matchAll(/:(\w+Id)\b/g)].map((x) => x[1])))].filter((p) => p !== 'childId').sort();
  const AUDITED = {
    inviteId: 'guardian_invite: RLS invited_by = actor on revoke; id is an unguessable bearer for get/accept/bootstrap (by design, 0014)',
    codeId: 'device_pairing_code: RLS owner (created_by = actor); not_found covers not-yours (0032)',
    deviceId: "revokePairedDevice: WHERE id AND target child is the path child's family (0032)",
    sessionId: 'call_log: WHERE id AND child_id (recordCallEnd / callSessionFor)',
    messageId: 'delivery_intent: WHERE id AND child_id',
    expenseId: 'resolveExpense: WHERE id AND child_id',
    medicationId: 'recordDose: medication must belong to child (S-B5) + composite FK (0039)',
    itemId: 'setBagItemStatus: WHERE id AND child_id',
    letterId: 'letter: WHERE id AND child_id (+ child-owned RLS)',
    artifactId: 'mediaArtifactFor: WHERE id AND child_id',
    passkeyId: 'deletePasskey: WHERE id AND user_id = caller',
  };
  check('A IDOR', 'every :xId path parameter in routes.mjs is in this suite\'s audited table (add new ones here AFTER auditing)',
    found.filter((p) => !(p in AUDITED)).join(',') || 'none', 'none');
  check('A IDOR', 'and the audited table has no stale entries',
    Object.keys(AUDITED).filter((p) => !found.includes(p)).join(',') || 'none', 'none');
}

// ===========================================================================
// B · S-B3 — passkeys
// ===========================================================================
const cborUint = (n) => (n < 24 ? Buffer.from([n]) : Buffer.from([24, n]));
const cborNegint = (n) => { const a = n - 1; return a < 24 ? Buffer.from([0x20 | a]) : Buffer.from([0x38, a]); };
const cborBytes = (buf) => (buf.length < 24
  ? Buffer.concat([Buffer.from([0x40 | buf.length]), buf]) : Buffer.concat([Buffer.from([0x58, buf.length]), buf]));
const cborText = (s) => { const b = Buffer.from(s, 'utf8');
  return b.length < 24 ? Buffer.concat([Buffer.from([0x60 | b.length]), b]) : Buffer.concat([Buffer.from([0x78, b.length]), b]); };
const cborMap = (n) => Buffer.from([0xa0 | n]);
const rpIdHash = createHash('sha256').update(RP_ID, 'utf8').digest();
function attestation(rawId, flags = 0x45) {
  const { publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const jwk = publicKey.export({ format: 'jwk' });
  const cose = Buffer.concat([cborMap(5), cborUint(1), cborUint(2), cborUint(3), cborNegint(7), cborNegint(1), cborUint(1),
    cborNegint(2), cborBytes(Buffer.from(jwk.x, 'base64url')), cborNegint(3), cborBytes(Buffer.from(jwk.y, 'base64url'))]);
  const idBuf = Buffer.from(rawId, 'utf8');
  const idLen = Buffer.alloc(2); idLen.writeUInt16BE(idBuf.length);
  const authData = Buffer.concat([rpIdHash, Buffer.from([flags]), Buffer.alloc(4), Buffer.alloc(16), idLen, idBuf, cose]);
  return Buffer.concat([cborMap(3), cborText('fmt'), cborText('none'), cborText('attStmt'), cborMap(0),
    cborText('authData'), cborBytes(authData)]).toString('base64url');
}
const clientData = (challenge) => Buffer.from(JSON.stringify({ type: 'webauthn.create', challenge, origin: RP_ORIGIN })).toString('base64url');
async function register(t, rawId, extra = {}, flags = 0x45) {
  const chal = await call('POST', '/v1/auth/webauthn/register/challenge', t);
  return call('POST', '/v1/auth/webauthn/register/verify', t,
    { clientDataJSON: clientData(chal.body.challenge), attestationObject: attestation(rawId, flags), ...extra });
}
const passkeyCount = async (u) => (await admin.query(`SELECT count(*)::int AS n FROM webauthn_credential WHERE user_id = $1`, [u])).rows[0].n;

{
  const noPin = await register(T.GA1, 'ga1-key-1');
  check('B passkeys', 'an account that has a PIN cannot add a passkey without it (400 pin_required)', `${noPin.status}/${noPin.body.error}`, '400/pin_required');
  const wrong = await register(T.GA1, 'ga1-key-1', { pin: '000000' });
  check('B passkeys', 'a wrong PIN is refused (403 pin_incorrect)', `${wrong.status}/${wrong.body.error}`, '403/pin_incorrect');
  check('B passkeys', 'and nothing was stored by either refusal', await passkeyCount(GA1), 0);
  const noUv = await register(T.GA1, 'ga1-key-1', { pin: PIN }, 0x41);
  check('B passkeys', 'a credential made WITHOUT user verification (UV flag clear) is refused (400)', `${noUv.status}/${noUv.body.error}`, '400/user_verification_required');
  check('B passkeys', 'and nothing was stored', await passkeyCount(GA1), 0);
  const ok = await register(T.GA1, 'ga1-key-1', { pin: PIN });
  check('B passkeys', 'with the PIN and user verification the passkey is registered (200)', ok.status, 200);
  check('B passkeys', 'and stored', await passkeyCount(GA1), 1);

  // bootstrap: a brand-new account (no PIN, no passkey) may register its FIRST passkey with no PIN
  const first = await register(T.NEWU, 'newu-key-1');
  check('B passkeys', 'bootstrap: the very first credential of a PIN-less, passkey-less account needs no PIN (200)', first.status, 200);
  const second = await register(T.NEWU, 'newu-key-2');
  check('B passkeys', 'but a SECOND one cannot be added by a bare session: the step-up now applies (400 pin_required)', `${second.status}/${second.body.error}`, '400/pin_required');
  const secondWrong = await register(T.NEWU, 'newu-key-2', { pin: '123456' });
  check('B passkeys', '...and with a guessed PIN it is refused too (403 pin_not_set: the account never set one)', `${secondWrong.status}/${secondWrong.body.error}`, '403/pin_not_set');
  check('B passkeys', '...so the account still holds exactly one passkey', await passkeyCount(NEWU), 1);

  const kidTry = await call('POST', '/v1/auth/webauthn/register/verify', T.KID, { clientDataJSON: 'x', attestationObject: 'y' });
  check('B passkeys', 'a child session cannot register a passkey (403)', kidTry.status, 403);

  // cap
  for (let i = 0; i < 9; i++) {
    await admin.query(`INSERT INTO webauthn_credential (user_id, credential_id, public_key_pem) VALUES ($1, $2, 'pem')`, [GA2, `ga2-bulk-${i}`]);
  }
  const ninth = await register(T.GA2, 'ga2-key-10', { pin: PIN });
  check('B passkeys', 'the 10th passkey is allowed', ninth.status, 200);
  const eleventh = await register(T.GA2, 'ga2-key-11', { pin: PIN });
  check('B passkeys', 'the 11th is refused (409 passkey_limit)', `${eleventh.status}/${eleventh.body.error}`, '409/passkey_limit');
  check('B passkeys', 'and not stored', await passkeyCount(GA2), 10);

  // list
  const list = await call('GET', '/v1/me/passkeys', T.GA1);
  check('B passkeys', 'GET /v1/me/passkeys lists the caller\'s passkey', `${list.status}/${list.body.passkeys.length}`, '200/1');
  check('B passkeys', 'and never exposes the credential id or public key',
    Object.keys(list.body.passkeys[0]).sort().join(), 'createdAt,id,signCount');
  check('B passkeys', "another user's list does not include it", (await call('GET', '/v1/me/passkeys', T.STR)).body.passkeys.length, 0);
  check('B passkeys', 'a child session cannot list passkeys (403)', (await call('GET', '/v1/me/passkeys', T.KID)).status, 403);
  check('B passkeys', 'an unauthenticated list is 401', (await call('GET', '/v1/me/passkeys', null)).status, 401);

  // delete
  const gaId = list.body.passkeys[0].id;
  const del1 = await call('DELETE', `/v1/me/passkeys/${gaId}`, T.GA1);
  check('B passkeys', 'DELETE without the PIN header is 400 pin_required', `${del1.status}/${del1.body.error}`, '400/pin_required');
  const del2 = await call('DELETE', `/v1/me/passkeys/${gaId}`, T.GA1, undefined, { 'x-guardian-pin': '111111' });
  check('B passkeys', 'DELETE with a wrong PIN is 403 pin_incorrect', `${del2.status}/${del2.body.error}`, '403/pin_incorrect');
  const del3 = await call('DELETE', `/v1/me/passkeys/${gaId}`, T.GA2, undefined, withPin);
  check('B passkeys', "ANOTHER user cannot delete GA1's passkey even with her own PIN (404)", `${del3.status}/${del3.body.error}`, '404/passkey_not_found');
  const del4 = await call('DELETE', `/v1/me/passkeys/${gaId}`, T.GA1, undefined, withPin);
  check('B passkeys', 'the LAST passkey cannot be removed (409 last_passkey: no self-lockout)', `${del4.status}/${del4.body.error}`, '409/last_passkey');
  check('B passkeys', 'and it is still there', await passkeyCount(GA1), 1);
  const del5 = await call('DELETE', `/v1/me/passkeys/${randomUUID()}`, T.GA1, undefined, withPin);
  check('B passkeys', 'an unknown id is 404', del5.status, 404);
  const del6 = await call('DELETE', '/v1/me/passkeys/not-a-uuid', T.GA1, undefined, withPin);
  check('B passkeys', 'a malformed id is 400 bad_path (strict ids)', `${del6.status}/${del6.body.error}`, '400/bad_path');
  const ga2List = await call('GET', '/v1/me/passkeys', T.GA2);
  const del7 = await call('DELETE', `/v1/me/passkeys/${ga2List.body.passkeys[0].id}`, T.GA2, undefined, withPin);
  check('B passkeys', 'with several passkeys, one can be removed with the PIN (200)', del7.status, 200);
  check('B passkeys', 'and it is gone', await passkeyCount(GA2), 9);
  check('B passkeys', 'a child session cannot delete (403)', (await call('DELETE', `/v1/me/passkeys/${gaId}`, T.KID, undefined, withPin)).status, 403);
}

// ===========================================================================
// C · S-B3 — the security-event feed + PIN-gated export
// ===========================================================================
{
  const feed = await call('GET', `/v1/children/${CA}/security-events`, T.GA2);
  check('C events', 'the CO-GUARDIAN reads the feed (200)', feed.status, 200);
  const kinds = feed.body.events.map((e) => e.kind);
  check('C events', "it shows GA1's passkey_added and GA2's own events", kinds.includes('passkey_added') && kinds.includes('passkey_removed'), true);
  const added = feed.body.events.find((e) => e.kind === 'passkey_added' && e.actor.userId === GA1);
  check('C events', 'each event names the ACTOR (so the other parent knows who)', added?.actor.name, 'Ann');
  check('C events', 'with the fixed, content-free summary', added?.summary, 'A passkey was added to a guardian account');
  check('C events', 'newest first', feed.body.events.every((e, i, a) => i === 0 || a[i - 1].seq > e.seq), true);
  const page = await call('GET', `/v1/children/${CA}/security-events?limit=1`, T.GA1);
  check('C events', '?limit=1 returns one event', page.body.events.length, 1);
  const next = await call('GET', `/v1/children/${CA}/security-events?limit=100&before=${page.body.nextBefore}`, T.GA1);
  check('C events', '?before=<seq> pages strictly older events', next.body.events.every((e) => e.seq < page.body.nextBefore), true);
  check('C events', 'a garbage ?before is 400', (await call('GET', `/v1/children/${CA}/security-events?before=abc`, T.GA1)).status, 400);
  check('C events', "family B's guardian is refused (403: no edge to this child)", (await call('GET', `/v1/children/${CA}/security-events`, T.GB)).status, 403);
  check('C events', 'a guardian with no edge anywhere is refused (403)', (await call('GET', `/v1/children/${CA}/security-events`, T.STR)).status, 403);
  check('C events', 'the child is refused (403)', (await call('GET', `/v1/children/${CA}/security-events`, T.KID)).status, 403);
  check('C events', 'unauthenticated is 401', (await call('GET', `/v1/children/${CA}/security-events`, null)).status, 401);
  check('C events', "family B's feed never contains family A's events",
    (await call('GET', `/v1/children/${CB}/security-events`, T.GB)).body.events.some((e) => e.actor.userId === GA1), false);

  // PIN change -> event
  const before = (await call('GET', `/v1/children/${CA}/security-events`, T.GA2)).body.events.length;
  const changed = await call('POST', '/v1/me/pin', T.GA1, { pin: '246813', currentPin: PIN });
  check('C events', 'changing the PIN works', changed.status, 200);
  const afterEv = (await call('GET', `/v1/children/${CA}/security-events`, T.GA2)).body.events;
  check('C events', "and the co-guardian sees a pin_changed event for it", afterEv.length - before === 1 && afterEv[0].kind === 'pin_changed', true);
  await call('POST', '/v1/me/pin', T.GA1, { pin: PIN, currentPin: '246813' });

  // export step-up
  const noPin = await call('GET', `/v1/children/${CA}/export`, T.GA1);
  check('C export', 'raw export without the PIN header is 400 pin_required', `${noPin.status}/${noPin.body.error}`, '400/pin_required');
  const noPinC = await call('GET', `/v1/children/${CA}/export?kind=certified`, T.GA1);
  check('C export', 'certified export without the PIN header is 400 pin_required', `${noPinC.status}/${noPinC.body.error}`, '400/pin_required');
  const wrong = await call('GET', `/v1/children/${CA}/export`, T.GA1, undefined, { 'x-guardian-pin': '999999' });
  check('C export', 'a wrong PIN is 403 pin_incorrect', `${wrong.status}/${wrong.body.error}`, '403/pin_incorrect');
  check('C export', 'no export_record or event was created by the refusals',
    (await admin.query(`SELECT count(*)::int AS n FROM export_record WHERE child_id = $1`, [CA])).rows[0].n, 0);
  const evBefore = (await call('GET', `/v1/children/${CA}/security-events`, T.GA2)).body.events.filter((e) => e.kind === 'export_taken').length;
  const okRaw = await call('GET', `/v1/children/${CA}/export`, T.GA1, undefined, withPin);
  check('C export', 'with the PIN a raw export works (200)', okRaw.status, 200);
  const evAfter = (await call('GET', `/v1/children/${CA}/security-events`, T.GA2)).body.events.filter((e) => e.kind === 'export_taken');
  check('C export', 'and the co-guardian is shown an export_taken event', evAfter.length - evBefore, 1);
  check('C export', 'whose summary says raw, and nothing about the content', evAfter[0].summary, 'A raw export of the family records was taken');
  const strangerExport = await call('GET', `/v1/children/${CA}/export`, T.STR, undefined, withPin);
  check('C export', 'a guardian with no edge is still refused even holding a PIN header (403)', strangerExport.status, 403);
}

// ===========================================================================
// D · S-B1 — redeem miss budget
// ===========================================================================
{
  const mk = await call('POST', `/v1/children/${CA}/device-pairing-codes`, T.GA1, { pin: PIN });
  check('D pairing', 'a guardian mints a pairing code (201)', mk.status, 201);
  const noPin = await call('POST', `/v1/children/${CA}/device-pairing-codes`, T.GA1, {});
  check('D pairing', '...and cannot without the PIN (400 pin_required)', `${noPin.status}/${noPin.body.error}`, '400/pin_required');
  const real = mk.body.numericCode;
  const wrongGuess = (i) => String((Number(real) + 1 + i) % 1_000_000).padStart(6, '0');
  const statuses = [];
  for (let i = 0; i < 3; i++) {
    statuses.push((await call('POST', '/v1/device-pairing/redeem', null, { code: wrongGuess(i), role: 'child' })).status);
  }
  check('D pairing', 'wrong guesses 1-3 are ordinary 404s', statuses.join(','), '404,404,404');
  const blocked = await call('POST', '/v1/device-pairing/redeem', null, { code: wrongGuess(4), role: 'child' });
  check('D pairing', 'once the global miss budget is spent the 4th guess is 429', `${blocked.status}/${blocked.body.error}`, '429/pairing_rate_limited');
  check('D pairing', 'with a retry hint', blocked.body.retryAfterSec >= 1, true);
  const realWhileBlocked = await call('POST', '/v1/device-pairing/redeem', null, { code: real, role: 'child' });
  check('D pairing', 'even the REAL code is refused while the budget is spent (the attacker cannot tell a hit from a miss)',
    `${realWhileBlocked.status}/${realWhileBlocked.body.error}`, '429/pairing_rate_limited');
  check('D pairing', 'and the code was not redeemed',
    (await admin.query(`SELECT count(*)::int AS n FROM device_pairing_code WHERE numeric_code = $1 AND redeemed_at IS NOT NULL`, [real])).rows[0].n, 0);
  clock += 61_000;
  const okRedeem = await call('POST', '/v1/device-pairing/redeem', null, { code: real, role: 'child' });
  check('D pairing', 'when the window rolls over the real code redeems (201)', okRedeem.status, 201);
  const ev = (await call('GET', `/v1/children/${CA}/security-events`, T.GA2)).body.events.find((e) => e.kind === 'device_paired');
  check('D pairing', 'and the co-guardian sees a device_paired event naming the guardian who minted the code',
    `${ev?.actor.name}/${ev?.summary}`, 'Ann/A child device was paired');
  const replay = await call('POST', '/v1/device-pairing/redeem', null, { code: real, role: 'child' });
  check('D pairing', 'a redeemed code cannot be used twice (409)', replay.status, 409);
}

// ===========================================================================
// E · S-B6 / S-B8 — uploads
// ===========================================================================
const MP4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(12), Buffer.alloc(976, 9)]); // 1000 B
const upload = (t, bytes, child = CA) => call('POST', `/v1/children/${child}/media`, t, { bytes: bytes.toString('base64') });
const blobCount = async () => (await storage.list('children/')).length;
const ledgerCount = async (child = CA) => (await admin.query(`SELECT count(*)::int AS n FROM media_upload WHERE child_id = $1`, [child])).rows[0].n;
let ga1Key, ga2Key, kidKey;
{
  const text = await upload(T.GA1, Buffer.from('<script>alert(1)</script>'));
  check('E uploads', 'HTML/text bytes are refused by magic-byte sniffing (415)', `${text.status}/${text.body.error}`, '415/unsupported_media_type');
  const exe = await upload(T.GA1, Buffer.from('MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00'));
  check('E uploads', 'an executable is refused (415)', exe.status, 415);
  check('E uploads', 'nothing was written to disk or the ledger by the refusals', `${await blobCount()}/${await ledgerCount()}`, '0/0');

  const png = (w, h) => {
    const b = Buffer.alloc(40);
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(b, 0);
    b.writeUInt32BE(13, 8); b.write('IHDR', 12, 'latin1'); b.writeUInt32BE(w, 16); b.writeUInt32BE(h, 20);
    return b;
  };
  const huge = await upload(T.GA1, png(8000, 8000));
  check('E uploads', 'an 8000x8000 PNG (64 Mpx, 249 KB in the audit) is refused before any decode (413 image_too_large)', `${huge.status}/${huge.body.error}`, '413/image_too_large');
  check('E uploads', '...and left no blob or ledger row', `${await blobCount()}/${await ledgerCount()}`, '0/0');

  const held = uploadLimiter.acquire(`u:${GA1}`);
  const busy = await upload(T.GA1, MP4);
  check('E uploads', 'a principal already at the in-flight cap gets 429 immediately (not queued)', `${busy.status}/${busy.body.error}`, '429/too_many_uploads_in_flight');
  const otherOk = await upload(T.GA2, MP4);
  ga2Key = otherOk.body.storageKey;
  check('E uploads', "another principal is unaffected by GA1's cap (201)", otherOk.status, 201);
  held();
  const ok = await upload(T.GA1, MP4);
  ga1Key = ok.body.storageKey;
  check('E uploads', 'after releasing the slot the upload is accepted (201)', ok.status, 201);
  check('E uploads', 'the response reports the MIME the bytes PROVE', ok.body.mime, 'video/mp4');
  const led = (await admin.query(`SELECT mime, byte_size, uploader_user_id, uploader_role FROM media_upload WHERE storage_key = $1`, [ga1Key])).rows[0];
  check('E uploads', 'the ledger records mime, size and uploader', `${led.mime}/${led.byte_size}/${led.uploader_user_id}/${led.uploader_role}`, `video/mp4/1000/${GA1}/guardian`);
  check('E uploads', 'the slot is released after a request that threw/returned (cap is back to 0)', uploadLimiter.count(`u:${GA1}`), 0);

  const kid = await upload(T.KID, MP4);
  kidKey = kid.body.storageKey;
  check('E uploads', "the child can upload to her own child (201)", kid.status, 201);
  check('E uploads', "...but not to another child (403 wrong_child)", (await upload(T.KID, MP4, CB)).status, 403);

  // quota: 3000 bytes; 3 x 1000 already in ledger (ga2, ga1, kid) -> the 4th is over
  const over = await upload(T.GA1, MP4);
  check('E uploads', 'a 4th 1000-byte upload past the 3000-byte per-child quota is 413 media_quota_exceeded', `${over.status}/${over.body.error}`, '413/media_quota_exceeded');
  check('E uploads', '...and left no blob or ledger row behind', `${await blobCount()}/${await ledgerCount()}`, '3/3');
  check('E uploads', "family B's quota is its own (GB can still upload)", (await upload(T.GB, MP4, CB)).status, 201);
}

// ===========================================================================
// F · S-B9 — message storageKey validation
// ===========================================================================
{
  const msg = (t, key, child = CA) => call('POST', `/v1/children/${child}/messages`, t, { storageKey: key, durationMs: 4200 });
  const err = async (t, key, child) => { const r = await msg(t, key, child); return `${r.status}/${r.body.error}`; };
  check('F storageKey', "another child's key under this child's path is 400 bad_storage_key", await err(T.GA1, `children/${CB}/messages/${randomUUID()}`), '400/bad_storage_key');
  check('F storageKey', 'a device-local key is 400 bad_storage_key', await err(T.GA1, `device/${randomUUID()}`), '400/bad_storage_key');
  check('F storageKey', 'a traversal key is 400 bad_storage_key', await err(T.GA1, `children/${CA}/messages/../../${CB}/messages/${randomUUID()}`), '400/bad_storage_key');
  check('F storageKey', 'a non-uuid tail is 400 bad_storage_key', await err(T.GA1, `children/${CA}/messages/anything`), '400/bad_storage_key');
  check('F storageKey', 'a well-formed key the server never issued is 400 storage_key_unknown', await err(T.GA1, `children/${CA}/messages/${randomUUID()}`), '400/storage_key_unknown');
  check('F storageKey', "a key uploaded by the CO-GUARDIAN cannot be used by GA1 (403 storage_key_not_yours)", await err(T.GA1, ga2Key), '403/storage_key_not_yours');
  check('F storageKey', "a key uploaded by the CHILD cannot be used by a guardian (403)", await err(T.GA1, kidKey), '403/storage_key_not_yours');
  check('F storageKey', "...and a guardian's key cannot be used by the child (403)", await err(T.KID, ga1Key), '403/storage_key_not_yours');
  check('F storageKey', 'no media_artifact row was created by any refusal',
    (await admin.query(`SELECT count(*)::int AS n FROM media_artifact WHERE child_id = $1`, [CA])).rows[0].n, 0);

  // ledger row whose blob is gone
  await storage.delete(ga2Key);
  check('F storageKey', "a ledger key whose blob no longer exists is 400 storage_key_unknown", await err(T.GA2, ga2Key), '400/storage_key_unknown');

  const good = await msg(T.GA1, ga1Key);
  check('F storageKey', 'positive control: the uploader posting her own key succeeds (201)', good.status, 201);
  check('F storageKey', 'the artifact points at exactly that key',
    (await admin.query(`SELECT storage_key FROM media_artifact WHERE id = $1`, [good.body.artifactId])).rows[0]?.storage_key, ga1Key);
  const reuse = await err(T.GA1, ga1Key);
  check('F storageKey', 'the same blob cannot back a second message (409 storage_key_in_use)', reuse, '409/storage_key_in_use');
  const kidGood = await msg(T.KID, kidKey);
  check('F storageKey', 'the child posting her own uploaded key succeeds (201)', kidGood.status, 201);
}

// ===========================================================================
// G · S-B8 — orphan sweeper + served MIME
// ===========================================================================
{
  const old1 = (await upload(T.GB, MP4, CB)).body;   // family B has one already (quota test); second still under 3000
  const youngKey = old1.storageKey;
  const strayKey = `children/${CA}/messages/${randomUUID()}`;
  await storage.put(strayKey, MP4);                                   // legacy blob: no ledger row at all
  const alienKey = `children/${randomUUID()}/messages/${randomUUID()}`;
  await storage.put(alienKey, MP4);                                   // child does not exist: must not be adopted
  const orphanOld = (await admin.query(`SELECT storage_key FROM media_upload WHERE child_id = $1 ORDER BY created_at LIMIT 1`, [CB])).rows[0].storage_key;
  await admin.query(`UPDATE media_upload SET created_at = now() - interval '25 hours' WHERE storage_key = $1`, [orphanOld]);
  const refKey = ga1Key;
  await admin.query(`UPDATE media_upload SET created_at = now() - interval '25 hours' WHERE storage_key = $1`, [refKey]);

  const r1 = await runOrphanMediaSweep(pool, storage, {});
  check('G sweeper', 'an unreferenced blob older than 24 h is deleted (blob AND ledger row)',
    `${await storage.exists(orphanOld)}/${(await admin.query(`SELECT 1 FROM media_upload WHERE storage_key = $1`, [orphanOld])).rowCount}`, 'false/0');
  check('G sweeper', 'a blob that backs a message is KEPT even when old', await storage.exists(refKey), true);
  check('G sweeper', 'a young unreferenced blob is kept (still waiting for its message)', await storage.exists(youngKey), true);
  check('G sweeper', 'a legacy blob with no ledger row is ADOPTED (not deleted on first sight)',
    `${await storage.exists(strayKey)}/${(await admin.query(`SELECT 1 FROM media_upload WHERE storage_key = $1`, [strayKey])).rowCount}`, 'true/1');
  check('G sweeper', 'a blob under a child that does not exist is not adopted',
    (await admin.query(`SELECT 1 FROM media_upload WHERE storage_key = $1`, [alienKey])).rowCount, 0);
  check('G sweeper', 'the sweep reports what it did', `${r1.blobsDeleted}/${r1.adopted >= 1}`, '1/true');
  await admin.query(`UPDATE media_upload SET created_at = now() - interval '25 hours' WHERE storage_key = $1`, [strayKey]);
  const r2 = await runOrphanMediaSweep(pool, storage, {});
  check('G sweeper', 'the adopted legacy blob is swept once it is 24 h old and still unreferenced',
    `${await storage.exists(strayKey)}/${r2.blobsDeleted >= 1}`, 'false/true');

  // served MIME
  const fakeRes = () => { const r = { code: null, headers: null }; r.writeHead = (c, h) => { r.code = c; r.headers = h; }; r.end = () => {}; return r; };
  const url = storage.signedUrl(refKey, 300, Date.now());
  const res = fakeRes();
  await serveSignedMedia(url, res, storage, async (k) => (await admin.query(`SELECT mime FROM media_upload WHERE storage_key = $1`, [k])).rows[0]?.mime ?? null);
  check('G served mime', 'a signed URL serves the MIME the bytes proved (video/mp4), not octet-stream', `${res.code}/${res.headers['content-type']}`, '200/video/mp4');
  check('G served mime', 'with nosniff', res.headers['x-content-type-options'], 'nosniff');
  const res2 = fakeRes();
  await serveSignedMedia(url, res2, storage, async () => 'text/html');
  check('G served mime', 'a MIME outside the servable set (text/html) is never emitted (falls back to octet-stream)', res2.headers['content-type'], 'application/octet-stream');
  const res3 = fakeRes();
  await serveSignedMedia(url, res3, storage, async () => { throw new Error('db down'); });
  check('G served mime', 'a failing MIME lookup degrades to octet-stream, not a 500', `${res3.code}/${res3.headers['content-type']}`, '200/application/octet-stream');
  const res4 = fakeRes();
  await serveSignedMedia(url, res4, storage);
  check('G served mime', 'with no lookup wired, the old behaviour (octet-stream) is unchanged', res4.headers['content-type'], 'application/octet-stream');
}

// ===========================================================================
// H · S-B14 + homework capture size
// ===========================================================================
{
  const bad = await call('GET', '/v1/children/not-a-uuid/medications', T.GA1);
  check('H strict ids', 'a malformed :childId is 400 bad_path on the real Api (it used to be a Postgres cast 500)', `${bad.status}/${bad.body.error}`, '400/bad_path');
  const badInv = await call('GET', '/v1/guardian-invites/12345', null);
  check('H strict ids', 'a malformed invite id is 400 bad_path (unauthenticated route)', badInv.status, 400);
  const badCode = await call('POST', '/v1/device-pairing-codes/xyz/cancel', T.GA1, {});
  check('H strict ids', 'a malformed pairing-code id is 400 bad_path', badCode.status, 400);
  const real = await call('GET', `/v1/guardian-invites/${randomUUID()}`, null);
  check('H strict ids', 'a well-formed but unknown invite id is an ordinary 404', real.status, 404);

  const png = Buffer.alloc(40);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png, 0);
  png.writeUInt32BE(13, 8); png.write('IHDR', 12, 'latin1'); png.writeUInt32BE(8000, 16); png.writeUInt32BE(8000, 20);
  const cap = await call('POST', `/v1/children/${CA}/homework/capture`, T.GA1, { image: png.toString('base64') });
  check('H capture', 'homework capture refuses an 8000x8000 PNG before decoding (413 image_too_large)', `${cap.status}/${cap.body.error}`, '413/image_too_large');
  const held = uploadLimiter.acquire(`u:${GA1}`);
  const small = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const capBusy = await call('POST', `/v1/children/${CA}/homework/capture`, T.GA1, { image: small.toString('base64') });
  check('H capture', 'and shares the in-flight cap with media uploads (429)', `${capBusy.status}/${capBusy.body.error}`, '429/too_many_uploads_in_flight');
  held();
}

await cleanup();
await fs.rm(storageRoot, { recursive: true, force: true });
await admin.end(); await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
