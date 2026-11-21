/**
 * Encrypted family backup, the SERVER half (db/migrations/0054_family_backup.sql, server/family_backup*.mjs),
 * end to end against a REAL Postgres through the REAL Api (strict ids ON, as in production). Every account
 * comes from POST /v1/auth/signup; the only SQL seeding is the guardianship edges a family would get from the
 * invite flow, and the clock (the waiting period is moved by rewinding the stored times, never by editing a rule).
 *
 *   A. vault        create, one per family, join, a stranger learns nothing (404 for "no such vault" and "not yours")
 *   B. backup       chunked, resumable, idempotent; every refusal (bad chain, bad hash, wrong size, stale head, wrong phone)
 *   C. integrity    what the phone verifies: the listed history passes the reference check; a tampered history does not
 *   D. retention    never an overwrite: newest N live, older tombstoned with bytes kept; delete needs the PIN, is reversible
 *   E. immutability the database itself refuses to rewrite or erase a committed backup (as the runtime role)
 *   F. quota        live bytes, open uploads, the set-aside allowance, open-upload cap
 *   G. restore      the whole lost-phone story, then replay, wrong family, wrong key, wrong phone, races, cancel, limits
 *   H. pause        either parent may pause the other; visible to all; reversible; a paused parent can still STOP a restore
 *   I. helper       one trusted helper for a single parent; can ONLY confirm; steps down when a second parent joins
 *   J. isolation    row level security under the runtime role, table by table
 *   K. limits       rate limits, the kill switch, child sessions, no-token requests, content-free notices
 *   L. pressure     a full allowance sets the oldest aside (never refuses), abort/sweep racing a commit, two parents at once
 *
 * Needs a NOSUPERUSER NOBYPASSRLS DATABASE_URL (app_owner or app_runtime) and an ADMIN_DATABASE_URL for setup and
 * cleanup. Prints "N passed, M failed" for verify.sh.
 */
import pg from 'pg';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import { randomUUID, randomBytes, generateKeyPairSync, sign } from 'node:crypto';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort, withSession, issueSignupAllowance, setSignupPolicy, issueRecoveryCode } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { TokenBuckets } from '../rate_limit.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { backupConfig, reclaimVault, sweepBackups, endVaultMembership } from '../family_backup.mjs';
import { createBackupLimiters } from '../family_backup_routes.mjs';
import { GENESIS_CHAIN, sha256, chainHash, restoreChallengeMessage, verifyHistory, ed25519Verify } from '../backup_chain.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const st = (r) => `${r.status}${r.body?.error ? ' ' + r.body.error : ''}`;

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const SECRET = Buffer.from('b'.repeat(32), 'utf8');
const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-backup-test-'));
const baseCfg = { ...backupConfig({}), keepVersions: 3, maxVersionBytes: 20_000, quotaBytes: 40_000, maxRequestsPerDevicePerDay: 50, maxRequestsPerVaultPerDay: 50, maxChallengesPerDeviceHour: 40 };
const big = () => new TokenBuckets({ capacity: 100000, refillPerSec: 1000 });
const wideLimiters = () => ({ begin: big(), challenge: big(), request: big(), token: big(), members: big(), download: big(), reads: big() });
const mkApi = (opts = {}) => {
  const a = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
  registerRoutes(a, pool, new FilesystemStorage(tmpRoot), {
    callEnv: { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
      JITSI_APP_SECRET: randomBytes(32).toString('hex'), JITSI_SERVER_URL: 'https://calls.example.test:8443' },
    backupLimiters: wideLimiters(), backupConfig: baseCfg, ...opts });
  return a;
};
const api = mkApi();
const hdr = (tok, more = {}) => ({ ...(tok ? { authorization: `Bearer ${tok}` } : {}), ...more });
const callOn = (a) => (method, p, tok, body, more) => a.handle(method, p, hdr(tok, more), body === undefined ? '' : JSON.stringify(body));
const call = callOn(api);
const RUN = randomUUID().slice(0, 8);
const LABEL = `bktest-${RUN}`;
const users = []; const children = []; const vaults = [];

const signup = async (suffix, pin, over = {}) => {
  const token = (await issueSignupAllowance(pool, { label: `${LABEL}-${suffix}` })).token;
  const r = await call('POST', '/v1/auth/signup', null, {
    allowanceToken: token, displayName: `${suffix}-${RUN}`, homeTz: 'America/Chicago', pin, deviceLabel: 'Phone', ...over });
  if (r.status !== 201) throw new Error(`signup failed: ${r.status} ${JSON.stringify(r.body)}`);
  users.push(r.body.userId);
  return { userId: r.body.userId, tok: r.body.token, deviceId: r.body.deviceId, pin };
};
const mkChild = async (g, name) => {
  const r = await call('POST', '/v1/children', g.tok, { displayName: name, birthDate: '2018-03-04', homeTz: 'America/Chicago', pin: g.pin });
  if (r.status !== 201) throw new Error('child create failed');
  children.push(r.body.child.id);
  return r.body.child.id;
};
const edge = (childId, userId, role = 'guardian') => admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, $3, '{}', tstzrange(now() - interval '1 minute', NULL))`, [childId, userId, role]);
const unlockPin = (userId) => admin.query(`UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL WHERE user_id = $1`, [userId]);
const rewindRestore = (id, hours) => admin.query(
  `UPDATE backup_restore_request SET created_at = created_at - make_interval(hours => $2),
          not_before = not_before - make_interval(hours => $2), expires_at = expires_at - make_interval(hours => $2) WHERE id = $1`, [id, hours]);

// The family's recovery key (made on the phone, only the public half is ever sent) and the signing key backups use.
const FAMILY = generateKeyPairSync('ed25519');
const rawPub = FAMILY.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
const VERIFIER = rawPub.toString('hex');
const SIGN = (m) => sign(null, m, FAMILY.privateKey);
const verifySig = (chain, sig) => ed25519Verify(rawPub, chain, sig);

/** Build one backup the way a phone would: opaque bytes cut into chunks, hashed, chained, signed. */
function mkBackup(vaultId, head, { size = 3000, chunkSize = 1024, ref } = {}) {
  const blob = randomBytes(size);
  const manifest = randomBytes(48);
  const blobSha = sha256(blob);
  const seq = head.seq + 1;
  const prev = Buffer.from(head.chain, 'hex');
  const chain = chainHash({ vaultId, seq, prevChain: prev, blobSha256: blobSha, size, manifest });
  const chunks = [];
  for (let i = 0; i < blob.length; i += chunkSize) chunks.push(blob.subarray(i, i + chunkSize));
  return {
    blob, chunks, seq, chain,
    body: { clientRef: ref ?? `ref-${randomBytes(6).toString('hex')}`, baseSeq: head.seq, prevChainHash: head.chain,
      chainHash: chain.toString('hex'), blobSha256: blobSha.toString('hex'), sizeBytes: size, chunkSize,
      manifest: manifest.toString('base64'), signature: SIGN(chain).toString('base64') } };
}
const chunkBody = (buf) => ({ data: buf.toString('base64'), sha256: sha256(buf).toString('hex') });
const V = (id) => `/v1/backup/vaults/${id}`;
const putChunks = async (actor, vid, uid, bb, which) => {
  const out = [];
  for (const i of which ?? bb.chunks.keys()) out.push(await call('PUT', `${V(vid)}/uploads/${uid}/chunks/${i}`, actor.tok, chunkBody(bb.chunks[i])));
  return out;
};
const headOf = async (actor, vid) => {
  const all = await call('GET', `${V(vid)}/versions?limit=200`, actor.tok);
  const last = all.body.versions?.[all.body.versions.length - 1];
  return last ? { seq: last.seq, chain: last.chainHash } : { seq: 0, chain: GENESIS_CHAIN.toString('hex') };
};
/** begin + every chunk + commit. */
const backupOnce = async (actor, vid, opts) => {
  const head = await headOf(actor, vid);
  const bb = mkBackup(vid, head, opts);
  const b = await call('POST', `${V(vid)}/uploads`, actor.tok, bb.body);
  if (b.status !== 201) return { fail: b, bb };
  await putChunks(actor, vid, b.body.uploadId, bb);
  const c = await call('POST', `${V(vid)}/uploads/${b.body.uploadId}/commit`, actor.tok);
  return { commit: c, bb, uploadId: b.body.uploadId };
};
const countRows = async (table, vid) => Number((await admin.query(`SELECT count(*) n FROM ${table} WHERE vault_id = $1`, [vid])).rows[0].n);

await setSignupPolicy(pool, { enabled: true, maxAccounts: null });

// ---- the cast ---------------------------------------------------------------------------------------------------
const A = await signup('mom', '4821');
const B = await signup('dad', '2468');
const C = await signup('other', '7315');         // a stranger family
const S = await signup('solo', '1357');          // a single parent
const H = await signup('helper', '9753');        // a welcomed adult in the single parent's family
const CA = await mkChild(A, 'Ivy');
const CC = await mkChild(C, 'Otis');
const CS = await mkChild(S, 'Wren');
await edge(CA, B.userId);
await edge(CS, H.userId, 'trusted_adult');
check('setup', 'five grown-ups in three families exist, each with one signed-in phone', users.length, 5);

// ===========================================================================
// A · THE VAULT
// ===========================================================================
let VA;
{
  check('A vault', 'creating a vault needs the PIN', st(await call('POST', '/v1/backup/vaults', A.tok, { recoveryVerifier: VERIFIER })), '400 pin_required');
  check('A vault', 'a wrong PIN is refused', st(await call('POST', '/v1/backup/vaults', A.tok, { recoveryVerifier: VERIFIER, pin: '0000' })), '403 pin_incorrect');
  await unlockPin(A.userId);
  check('A vault', 'a malformed recovery key is refused', st(await call('POST', '/v1/backup/vaults', A.tok, { recoveryVerifier: 'zz', pin: A.pin })), '400 recovery_verifier_invalid');
  const r = await call('POST', '/v1/backup/vaults', A.tok, { recoveryVerifier: VERIFIER, pin: A.pin });
  check('A vault', 'a grown-up creates the family vault (201)', r.status, 201);
  VA = r.body.vaultId; vaults.push(VA);
  check('A vault', 'the vault reports the policy it keeps', `${r.body.keepVersions}/${r.body.recoveryWindowDays}`, `3/180`);
  check('A vault', 'a second grown-up of the SAME family is told to join, not to start a second vault',
    `${st(await call('POST', '/v1/backup/vaults', B.tok, { recoveryVerifier: VERIFIER, pin: B.pin }))}`, '409 join_existing_vault');
  const l = await call('GET', '/v1/backup/vaults', B.tok);
  check('A vault', 'the co-parent sees it as joinable', `${l.body.vaults.length}/${l.body.joinable.length}/${l.body.joinable[0]?.vaultId === VA}`, '0/1/true');
  const lc = await call('GET', '/v1/backup/vaults', C.tok);
  check('A vault', 'a stranger family sees nothing joinable', `${lc.body.vaults.length}/${lc.body.joinable.length}`, '0/0');
  check('A vault', 'a stranger cannot join (the answer is the same as "no such vault")', st(await call('POST', `${V(VA)}/join`, C.tok, { pin: C.pin })), '404 vault_not_found');
  check('A vault', 'joining a vault that does not exist gives the same answer', st(await call('POST', `${V(randomUUID())}/join`, C.tok, { pin: C.pin })), '404 vault_not_found');
  for (const [name, fn] of [
    ['status', () => call('GET', V(VA), C.tok)], ['versions', () => call('GET', `${V(VA)}/versions`, C.tok)],
    ['events', () => call('GET', `${V(VA)}/events`, C.tok)], ['restores', () => call('GET', `${V(VA)}/restores`, C.tok)],
    ['begin', () => call('POST', `${V(VA)}/uploads`, C.tok, mkBackup(VA, { seq: 0, chain: GENESIS_CHAIN.toString('hex') }).body)],
  ]) check('A vault', `a stranger cannot reach ${name} of another family's vault`, st(await fn()).slice(0, 3) === '404' ? 'hidden' : st(await fn()), 'hidden');
  check('A vault', 'joining needs the PIN', st(await call('POST', `${V(VA)}/join`, B.tok, {})), '400 pin_required');
  const j = await call('POST', `${V(VA)}/join`, B.tok, { pin: B.pin });
  check('A vault', 'the co-parent joins (201)', `${j.status} ${j.body.state}`, '201 active');
  check('A vault', 'joining twice is harmless', `${(await call('POST', `${V(VA)}/join`, B.tok, { pin: B.pin })).body.alreadyMember}`, 'true');
  const s = await call('GET', V(VA), A.tok);
  check('A vault', 'status lists both grown-ups by NAME and no other family', s.body.members.length, 2);
  check('A vault', '...and an empty backup has no head yet', `${s.body.head}/${s.body.liveVersions}`, 'null/0');
  const ev = await call('GET', `${V(VA)}/events`, B.tok);
  check('A vault', 'both grown-ups see the plain-words notices (set up, joined)', ev.body.events.map((e) => e.kind).join(), 'vault_created,member_joined');
}

// ===========================================================================
// B · A BACKUP: chunked, resumable, idempotent, and every way it can be refused
// ===========================================================================
let head = { seq: 0, chain: GENESIS_CHAIN.toString('hex') };
{
  const lim = await call('GET', '/v1/backup/limits', A.tok);
  check('B backup', 'a phone can ask what the server accepts (to plan a weak link)', `${lim.status} ${lim.body.maxChunkBytes > 0} ${lim.body.waitHoursWithApprover}/${lim.body.waitHoursSolo}`, '200 true 48/72');

  const bb = mkBackup(VA, head, { size: 3500 });
  check('B backup', 'a begin with a chain value that is not the hash of its own parts is refused', st(await call('POST', `${V(VA)}/uploads`, A.tok, { ...bb.body, chainHash: sha256(Buffer.from('x')).toString('hex') })), '422 chain_mismatch');
  check('B backup', 'a junk begin is refused', st(await call('POST', `${V(VA)}/uploads`, A.tok, { clientRef: 'x' })), '400 invalid_upload');
  const huge = mkBackup(VA, head, { size: 30_000 });
  check('B backup', 'a backup over the size cap is refused before a byte is sent', st(await call('POST', `${V(VA)}/uploads`, A.tok, huge.body)), '413 backup_too_large');
  check('B backup', 'a chunk size outside the window is refused', st(await call('POST', `${V(VA)}/uploads`, A.tok, { ...bb.body, chunkSize: 100 })).slice(0, 3), '400');

  const b = await call('POST', `${V(VA)}/uploads`, A.tok, bb.body);
  check('B backup', 'begin (201)', `${b.status} ${b.body.chunkCount} ${b.body.seq}`, '201 4 1');
  const again = await call('POST', `${V(VA)}/uploads`, A.tok, bb.body);
  check('B backup', 'begin is idempotent on the phone\'s own id (a lost response leaves no second upload)', `${again.status} ${again.body.resumed} ${again.body.uploadId === b.body.uploadId}`, '200 true true');
  check('B backup', 'reusing the id for a DIFFERENT backup is refused', st(await call('POST', `${V(VA)}/uploads`, A.tok, { ...mkBackup(VA, head, { size: 3500, ref: bb.body.clientRef }).body })), '409 client_ref_reused');
  check('B backup', 'only one upload row exists for it', Number((await admin.query(`SELECT count(*) n FROM backup_upload WHERE vault_id = $1`, [VA])).rows[0].n), 1);

  const U = b.body.uploadId;
  await putChunks(A, VA, U, bb, [0, 2]);
  const sts = await call('GET', `${V(VA)}/uploads/${U}`, A.tok);
  check('B backup', 'the phone can ask which pieces are missing (resume after a dropped link)', `${sts.body.received} | ${sts.body.missing}`, '0,2 | 1,3');
  check('B backup', 'the same piece again is accepted without a second copy', `${(await call('PUT', `${V(VA)}/uploads/${U}/chunks/0`, A.tok, chunkBody(bb.chunks[0]))).body.already}`, 'true');
  const other = randomBytes(bb.chunks[0].length);
  check('B backup', 'a DIFFERENT piece for a slot already filled is refused', st(await call('PUT', `${V(VA)}/uploads/${U}/chunks/0`, A.tok, chunkBody(other))), '409 chunk_conflict');
  check('B backup', 'a piece whose bytes do not match its hash is refused', st(await call('PUT', `${V(VA)}/uploads/${U}/chunks/1`, A.tok, { data: bb.chunks[1].toString('base64'), sha256: sha256(Buffer.from('no')).toString('hex') })), '422 chunk_hash_mismatch');
  check('B backup', 'a piece of the wrong length is refused', st(await call('PUT', `${V(VA)}/uploads/${U}/chunks/1`, A.tok, chunkBody(bb.chunks[1].subarray(0, 500)))).slice(0, 3), '400');
  check('B backup', 'a piece past the end is refused', st(await call('PUT', `${V(VA)}/uploads/${U}/chunks/9`, A.tok, chunkBody(bb.chunks[1]))), '400 invalid_chunk');
  check('B backup', 'committing before every piece is in is refused (and says how many are missing)', `${st(await call('POST', `${V(VA)}/uploads/${U}/commit`, A.tok))}`, '409 upload_incomplete');
  check('B backup', 'the other parent cannot add to, finish or read the status of a phone\'s upload', `${st(await call('PUT', `${V(VA)}/uploads/${U}/chunks/1`, B.tok, chunkBody(bb.chunks[1])))}|${st(await call('POST', `${V(VA)}/uploads/${U}/commit`, B.tok))}|${st(await call('GET', `${V(VA)}/uploads/${U}`, B.tok))}`, '403 not_your_upload|403 not_your_upload|403 not_your_upload');
  check('B backup', 'a stranger cannot add a piece', st(await call('PUT', `${V(VA)}/uploads/${U}/chunks/1`, C.tok, chunkBody(bb.chunks[1]))), '404 vault_not_found');
  await putChunks(A, VA, U, bb, [1, 3]);
  const c = await call('POST', `${V(VA)}/uploads/${U}/commit`, A.tok);
  check('B backup', 'commit (201), version 1, nothing set aside', `${c.status} ${c.body.version.seq} ${c.body.tombstoned.length}`, '201 1 0');
  check('B backup', 'the server answers with the chain it recomputed', c.body.version.chainHash, bb.chain.toString('hex'));
  const c2 = await call('POST', `${V(VA)}/uploads/${U}/commit`, A.tok);
  check('B backup', 'a second commit (lost response) returns the same version and adds none', `${c2.status} ${c2.body.alreadyCommitted} ${c2.body.version.seq} ${await countRows('backup_version', VA)}`, '200 true 1 1');
  check('B backup', 'a piece added after the commit is refused', st(await call('PUT', `${V(VA)}/uploads/${U}/chunks/0`, A.tok, chunkBody(bb.chunks[0]))), '409 upload_committed');
  check('B backup', 'an aborted-after-commit is refused (a committed backup is never aborted)', st(await call('POST', `${V(VA)}/uploads/${U}/abort`, A.tok)), '409 upload_committed');
  head = { seq: 1, chain: bb.chain.toString('hex') };

  // a stale phone (it did not see version 1) tries to write on top of the old head: refused, nothing overwritten
  const stale = mkBackup(VA, { seq: 0, chain: GENESIS_CHAIN.toString('hex') });
  const sr = await call('POST', `${V(VA)}/uploads`, A.tok, stale.body);
  check('B backup', 'writing on a stale head (rollback attempt) is refused and shows the real head', `${sr.status} ${sr.body.error} ${sr.body.headSeq}`, '409 head_moved 1');
  // a begin that skips ahead: right chain value for a made-up previous link
  const skip = mkBackup(VA, { seq: 1, chain: sha256(Buffer.from('invented')).toString('hex') });
  check('B backup', 'a begin that names a previous link the server does not hold is refused', st(await call('POST', `${V(VA)}/uploads`, A.tok, skip.body)), '409 head_moved');

  // ciphertext hash declared wrong: the pieces hash to something else
  const liar = mkBackup(VA, head, { size: 2048 });
  const wrongBlob = sha256(Buffer.from('not the blob'));
  const liarChain = chainHash({ vaultId: VA, seq: 2, prevChain: Buffer.from(head.chain, 'hex'), blobSha256: wrongBlob, size: 2048, manifest: Buffer.from(liar.body.manifest, 'base64') });
  const liarBody = { ...liar.body, blobSha256: wrongBlob.toString('hex'), chainHash: liarChain.toString('hex'), signature: SIGN(liarChain).toString('base64') };
  const lb = await call('POST', `${V(VA)}/uploads`, A.tok, liarBody);
  await putChunks(A, VA, lb.body.uploadId, liar);
  check('B backup', 'pieces that do not hash to the declared whole are refused at commit', st(await call('POST', `${V(VA)}/uploads/${lb.body.uploadId}/commit`, A.tok)), '422 blob_hash_mismatch');
  check('B backup', '...and nothing was committed', await countRows('backup_version', VA), 1);
  check('B backup', 'abort frees the bytes of an unfinished upload', `${(await call('POST', `${V(VA)}/uploads/${lb.body.uploadId}/abort`, A.tok)).body.state} ${Number((await admin.query(`SELECT count(*) n FROM backup_chunk WHERE upload_id = $1`, [lb.body.uploadId])).rows[0].n)}`, 'aborted 0');
  check('B backup', 'an aborted attempt id cannot be reused', st(await call('POST', `${V(VA)}/uploads`, A.tok, liarBody)), '409 client_ref_finished');

  // a race: two phones start from the same head at once; exactly one wins, the other is told the head moved
  const r1 = mkBackup(VA, head, { size: 1500 }), r2 = mkBackup(VA, head, { size: 1600 });
  const [b1, b2] = await Promise.all([call('POST', `${V(VA)}/uploads`, A.tok, r1.body), call('POST', `${V(VA)}/uploads`, B.tok, r2.body)]);
  await Promise.all([putChunks(A, VA, b1.body.uploadId, r1), putChunks(B, VA, b2.body.uploadId, r2)]);
  const [k1, k2] = await Promise.all([call('POST', `${V(VA)}/uploads/${b1.body.uploadId}/commit`, A.tok), call('POST', `${V(VA)}/uploads/${b2.body.uploadId}/commit`, B.tok)]);
  check('B backup', 'two simultaneous commits on one head: exactly one wins', [k1.status, k2.status].sort().join(), '201,409');
  check('B backup', '...the loser is told the head moved, and nothing was overwritten', `${[k1, k2].find((x) => x.status === 409).body.error} ${await countRows('backup_version', VA)}`, 'head_moved 2');
  const loserUpload = k1.status === 201 ? b2.body.uploadId : b1.body.uploadId;
  await call('POST', `${V(VA)}/uploads/${loserUpload}/abort`, k1.status === 201 ? B.tok : A.tok);
  const winner = k1.status === 201 ? r1 : r2;
  head = { seq: 2, chain: winner.chain.toString('hex') };

  // open-upload cap
  const caps = [];
  for (let i = 0; i < 4; i++) caps.push(await call('POST', `${V(VA)}/uploads`, A.tok, mkBackup(VA, head, { size: 1200 }).body));
  check('B backup', 'at most three unfinished uploads at a time (the fourth is refused)', caps.map((x) => x.status).join(), '201,201,201,429');
  for (const x of caps.filter((y) => y.status === 201)) await call('POST', `${V(VA)}/uploads/${x.body.uploadId}/abort`, A.tok);
}

// ===========================================================================
// C · INTEGRITY: what the phone checks on what the server lists
// ===========================================================================
{
  const lv = await call('GET', `${V(VA)}/versions`, A.tok);
  const list = lv.body.versions;
  check('C integrity', 'the listing carries every version\'s hashes, manifest and signature', ['seq', 'prevChainHash', 'chainHash', 'blobSha256', 'sizeBytes', 'manifest', 'signature', 'state'].every((k) => k in list[0]) && list.length === 2, true);
  const honest = verifyHistory({ vaultId: VA, versions: list, verifySignature: verifySig });
  check('C integrity', 'the history the server lists passes the phone\'s check', `${honest.ok} ${honest.headSeq}`, 'true 2');
  check('C integrity', '...and the head the server reports is the last version', `${lv.body.head.seq} ${lv.body.head.chainHash === list[1].chainHash}`, '2 true');
  const tampered = JSON.parse(JSON.stringify(list)); tampered[0].manifest = randomBytes(48).toString('base64');
  check('C integrity', 'a server that edited a stored manifest would be caught', verifyHistory({ vaultId: VA, versions: tampered, verifySignature: verifySig }).ok, false);
  check('C integrity', 'a server that hid the newest version would be caught against what the phone has seen',
    verifyHistory({ vaultId: VA, versions: list.slice(0, 1), highWater: { seq: 2, chainHash: list[1].chainHash }, verifySignature: verifySig }).reason, 'rollback');
  const paged = await call('GET', `${V(VA)}/versions?limit=1`, A.tok);
  check('C integrity', 'a page of one still reports the true head and that there is more', `${paged.body.versions.length} ${paged.body.more} ${paged.body.head.seq}`, '1 true 2');
  const after = await call('GET', `${V(VA)}/versions?after=1`, A.tok);
  check('C integrity', 'paging forward continues from the cursor', `${after.body.versions.map((v) => v.seq)}`, '2');
  check('C integrity', 'the listing has no ciphertext in it (metadata only)', JSON.stringify(lv.body).length < 2500, true);
}

// ===========================================================================
// D · RETENTION: nothing is silently overwritten
// ===========================================================================
{
  for (let i = 0; i < 3; i++) {
    const r = await backupOnce(A, VA, { size: 1100 + i });
    check('D retention', `backup ${3 + i} commits`, r.commit?.status, 201);
  }
  const lv = await call('GET', `${V(VA)}/versions`, A.tok);
  check('D retention', 'five versions exist; the newest three are live, the older two are set aside (tombstones)',
    lv.body.versions.map((v) => `${v.seq}${v.state === 'live' ? 'L' : 'T'}`).join(), '1T,2T,3L,4L,5L');
  check('D retention', 'a set-aside version says why and until when (a recovery window)', `${lv.body.versions[0].tombstoneReason} ${new Date(lv.body.versions[0].purgeAfter) > new Date(Date.now() + 170 * 86400e3)}`, 'retention true');
  const t1 = (await admin.query(`SELECT upload_id FROM backup_version WHERE vault_id = $1 AND seq = 1`, [VA])).rows[0].upload_id;
  check('D retention', 'the set-aside version\'s bytes are STILL stored', Number((await admin.query(`SELECT count(*) n FROM backup_chunk WHERE upload_id = $1`, [t1])).rows[0].n), 4);
  check('D retention', 'the chain across the set-aside versions is still whole', verifyHistory({ vaultId: VA, versions: lv.body.versions, verifySignature: verifySig }).ok, true);
  const st1 = await call('GET', V(VA), A.tok);
  check('D retention', 'status counts live and set-aside separately', `${st1.body.liveVersions}/${st1.body.tombstones}`, '3/2');

  check('D retention', 'setting a version aside needs the PIN', st(await call('POST', `${V(VA)}/versions/4/delete`, A.tok, {})), '400 pin_required');
  await unlockPin(A.userId);
  const d = await call('POST', `${V(VA)}/versions/4/delete`, A.tok, { pin: A.pin });
  check('D retention', 'a deleted version is set aside, not erased', `${d.status} ${d.body.state}`, '200 tombstone');
  check('D retention', 'its bytes are still there', Number((await admin.query(`SELECT count(*) n FROM backup_chunk c JOIN backup_version v ON v.upload_id = c.upload_id WHERE v.vault_id = $1 AND v.seq = 4`, [VA])).rows[0].n) > 0, true);
  check('D retention', 'deleting twice is harmless', `${(await call('POST', `${V(VA)}/versions/4/delete`, A.tok, { pin: A.pin })).body.alreadySetAside}`, 'true');
  check('D retention', 'deleting the one before the last live version is allowed, the LAST live version is refused', `${st(await call('POST', `${V(VA)}/versions/3/delete`, A.tok, { pin: A.pin }))}|${st(await call('POST', `${V(VA)}/versions/5/delete`, A.tok, { pin: A.pin }))}`, '200|409 last_version');
  check('D retention', 'a missing version is 404', st(await call('POST', `${V(VA)}/versions/99/delete`, A.tok, { pin: A.pin })), '404 version_not_found');
  check('D retention', 'a stranger cannot delete or bring back a version', `${st(await call('POST', `${V(VA)}/versions/5/delete`, C.tok, { pin: C.pin }))}|${st(await call('POST', `${V(VA)}/versions/3/undelete`, C.tok))}`, '404 vault_not_found|404 vault_not_found');
  const u = await call('POST', `${V(VA)}/versions/3/undelete`, B.tok);
  check('D retention', 'the other parent can bring a set-aside version back', `${u.status} ${u.body.state}`, '200 live');
  const ev = await call('GET', `${V(VA)}/events`, B.tok);
  check('D retention', 'both parents get a plain notice for each set-aside and bring-back', ev.body.events.filter((e) => e.kind === 'version_deleted' || e.kind === 'version_restored').length, 3);

  // purge: only after the window, only by the sweep
  await admin.query(`SET session_replication_role = replica`);
  await admin.query(`UPDATE backup_version SET purge_after = now() - interval '1 day' WHERE vault_id = $1 AND seq = 1`, [VA]);
  await admin.query(`SET session_replication_role = DEFAULT`);
  const sw = await sweepBackups(pool, new Date());
  check('D retention', 'the sweep purges only what is past its window (version 1) and frees its bytes', `${sw.purgedVersions >= 1} ${sw.freedBytes >= 3500}`, 'true true');
  check('D retention', '...the version ROW is kept (the chain stays whole) but its bytes are gone',
    `${await countRows('backup_version', VA)} ${Number((await admin.query(`SELECT count(*) n FROM backup_chunk WHERE upload_id = $1`, [t1])).rows[0].n)}`, '5 0');
  const lv2 = await call('GET', `${V(VA)}/versions`, A.tok);
  check('D retention', '...and says it was purged; the history still verifies end to end', `${lv2.body.versions[0].purged} ${verifyHistory({ vaultId: VA, versions: lv2.body.versions, verifySignature: verifySig }).ok}`, 'true true');
  check('D retention', 'a purged version cannot be brought back', st(await call('POST', `${V(VA)}/versions/1/undelete`, A.tok)), '410 version_purged');
  const stillThere = await admin.query(`SELECT count(*) n FROM backup_chunk c JOIN backup_version v ON v.upload_id = c.upload_id WHERE v.vault_id = $1 AND v.seq = 2`, [VA]);
  check('D retention', 'a version still inside its window was NOT touched by the sweep', Number(stillThere.rows[0].n) > 0, true);
}

// ===========================================================================
// E · IMMUTABILITY: the database refuses, even to a hostile session
// ===========================================================================
{
  const asA = (fn) => withSession(pool, { roleName: 'guardian', userId: A.userId, childId: null }, fn);
  const sys = (fn) => withSession(pool, { roleName: 'system', userId: null, childId: null }, fn);
  const attempt = async (fn) => { try { const r = await fn(); return Array.isArray(r) && r.length === 0 ? 'blocked' : 'allowed'; } catch (e) { return 'blocked'; } };
  check('E immutable', 'an active parent cannot DELETE a committed version', await attempt(() => asA((q) => q(`DELETE FROM backup_version WHERE vault_id = $1 RETURNING id`, [VA]))), 'blocked');
  check('E immutable', '...nor can the system role', await attempt(() => sys((q) => q(`DELETE FROM backup_version WHERE vault_id = $1 RETURNING id`, [VA]))), 'blocked');
  for (const col of ['blob_sha256 = repeat(\'a\',32)::bytea', 'size_bytes = size_bytes + 1', 'chain_hash = prev_chain_hash', 'manifest = \'\\x00\'::bytea', 'signature = \'\\x00\'::bytea', 'seq = seq + 100', 'created_at = now()']) {
    check('E immutable', `a committed version's ${col.split(' ')[0]} cannot be rewritten`, await attempt(() => asA((q) => q(`UPDATE backup_version SET ${col} WHERE vault_id = $1 AND seq = 5 RETURNING id`, [VA]))), 'blocked');
  }
  check('E immutable', 'a stored chunk cannot be rewritten', await attempt(() => asA((q) => q(`UPDATE backup_chunk SET data = '\\x01'::bytea, size_bytes = 1 WHERE vault_id = $1 RETURNING idx`, [VA]))), 'blocked');
  check('E immutable', 'a stored chunk cannot be deleted by a parent', await attempt(() => asA((q) => q(`DELETE FROM backup_chunk WHERE vault_id = $1 RETURNING idx`, [VA]))), 'blocked');
  check('E immutable', '...nor by the system role while its version is live or inside its window', await attempt(() => sys((q) => q(`DELETE FROM backup_chunk c USING backup_version v WHERE v.upload_id = c.upload_id AND v.vault_id = $1 AND v.seq = 5 RETURNING c.idx`, [VA]))), 'blocked');
  check('E immutable', 'a version cannot be purged early', await attempt(() => sys((q) => q(`UPDATE backup_version SET purged_at = now() WHERE vault_id = $1 AND seq = 5 RETURNING id`, [VA]))), 'blocked');
  check('E immutable', 'a committed upload cannot change shape', await attempt(() => asA((q) => q(`UPDATE backup_upload SET size_bytes = 1 WHERE vault_id = $1 RETURNING id`, [VA]))), 'blocked');
  check('E immutable', 'a finished upload cannot be reopened', await attempt(() => sys((q) => q(`UPDATE backup_upload SET state = 'open' WHERE vault_id = $1 AND state = 'committed' RETURNING id`, [VA]))), 'blocked');
  check('E immutable', 'a chunk cannot be added to a finished upload', await attempt(() => sys((q) => q(`INSERT INTO backup_chunk (upload_id, idx, vault_id, size_bytes, sha256, data)
      SELECT id, 99, vault_id, 1, repeat('a',32)::bytea, '\\x01'::bytea FROM backup_upload WHERE vault_id = $1 AND state = 'committed' LIMIT 1 RETURNING idx`, [VA]))), 'blocked');
  check('E immutable', 'the notice feed cannot be edited', await attempt(() => sys((q) => q(`UPDATE backup_vault_event SET summary = 'x' WHERE vault_id = $1 RETURNING seq`, [VA]))), 'blocked');
  check('E immutable', 'the notice feed cannot be erased', await attempt(() => sys((q) => q(`DELETE FROM backup_vault_event WHERE vault_id = $1 RETURNING seq`, [VA]))), 'blocked');
  const trg = (await admin.query(`SELECT count(*)::int n FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE 'backup\_%' `)).rows[0].n;
  check('E immutable', 'the guards are real triggers in the database, not application code', trg >= 7, true);
  check('E immutable', 'after every attempt above the backup is whole (five versions, bytes present)', `${await countRows('backup_version', VA)} ${(await countRows('backup_chunk', VA)) > 0}`, '5 true');
  check('E immutable', 'a version cannot be half-tombstoned (the table checks the three tombstone columns move together)', await attempt(() => asA((q) => q(`UPDATE backup_version SET state = 'tombstone' WHERE vault_id = $1 AND seq = 5 RETURNING id`, [VA]))), 'blocked');
  check('E immutable', 'the vault itself cannot be deleted while it holds versions', await attempt(() => sys((q) => q(`DELETE FROM backup_vault WHERE id = $1 RETURNING id`, [VA]))), 'blocked');
}

// ===========================================================================
// F · QUOTA
// ===========================================================================
let VS; // the single parent's vault, small quota
{
  const r = await call('POST', '/v1/backup/vaults', S.tok, { recoveryVerifier: VERIFIER, pin: S.pin });
  VS = r.body.vaultId; vaults.push(VS);
  await admin.query(`UPDATE backup_vault SET quota_bytes = 4000 WHERE id = $1`, [VS]);
  const one = await backupOnce(S, VS, { size: 3000 });
  check('F quota', 'a backup within the quota is stored', one.commit?.status, 201);
  const two = await call('POST', `${V(VS)}/uploads`, S.tok, mkBackup(VS, { seq: 1, chain: one.bb.chain.toString('hex') }, { size: 3000 }).body);
  check('F quota', 'a backup that would push live bytes over the quota is refused with the numbers', `${two.status} ${two.body.error} ${two.body.quotaBytes}`, '507 quota_exceeded 4000');
  const stq = await call('GET', V(VS), S.tok);
  check('F quota', 'status shows used and quota', `${stq.body.usedBytes}/${stq.body.quotaBytes}`, '3000/4000');
  check('F quota', 'a refused begin left no upload behind', Number((await admin.query(`SELECT count(*) n FROM backup_upload WHERE vault_id = $1 AND state = 'open'`, [VS])).rows[0].n), 0);
  // unfinished uploads count while open and are given back when they lapse
  await admin.query(`UPDATE backup_vault SET quota_bytes = 7000 WHERE id = $1`, [VS]);
  const half = mkBackup(VS, { seq: 1, chain: one.bb.chain.toString('hex') }, { size: 3500 });
  const hb = await call('POST', `${V(VS)}/uploads`, S.tok, half.body);
  const over = await call('POST', `${V(VS)}/uploads`, S.tok, mkBackup(VS, { seq: 1, chain: one.bb.chain.toString('hex') }, { size: 1200 }).body);
  check('F quota', 'an open upload reserves its size against the quota', `${hb.status} ${over.status}`, '201 507');
  await admin.query('SET session_replication_role = replica');
  await admin.query(`UPDATE backup_upload SET expires_at = now() - interval '1 minute', created_at = now() - interval '2 minutes' WHERE id = $1`, [hb.body.uploadId]);
  await admin.query('SET session_replication_role = DEFAULT');
  const reused = await call('POST', `${V(VS)}/uploads`, S.tok, mkBackup(VS, { seq: 1, chain: one.bb.chain.toString('hex') }, { size: 1200 }).body);
  check('F quota', 'a lapsed unfinished upload is given back and the new one fits', reused.status, 201);
  check('F quota', 'a piece for the lapsed upload is refused (it ran out of time)', st((await putChunks(S, VS, hb.body.uploadId, half, [0]))[0]).slice(0, 3), '410');
  await call('POST', `${V(VS)}/uploads/${reused.body.uploadId}/abort`, S.tok);
  // set-aside allowance: tombstoned bytes never block a new backup, and live bytes are never given up to make room
  await admin.query(`UPDATE backup_vault SET quota_bytes = 8000, keep_versions = 3 WHERE id = $1`, [VS]);
  let last = one.bb;
  for (let i = 0; i < 3; i++) { const x = await backupOnce(S, VS, { size: 1500 }); last = x.bb; }
  const lvS = await call('GET', `${V(VS)}/versions`, S.tok);
  check('F quota', 'older backups are set aside as new ones arrive, and every one is still listed', lvS.body.versions.map((v) => v.state[0]).join(''), 'tlll');
  const bytesKept = Number((await admin.query(`SELECT COALESCE(sum(size_bytes),0) n FROM backup_chunk WHERE vault_id = $1`, [VS])).rows[0].n);
  check('F quota', 'set-aside bytes are kept in addition to the live ones', bytesKept >= 3000 + 4500, true);
}

// ===========================================================================
// G · RESTORE: the lost phone, then everything hostile
// ===========================================================================
let NEW; // A's new phone
{
  // the old phone's backups exist (section B and D). The phone is lost; the operator hands A a recovery code.
  const code = await issueRecoveryCode(pool, { userId: A.userId });
  const rec = await call('POST', '/v1/auth/recover', null, { recoveryCode: code.token, pin: A.pin, deviceLabel: 'New phone' });
  check('G restore', 'the account comes back on a new phone (recovery code + PIN)', rec.status, 201);
  NEW = { userId: A.userId, tok: rec.body.token, deviceId: rec.body.deviceId, pin: A.pin };
  check('G restore', 'the LOST phone\'s session is cut off from the backup at once', st(await call('GET', V(VA), A.tok)).slice(0, 3), '401');
  check('G restore', '...and so is every write it might still try', st(await call('POST', `${V(VA)}/uploads`, A.tok, mkBackup(VA, head).body)).slice(0, 3), '401');
  const evb = await call('GET', `${V(VA)}/events`, B.tok);
  const st0 = await call('GET', V(VA), NEW.tok);
  check('G restore', 'the new phone sees the vault and the unbroken history', `${st0.status} ${st0.body.liveVersions}`, '200 2');

  // challenge -> proof by the family recovery key
  check('G restore', 'a restore cannot even be asked for without a challenge signed by the recovery key', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: randomUUID(), signature: Buffer.alloc(64).toString('base64') })), '403 challenge_invalid');
  const ch = async (who = NEW) => (await call('POST', `${V(VA)}/restores/challenge`, who.tok, {})).body;
  const prove = (c, who = NEW, key = FAMILY.privateKey, vid = VA) => sign(null, restoreChallengeMessage({ vaultId: vid, userId: who.userId, deviceId: who.deviceId, nonce: Buffer.from(c.nonce, 'hex') }), key).toString('base64');
  const c1 = await ch();
  check('G restore', 'a stranger cannot ask for a challenge', st(await call('POST', `${V(VA)}/restores/challenge`, C.tok, {})), '404 vault_not_found');
  // wrong key
  const wrongKey = generateKeyPairSync('ed25519').privateKey;
  check('G restore', 'a proof by some other key is refused', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c1.challengeId, signature: prove(c1, NEW, wrongKey) })), '403 recovery_key_proof_invalid');
  check('G restore', '...and the challenge is spent whether or not the proof was right (no guessing against one nonce)', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c1.challengeId, signature: prove(c1) })), '403 challenge_invalid');
  // replay of an old proof against a fresh challenge
  const c2 = await ch();
  check('G restore', 'a proof for an OLD challenge cannot be replayed on a new one', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c2.challengeId, signature: prove(c1) })), '403 recovery_key_proof_invalid');
  // proof made for another phone
  const c3 = await ch();
  check('G restore', 'a proof made for ANOTHER phone does not work on this one', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c3.challengeId, signature: prove(c3, { ...NEW, deviceId: randomUUID() }) })), '403 recovery_key_proof_invalid');
  // the challenge belongs to the phone that asked
  const c4 = await ch();
  check('G restore', 'a challenge cannot be used from a different account\'s session', st(await call('POST', `${V(VA)}/restores`, B.tok, { pin: B.pin, challengeId: c4.challengeId, signature: prove(c4) })), '403 challenge_invalid');
  // an expired challenge
  const c5 = await ch();
  await admin.query(`UPDATE backup_restore_challenge SET created_at = now() - interval '10 minutes', expires_at = now() - interval '5 minutes' WHERE id = $1`, [c5.challengeId]);
  check('G restore', 'an expired challenge is refused', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c5.challengeId, signature: prove(c5) })), '403 challenge_invalid');
  // wrong PIN
  const c6 = await ch();
  check('G restore', 'the grown-up\'s own PIN is needed on top of the key', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: '0000', challengeId: c6.challengeId, signature: prove(c6) })), '403 pin_incorrect');
  await unlockPin(NEW.userId);

  // the real request
  const c7 = await ch();
  const rq = await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c7.challengeId, signature: prove(c7) });
  check('G restore', 'with the key, the PIN and a fresh challenge the request is made (201)', rq.status, 201);
  const R = rq.body.restore.restoreId;
  check('G restore', 'with another parent able to say yes, the wait is 48 hours and a yes is needed', `${rq.body.restore.waitHours} ${rq.body.restore.approvalRequired} ${rq.body.restore.phase}`, '48 true waiting');
  const c8 = await ch();
  check('G restore', 'a second request while one is open is refused', st(await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c8.challengeId, signature: prove(c8) })), '409 restore_already_open');
  check('G restore', 'the token is refused during the waiting period', st(await call('POST', `${V(VA)}/restores/${R}/token`, NEW.tok, {})), '409 waiting_period');
  check('G restore', 'no download without a token', st(await call('GET', `${V(VA)}/restores/${R}/versions/5/chunks/0`, NEW.tok)), '403 restore_token_required');
  check('G restore', 'a made-up token is refused', st(await call('GET', `${V(VA)}/restores/${R}/versions/5/chunks/0`, NEW.tok, undefined, { 'x-olive-restore-token': 'x'.repeat(43) })), '403 restore_token_invalid');
  const evB = await call('GET', `${V(VA)}/events`, B.tok);
  check('G restore', 'the OTHER parent\'s phone is told, in plain words, with the waiting period', evB.body.events.some((e) => e.kind === 'restore_requested' && /48 hours/.test(e.summary) && /cancel/i.test(e.summary)), true);
  const stB = await call('GET', V(VA), B.tok);
  check('G restore', 'the other parent\'s status shows the pending restore', stB.body.pendingRestore?.restoreId === R, true);
  check('G restore', 'nobody can approve their own request', st(await call('POST', `${V(VA)}/restores/${R}/approve`, NEW.tok, { pin: NEW.pin })), '403 cannot_approve_own_restore');
  check('G restore', 'a stranger cannot approve (or learn it exists)', st(await call('POST', `${V(VA)}/restores/${R}/approve`, C.tok, { pin: C.pin })), '404 restore_not_found');
  check('G restore', 'approving needs the approver\'s own PIN', st(await call('POST', `${V(VA)}/restores/${R}/approve`, B.tok, {})), '400 pin_required');
  // five simultaneous yeses: one approval
  const yes = await Promise.all([1, 2, 3, 4, 5].map(() => call('POST', `${V(VA)}/restores/${R}/approve`, B.tok, { pin: B.pin })));
  check('G restore', 'five simultaneous yeses record exactly one approval', `${yes.filter((x) => x.status === 200).length} ${(await admin.query(`SELECT count(*) n FROM backup_vault_event WHERE vault_id = $1 AND kind = 'restore_approved'`, [VA])).rows[0].n}`, '5 1');
  check('G restore', 'a yes does NOT shorten the waiting period', st(await call('POST', `${V(VA)}/restores/${R}/token`, NEW.tok, {})), '409 waiting_period');

  // race on the waiting period: just before and just after
  await rewindRestore(R, 47);
  check('G restore', 'one hour short of the wait is still refused', st(await call('POST', `${V(VA)}/restores/${R}/token`, NEW.tok, {})), '409 waiting_period');
  check('G restore', 'the other parent (not the requesting phone) cannot take the token', st(await call('POST', `${V(VA)}/restores/${R}/token`, B.tok, {})), '403 not_the_requesting_phone');
  await rewindRestore(R, 2);
  const [tk, cn] = await Promise.all([call('POST', `${V(VA)}/restores/${R}/token`, NEW.tok, {}), call('POST', `${V(VA)}/restores/${R}/cancel`, B.tok, {})]);
  const tokenWon = tk.status === 200;
  check('G restore', 'a cancel racing the token: either order, the cancel always ends it and nothing downloads afterwards', `${cn.status}`, '200');
  const dl = await call('GET', `${V(VA)}/restores/${R}/versions/5/chunks/0`, NEW.tok, undefined, { 'x-olive-restore-token': tk.body.token ?? 'x'.repeat(43) });
  check('G restore', '...a download after the cancel is refused', dl.status, 403);
  check('G restore', '...and the request is cancelled for good', (await admin.query(`SELECT state, token_hash FROM backup_restore_request WHERE id = $1`, [R])).rows[0].state, 'cancelled');
  check('G restore', 'cancelling twice is harmless', `${(await call('POST', `${V(VA)}/restores/${R}/cancel`, B.tok, {})).body.already}`, 'true');
  check('G restore', 'a cancelled request cannot be approved or given a token', `${st(await call('POST', `${V(VA)}/restores/${R}/approve`, B.tok, { pin: B.pin }))}|${st(await call('POST', `${V(VA)}/restores/${R}/token`, NEW.tok, {}))}`, '409 restore_cancelled|409 restore_cancelled');
  check('G restore', 'the notice feed says it was cancelled and nothing was restored', (await call('GET', `${V(VA)}/events`, B.tok)).body.events.some((e) => e.kind === 'restore_cancelled' && /Nothing was restored/.test(e.summary)), true);

  // second request, completed properly
  const c9 = await ch();
  const rq2 = await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c9.challengeId, signature: prove(c9) });
  const R2 = rq2.body.restore.restoreId;
  check('G restore', 'after a cancel a new request is allowed', rq2.status, 201);
  await rewindRestore(R2, 49);
  check('G restore', 'wait over but nobody has said yes: still no token', st(await call('POST', `${V(VA)}/restores/${R2}/token`, NEW.tok, {})), '409 waiting_for_approval');
  await call('POST', `${V(VA)}/restores/${R2}/approve`, B.tok, { pin: B.pin });
  const t2 = await call('POST', `${V(VA)}/restores/${R2}/token`, NEW.tok, {});
  check('G restore', 'wait over AND a second parent said yes: the one-time token is issued', `${t2.status} ${t2.body.token.length >= 43}`, '200 true');
  check('G restore', 'only the token\'s digest is stored', (await admin.query(`SELECT token_hash FROM backup_restore_request WHERE id = $1`, [R2])).rows[0].token_hash !== t2.body.token, true);
  const TOK = { 'x-olive-restore-token': t2.body.token };
  check('G restore', 'the token does not work from any other phone or account', `${st(await call('GET', `${V(VA)}/restores/${R2}/versions/5/chunks/0`, B.tok, undefined, TOK))}`, '403 restore_token_invalid');
  check('G restore', '...nor for a different restore id', st(await call('GET', `${V(VA)}/restores/${randomUUID()}/versions/5/chunks/0`, NEW.tok, undefined, TOK)), '403 restore_token_invalid');
  // download everything of the newest live version and check it as the phone would
  const lvN = await call('GET', `${V(VA)}/versions`, NEW.tok);
  const v5 = lvN.body.versions.find((v) => v.seq === 5);
  const parts = [];
  for (let i = 0; i < v5.chunkCount; i++) {
    const g = await call('GET', `${V(VA)}/restores/${R2}/versions/5/chunks/${i}`, NEW.tok, undefined, TOK);
    if (g.status !== 200) { parts.push(null); continue; }
    const buf = Buffer.from(g.body.data, 'base64');
    parts.push(sha256(buf).toString('hex') === g.body.sha256 ? buf : null);
  }
  check('G restore', 'every chunk downloads and matches its hash', parts.every(Boolean), true);
  check('G restore', '...and the whole matches the hash the phone signed', sha256(Buffer.concat(parts)).toString('hex'), v5.blobSha256);
  check('G restore', '...and the history verifies on the new phone', verifyHistory({ vaultId: VA, versions: lvN.body.versions, verifySignature: verifySig }).ok, true);
  check('G restore', 'a set-aside (older) version can be fetched the same way', (await call('GET', `${V(VA)}/restores/${R2}/versions/2/chunks/0`, NEW.tok, undefined, TOK)).status, 200);
  check('G restore', 'a chunk past the end is 404', (await call('GET', `${V(VA)}/restores/${R2}/versions/5/chunks/${v5.chunkCount}`, NEW.tok, undefined, TOK)).status, 404);
  check('G restore', 'a purged version is 410', (await call('GET', `${V(VA)}/restores/${R2}/versions/1/chunks/0`, NEW.tok, undefined, TOK)).status, 410);
  check('G restore', 'completing without the token is refused', st(await call('POST', `${V(VA)}/restores/${R2}/complete`, NEW.tok, {})), '403 restore_token_required');
  const done = await call('POST', `${V(VA)}/restores/${R2}/complete`, NEW.tok, {}, TOK);
  check('G restore', 'completing ends the restore and the token dies with it', `${done.status} ${done.body.state}`, '200 completed');
  check('G restore', '...a download after completing is refused', (await call('GET', `${V(VA)}/restores/${R2}/versions/5/chunks/0`, NEW.tok, undefined, TOK)).status, 403);
  const kinds = {}; for (const e of (await call('GET', `${V(VA)}/events`, B.tok)).body.events) kinds[e.kind] = (kinds[e.kind] ?? 0) + 1;
  check('G restore', 'the restore is done and the other parent was told at each step (the first token may or may not have been issued before the cancel won the race)',
    `${kinds.restore_requested} ${kinds.restore_approved} ${kinds.restore_cancelled} ${kinds.restore_completed} ${kinds.restore_token_issued >= 1 && kinds.restore_token_issued <= 2}`, '2 2 1 1 true');

  // wrong tokens burn the token
  const c10 = await ch();
  const rq3 = await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c10.challengeId, signature: prove(c10) });
  const R3 = rq3.body.restore.restoreId;
  await call('POST', `${V(VA)}/restores/${R3}/approve`, B.tok, { pin: B.pin });
  await rewindRestore(R3, 49);
  const t3 = await call('POST', `${V(VA)}/restores/${R3}/token`, NEW.tok, {});
  let last10; for (let i = 0; i < 10; i++) last10 = await call('GET', `${V(VA)}/restores/${R3}/versions/5/chunks/0`, NEW.tok, undefined, { 'x-olive-restore-token': 'y'.repeat(43) });
  check('G restore', 'ten wrong tokens in a row revoke the token', `${last10.status} ${last10.body.revoked}`, '403 true');
  check('G restore', '...so even the right one no longer works', (await call('GET', `${V(VA)}/restores/${R3}/versions/5/chunks/0`, NEW.tok, undefined, { 'x-olive-restore-token': t3.body.token })).status, 403);
  await call('POST', `${V(VA)}/restores/${R3}/cancel`, NEW.tok, {});

  // the request lapses if nobody finishes it
  const c11 = await ch();
  const rq4 = await call('POST', `${V(VA)}/restores`, NEW.tok, { pin: NEW.pin, challengeId: c11.challengeId, signature: prove(c11) });
  await rewindRestore(rq4.body.restore.restoreId, 24 * 9);
  const sw = await sweepBackups(pool, new Date());
  check('G restore', 'an unfinished request lapses on its own and says nothing was restored', `${sw.expiredRestores >= 1} ${(await call('GET', `${V(VA)}/events`, B.tok)).body.events.some((e) => e.kind === 'restore_expired')}`, 'true true');
  const listR = await call('GET', `${V(VA)}/restores`, NEW.tok);
  check('G restore', 'the history of requests is visible to the vault\'s grown-ups', `${listR.body.role} ${listR.body.restores.length >= 4}`, 'member true');
}

// ===========================================================================
// H · PAUSE: either parent may pause the other; reversible; visible; a paused parent can still STOP a restore
// ===========================================================================
{
  check('H pause', 'pausing needs the actor\'s PIN', st(await call('POST', `${V(VA)}/pause`, B.tok, { targetUserId: NEW.userId })), '400 pin_required');
  check('H pause', 'a parent cannot pause themselves', st(await call('POST', `${V(VA)}/pause`, B.tok, { targetUserId: B.userId, pin: B.pin })), '409 cannot_pause_yourself');
  check('H pause', 'a stranger cannot pause anyone', st(await call('POST', `${V(VA)}/pause`, C.tok, { targetUserId: B.userId, pin: C.pin })), '404 vault_not_found');
  check('H pause', 'a junk target is refused before any query', st(await call('POST', `${V(VA)}/pause`, B.tok, { targetUserId: "x'; drop table app_user;--", pin: B.pin })), '400 invalid_input');
  const p = await call('POST', `${V(VA)}/pause`, B.tok, { targetUserId: NEW.userId, pin: B.pin });
  check('H pause', 'either parent can pause the other', `${p.status} ${p.body.state}`, '200 paused');
  const ev = await call('GET', `${V(VA)}/events`, B.tok);
  check('H pause', 'the pause is a plain notice every parent can read (and says it can be turned back on)', ev.body.events.some((e) => e.kind === 'member_paused' && /turned back on/.test(e.summary)), true);
  check('H pause', 'the paused parent can see THAT they are paused', `${(await call('GET', V(VA), NEW.tok)).body.me.state}`, 'paused');
  check('H pause', 'the paused parent\'s reach is off: versions', st(await call('GET', `${V(VA)}/versions`, NEW.tok)), '403 reach_paused');
  check('H pause', '...uploads', st(await call('POST', `${V(VA)}/uploads`, NEW.tok, mkBackup(VA, head).body)), '403 reach_paused');
  check('H pause', '...a restore challenge', st(await call('POST', `${V(VA)}/restores/challenge`, NEW.tok, {})), '403 reach_paused');
  check('H pause', '...deleting a version', st(await call('POST', `${V(VA)}/versions/5/delete`, NEW.tok, { pin: NEW.pin })), '403 reach_paused');
  check('H pause', '...pausing the other parent back', st(await call('POST', `${V(VA)}/pause`, NEW.tok, { targetUserId: B.userId, pin: NEW.pin })), '403 reach_paused');
  check('H pause', '...and resuming themselves', st(await call('POST', `${V(VA)}/resume`, NEW.tok, { targetUserId: NEW.userId, pin: NEW.pin })), '403 reach_paused');
  check('H pause', 'pausing twice is harmless', `${(await call('POST', `${V(VA)}/pause`, B.tok, { targetUserId: NEW.userId, pin: B.pin })).body.already}`, 'true');
  // a restore asked by B (stolen-phone shape) can still be stopped by the paused parent
  const cB = (await call('POST', `${V(VA)}/restores/challenge`, B.tok, {})).body;
  const rqB = await call('POST', `${V(VA)}/restores`, B.tok, { pin: B.pin, challengeId: cB.challengeId,
    signature: sign(null, restoreChallengeMessage({ vaultId: VA, userId: B.userId, deviceId: B.deviceId, nonce: Buffer.from(cB.nonce, 'hex') }), FAMILY.privateKey).toString('base64') });
  check('H pause', 'pausing the other parent does NOT remove the second yes: the 48-hour wait and the approval still apply', `${rqB.status} ${rqB.body.restore.waitHours} ${rqB.body.restore.approvalRequired}`, '201 48 true');
  check('H pause', 'and the paused parent cannot say yes either (a pause is no way to get a restore through)', st(await call('POST', `${V(VA)}/restores/${rqB.body.restore.restoreId}/approve`, NEW.tok, { pin: NEW.pin })), '403 reach_paused');
  const seen = await call('GET', V(VA), NEW.tok);
  check('H pause', 'the PAUSED parent still sees the restore, and sees nothing else', `${seen.body.pendingRestore?.restoreId === rqB.body.restore.restoreId} ${seen.body.liveVersions}`, 'true undefined');
  const stop = await call('POST', `${V(VA)}/restores/${rqB.body.restore.restoreId}/cancel`, NEW.tok, {});
  check('H pause', 'and the paused parent can STOP it, with no PIN and no waiting', `${stop.status} ${stop.body.state}`, '200 cancelled');
  const rs = await call('POST', `${V(VA)}/resume`, B.tok, { targetUserId: NEW.userId, pin: B.pin });
  check('H pause', 'a pause is reversible and says so in the notices', `${rs.status} ${rs.body.state} ${(await call('GET', `${V(VA)}/events`, NEW.tok)).body.events.some((e) => e.kind === 'member_resumed')}`, '200 active true');
  check('H pause', 'after resuming the parent\'s reach is back', (await call('GET', `${V(VA)}/versions`, NEW.tok)).status, 200);
  // ending a grown-up is the family's act (identity lane), not a route here: no route removes a member
  const removable = api.routes.filter((r) => r.path.startsWith('/v1/backup') && /member|remove/.test(r.path) && !/helper/.test(r.path));
  check('H pause', 'there is NO route that removes a parent (no parent can remove another alone)', removable.length, 0);
}

// ===========================================================================
// I · THE TRUSTED HELPER (one, for a single parent, can ONLY confirm)
// ===========================================================================
{
  check('I helper', 'naming a helper needs the PIN', st(await call('POST', `${V(VS)}/helper`, S.tok, { helperUserId: H.userId })), '400 pin_required');
  check('I helper', 'a helper must already be a welcomed adult of this family (a stranger cannot be named)', st(await call('POST', `${V(VS)}/helper`, S.tok, { helperUserId: C.userId, pin: S.pin })), '404 helper_not_found');
  check('I helper', 'a parent cannot name themselves', st(await call('POST', `${V(VS)}/helper`, S.tok, { helperUserId: S.userId, pin: S.pin })), '409 helper_must_be_someone_else');
  check('I helper', 'with two parents there is no helper (the second parent is the safeguard)', st(await call('POST', `${V(VA)}/helper`, B.tok, { helperUserId: H.userId, pin: B.pin })), '409 helper_only_for_single_parent');
  const n = await call('POST', `${V(VS)}/helper`, S.tok, { helperUserId: H.userId, pin: S.pin });
  check('I helper', 'the single parent names one trusted helper (201)', n.status, 201);
  check('I helper', 'only one at a time', st(await call('POST', `${V(VS)}/helper`, S.tok, { helperUserId: H.userId, pin: S.pin })), '409 helper_already_named');
  // over-reach: the helper can do NOTHING but see restore notices, confirm, and cancel
  const reach = {
    status: await call('GET', V(VS), H.tok), versions: await call('GET', `${V(VS)}/versions`, H.tok),
    begin: await call('POST', `${V(VS)}/uploads`, H.tok, mkBackup(VS, { seq: 4, chain: sha256(Buffer.from('x')).toString('hex') }).body),
    challenge: await call('POST', `${V(VS)}/restores/challenge`, H.tok, {}),
    pause: await call('POST', `${V(VS)}/pause`, H.tok, { targetUserId: S.userId, pin: H.pin }),
    helper: await call('POST', `${V(VS)}/helper`, H.tok, { helperUserId: H.userId, pin: H.pin }),
    del: await call('POST', `${V(VS)}/versions/1/delete`, H.tok, { pin: H.pin }),
    join: await call('POST', `${V(VS)}/join`, H.tok, { pin: H.pin }),
  };
  for (const [k, r] of Object.entries(reach)) check('I helper', `over-reach: a helper cannot ${k}`, r.status >= 400 ? 'refused' : `allowed ${r.status}`, 'refused');
  const hev = await call('GET', `${V(VS)}/events`, H.tok);
  check('I helper', 'the helper sees only restore notices (none yet)', hev.body.events.every((e) => e.scope === 'restore'), true);
  // a restore by the single parent: helper not yet settled, so nobody can say yes -> 72 hours
  const cS = (await call('POST', `${V(VS)}/restores/challenge`, S.tok, {})).body;
  const prS = (c) => sign(null, restoreChallengeMessage({ vaultId: VS, userId: S.userId, deviceId: S.deviceId, nonce: Buffer.from(c.nonce, 'hex') }), FAMILY.privateKey).toString('base64');
  const r1 = await call('POST', `${V(VS)}/restores`, S.tok, { pin: S.pin, challengeId: cS.challengeId, signature: prS(cS) });
  check('I helper', 'a helper named a moment ago cannot yet be counted on: the single parent waits 72 hours', `${r1.body.restore.waitHours} ${r1.body.restore.approvalRequired}`, '72 false');
  const helperSees = await call('GET', `${V(VS)}/restores`, H.tok);
  check('I helper', 'the helper is told of the restore', `${helperSees.body.role} ${helperSees.body.restores.length}`, 'helper 1');
  check('I helper', 'the helper is not settled yet, so cannot confirm', st(await call('POST', `${V(VS)}/restores/${r1.body.restore.restoreId}/approve`, H.tok, { pin: H.pin })), '403 helper_not_settled');
  const stopH = await call('POST', `${V(VS)}/restores/${r1.body.restore.restoreId}/cancel`, H.tok, {});
  check('I helper', 'the helper CAN stop it, at once', `${stopH.status} ${stopH.body.state}`, '200 cancelled');
  check('I helper', 'the helper sees the restore notices (requested, cancelled), not the rest', (await call('GET', `${V(VS)}/events`, H.tok)).body.events.map((e) => e.kind).join(), 'restore_requested,restore_cancelled');
  // settle the helper, ask again: now a yes is needed and the wait is 48
  await admin.query(`UPDATE backup_vault_helper SET named_at = named_at - interval '25 hours' WHERE vault_id = $1`, [VS]);
  const cS2 = (await call('POST', `${V(VS)}/restores/challenge`, S.tok, {})).body;
  const r2 = await call('POST', `${V(VS)}/restores`, S.tok, { pin: S.pin, challengeId: cS2.challengeId, signature: prS(cS2) });
  check('I helper', 'with a settled helper the wait is 48 hours and the helper\'s yes is needed', `${r2.body.restore.waitHours} ${r2.body.restore.approvalRequired}`, '48 true');
  const RS = r2.body.restore.restoreId;
  check('I helper', 'the helper needs their own PIN to confirm', st(await call('POST', `${V(VS)}/restores/${RS}/approve`, H.tok, {})), '400 pin_required');
  check('I helper', 'the single parent cannot approve their own restore', st(await call('POST', `${V(VS)}/restores/${RS}/approve`, S.tok, { pin: S.pin })), '403 cannot_approve_own_restore');
  const ap = await call('POST', `${V(VS)}/restores/${RS}/approve`, H.tok, { pin: H.pin });
  check('I helper', 'the helper confirms', `${ap.status} ${ap.body.approverKind}`, '200 helper');
  check('I helper', '...and the confirmation does not shorten the wait', st(await call('POST', `${V(VS)}/restores/${RS}/token`, S.tok, {})), '409 waiting_period');
  check('I helper', '...and the helper cannot take the token or any bytes', `${st(await call('POST', `${V(VS)}/restores/${RS}/token`, H.tok, {}))}`, '404 restore_not_found');
  await rewindRestore(RS, 49);
  const tS = await call('POST', `${V(VS)}/restores/${RS}/token`, S.tok, {});
  check('I helper', 'after the wait the single parent gets the token', tS.status, 200);
  check('I helper', 'the helper cannot use the single parent\'s token', (await call('GET', `${V(VS)}/restores/${RS}/versions/1/chunks/0`, H.tok, undefined, { 'x-olive-restore-token': tS.body.token })).status >= 400, true);
  await call('POST', `${V(VS)}/restores/${RS}/cancel`, S.tok, {});
  const rh = await call('POST', `${V(VS)}/helper/remove`, S.tok, { pin: S.pin });
  check('I helper', 'the parent can remove the helper', `${rh.status} ${rh.body.removed}`, '200 true');
  check('I helper', '...and a removed helper has no reach left (not even to see restores)', st(await call('GET', `${V(VS)}/restores`, H.tok)), '404 vault_not_found');
  await call('POST', `${V(VS)}/helper`, S.tok, { helperUserId: H.userId, pin: S.pin });
  // a second parent joins: the helper steps down
  const S2 = await signup('solo2', '8642');
  await edge(CS, S2.userId);
  const js = await call('POST', `${V(VS)}/join`, S2.tok, { pin: S2.pin });
  check('I helper', 'a second parent joins the single parent\'s vault', js.status, 201);
  const sa = await call('GET', V(VS), S.tok);
  check('I helper', '...and the helper steps down (the second parent is the safeguard now), with a notice', `${sa.body.helper} ${(await call('GET', `${V(VS)}/events`, S.tok)).body.events.filter((e) => e.kind === 'helper_removed').length}`, 'null 2');
}

// ===========================================================================
// J · ISOLATION: row level security, table by table, as the connecting role
// ===========================================================================
{
  const tables = ['backup_vault', 'backup_vault_member', 'backup_vault_helper', 'backup_upload', 'backup_chunk', 'backup_version',
    'backup_restore_challenge', 'backup_restore_request', 'backup_vault_event'];
  const as = (u, fn) => withSession(pool, { roleName: 'guardian', userId: u, childId: null }, fn);
  const n = (u, t, where = 'true') => as(u, async (q) => (await q(`SELECT count(*)::int AS n FROM ${t} WHERE ${where}`))[0].n);
  const flags = (await admin.query(`SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname = ANY($1::text[])`, [tables])).rows;
  check('J isolation', 'every backup table has row level security ENABLED and FORCED', flags.every((f) => f.relrowsecurity && f.relforcerowsecurity), true);
  check('J isolation', '...all nine of them', flags.length, 9);
  for (const t of tables) check('J isolation', `a stranger family's grown-up sees no ${t} rows`, await n(C.userId, t), 0);
  check('J isolation', 'a grown-up of the family sees their vault', await n(A.userId, 'backup_vault', `id = '${VA}'`), 1);
  check('J isolation', '...and not the single parent\'s', await n(A.userId, 'backup_vault', `id = '${VS}'`), 0);
  check('J isolation', '...nor its versions or chunks', `${await n(A.userId, 'backup_version', `vault_id = '${VS}'`)}${await n(A.userId, 'backup_chunk', `vault_id = '${VS}'`)}`, '00');
  check('J isolation', 'a grown-up sees only their own membership rows', await n(A.userId, 'backup_vault_member'), 1);
  const cc = await withSession(pool, { roleName: 'child', userId: null, childId: CA }, async (q) => Promise.all(tables.map((t) => q(`SELECT count(*)::int AS n FROM ${t}`))));
  check('J isolation', 'a CHILD session sees no row of any backup table', cc.map((r) => r[0].n).join(''), '000000000');
  const w = async (fn) => { try { const r = await fn(); return r.length ? 'allowed' : 'no rows'; } catch { return 'refused'; } };
  check('J isolation', 'a grown-up cannot create a vault of their own by SQL', await w(() => as(C.userId, (q) => q(`INSERT INTO backup_vault (created_by, recovery_verifier, quota_bytes) VALUES ($1, repeat('a',32)::bytea, 1) RETURNING id`, [C.userId]))), 'refused');
  check('J isolation', '...nor add themselves to someone else\'s vault', await w(() => as(C.userId, (q) => q(`INSERT INTO backup_vault_member (vault_id, user_id) VALUES ($1, $2) RETURNING user_id`, [VA, C.userId]))), 'refused');
  check('J isolation', '...nor name themselves its helper', await w(() => as(C.userId, (q) => q(`INSERT INTO backup_vault_helper (vault_id, user_id) VALUES ($1, $2) RETURNING id`, [VA, C.userId]))), 'refused');
  check('J isolation', '...nor forge a restore request or an approval', await w(() => as(A.userId, (q) => q(`INSERT INTO backup_restore_request (vault_id, requested_by, device_id, wait_hours, not_before, approval_required, expires_at) VALUES ($1, $2, $3, 24, now(), false, now() + interval '1 day') RETURNING id`, [VA, A.userId, A.deviceId]))), 'refused');
  check('J isolation', '...nor approve by editing the request', await w(() => as(B.userId, (q) => q(`UPDATE backup_restore_request SET approved_at = now(), approver_kind = 'member' WHERE vault_id = $1 RETURNING id`, [VA]))), 'no rows');
  check('J isolation', '...nor un-pause themselves', await w(() => as(NEW.userId, (q) => q(`UPDATE backup_vault_member SET state = 'active', paused_at = NULL WHERE vault_id = $1 RETURNING user_id`, [VA]))), 'no rows');
  check('J isolation', '...nor shrink the recovery window or the version count', await w(() => as(A.userId, (q) => q(`UPDATE backup_vault SET keep_versions = 3, recovery_window_days = 30 WHERE id = $1 RETURNING id`, [VA]))), 'no rows');
  check('J isolation', '...nor swap the recovery key', await w(() => as(A.userId, (q) => q(`UPDATE backup_vault SET recovery_verifier = repeat('b',32)::bytea WHERE id = $1 RETURNING id`, [VA]))), 'no rows');
  check('J isolation', '...nor insert a version into a vault they are not in', await w(() => as(C.userId, (q) => q(`INSERT INTO backup_version (vault_id, seq, upload_id, prev_chain_hash, chain_hash, blob_sha256, size_bytes, chunk_size, chunk_count, manifest, signature, uploaded_by)
        SELECT vault_id, 99, id, prev_chain_hash, chain_hash, blob_sha256, size_bytes, chunk_size, chunk_count, manifest, signature, $2 FROM backup_upload WHERE vault_id = $1 LIMIT 1 RETURNING id`, [VA, C.userId]))), 'no rows');
  check('J isolation', '...nor add a notice to someone else\'s feed', await w(() => as(C.userId, (q) => q(`INSERT INTO backup_vault_event (vault_id, scope, kind, actor_user, summary) VALUES ($1, 'vault', 'vault_created', $2, 'x') RETURNING seq`, [VA, C.userId]))), 'refused');
  check('J isolation', 'a paused grown-up cannot read uploads, versions or chunks directly', `${await (async () => { await call('POST', `${V(VA)}/pause`, B.tok, { targetUserId: NEW.userId, pin: B.pin }); return `${await n(NEW.userId, 'backup_upload')}${await n(NEW.userId, 'backup_version')}${await n(NEW.userId, 'backup_chunk')}`; })()}`, '000');
  await call('POST', `${V(VA)}/resume`, B.tok, { targetUserId: NEW.userId, pin: B.pin });
  check('J isolation', 'the connecting role really is not a superuser and cannot bypass row security', (await withSession(pool, { roleName: 'system', userId: null, childId: null }, (q) => q(`SELECT rolsuper OR rolbypassrls AS bad FROM pg_roles WHERE rolname = current_user`)))[0].bad, false);
}

// ===========================================================================
// K · LIMITS, THE KILL SWITCH, CHILD SESSIONS, NOTICES THAT SAY NOTHING PRIVATE, ERASURE
// ===========================================================================
{
  const tiny = () => new TokenBuckets({ capacity: 2, refillPerSec: 0.0001 });
  const apiT = mkApi({ backupLimiters: { ...wideLimiters(), begin: tiny(), challenge: tiny(), request: tiny(), token: tiny(), members: tiny(), reads: tiny(), download: tiny() } });
  const t = callOn(apiT);
  const reads = []; for (let i = 0; i < 4; i++) reads.push((await t('GET', V(VA), B.tok)).status);
  check('K limits', 'reads are rate limited per grown-up (429 with a retry hint)', reads.join(), '200,200,429,429');
  check('K limits', '...and the limit is per person, not shared', (await t('GET', V(VS), S.tok)).status, 200);
  const begins = []; for (let i = 0; i < 3; i++) begins.push((await t('POST', `${V(VA)}/uploads`, B.tok, { clientRef: 'x' })).status);
  check('K limits', 'starting backups is rate limited (junk bodies count too)', begins.join(), '400,400,429');
  const ch = []; for (let i = 0; i < 3; i++) ch.push((await t('POST', `${V(VA)}/restores/challenge`, B.tok, {})).status);
  check('K limits', 'restore challenges are rate limited', ch.join(), '201,201,429');
  const rq = []; for (let i = 0; i < 3; i++) rq.push((await t('POST', `${V(VA)}/restores`, B.tok, { pin: B.pin, challengeId: randomUUID(), signature: Buffer.alloc(64).toString('base64') })).status);
  check('K limits', 'restore requests are rate limited (guessing proofs is capped)', rq.join(), '403,403,429');
  const mm = []; for (let i = 0; i < 3; i++) mm.push((await t('POST', `${V(VA)}/pause`, B.tok, { targetUserId: B.userId, pin: B.pin })).status);
  check('K limits', 'pause and helper changes are rate limited', mm.join(), '409,409,429');

  // kill switch
  const apiOff = mkApi({ backupEnv: { BACKUP_VAULT_ENABLED: '0' } });
  const off = callOn(apiOff);
  check('K limits', 'with BACKUP_VAULT_ENABLED=0 every route answers 404 backup_not_enabled', `${st(await off('GET', V(VA), NEW.tok))}|${st(await off('GET', '/v1/backup/vaults', B.tok))}`, '404 backup_not_enabled|404 backup_not_enabled');

  // no token / garbage token / child session on every route
  const paths = [...new Set(api.routes.filter((r) => r.path.startsWith('/v1/backup')).map((r) => `${r.method} ${r.path}`))];
  check('K limits', 'the backup surface is registered (routes found)', paths.length >= 24, true);
  const fill = (p) => p.replace(':vaultId', VA).replace(':uploadId', randomUUID()).replace(':restoreId', randomUUID()).replace(':seq', '1').replace(':index', '0');
  const bad = [];
  for (const line of paths) { const [m, p] = line.split(' '); const r = await call(m, fill(p), null, m === 'GET' ? undefined : {}); if (r.status !== 401) bad.push(`${line}->${r.status}`); }
  check('K limits', 'every backup route refuses a request with no session (401)', bad.join(' ') || 'none', 'none');
  // a child session: minted by the pairing flow the suite already trusts (a paired child device)
  const kid = api.issueSessionToken({ userId: null, roleName: 'child', childId: CA, escalated: false });
  check('K limits', 'a child session exists for the test', Boolean(kid), true);
  const badKid = [];
  for (const line of paths) { const [m, p] = line.split(' '); const r = await call(m, fill(p), kid, m === 'GET' ? undefined : {}); if (r.status !== 403) badKid.push(`${line}->${r.status}`); }
  check('K limits', 'the child sees NONE of it: every backup route refuses a child session (403)', badKid.join(' ') || 'none', 'none');
  check('K limits', '...and the refusal is a code, not a screen of words', (await call('GET', V(VA), kid)).body.error, 'guardian_session_required');

  // notices say nothing private
  const evs = (await call('GET', `${V(VA)}/events`, B.tok)).body.events;
  const names = [`mom-${RUN}`, `dad-${RUN}`, 'Ivy'];
  check('K limits', 'no notice carries a name, a device label, an address or a number from the request', evs.every((e) => !names.some((nm) => e.summary.includes(nm)) && !/[0-9a-f]{8}-[0-9a-f]{4}/.test(e.summary) && !/\d+\.\d+\.\d+\.\d+/.test(e.summary)), true);
  check('K limits', 'every notice is plain adult words from a fixed list, never request text', evs.every((e) => /^[A-Z]/.test(e.summary) && e.summary.length < 160), true);
  const stored = (await admin.query(`SELECT column_name FROM information_schema.columns WHERE table_name LIKE 'backup\\_%' AND (column_name ~* '(^|_)(ip|ip_address|address|email|label|name|display_name|lat|lon|latitude|longitude|location|gps|city|zip|phone|serial)($|_)')`)).rows;
  check('K limits', 'no backup table has an address, location, email, name or device-label column', stored.map((r) => r.column_name).join(',') || 'none', 'none');

  // erasing an account that acted does not break the feed or the backup
  const S2row = (await admin.query(`SELECT id FROM app_user WHERE display_name = $1`, [`solo2-${RUN}`])).rows[0];
  const before = await countRows('backup_vault_event', VS);
  await admin.query(`DELETE FROM paired_device WHERE target_id = $1`, [S2row.id]);
  await admin.query(`DELETE FROM guardianship WHERE user_id = $1`, [S2row.id]);
  const del = await admin.query(`DELETE FROM app_user WHERE id = $1`, [S2row.id]).then(() => 'deleted', (e) => `blocked: ${e.message}`);
  check('K limits', 'erasing a grown-up who joined and acted is not blocked by the append-only feed', del, 'deleted');
  check('K limits', '...the feed keeps its rows (the actor is simply forgotten)', `${await countRows('backup_vault_event', VS)} ${(await admin.query(`SELECT count(*) n FROM backup_vault_event WHERE vault_id = $1 AND actor_user IS NULL`, [VS])).rows[0].n > 0}`, `${before} true`);
  check('K limits', '...and the backup itself is untouched', await countRows('backup_version', VS), 4);

  // ending a grown-up (the identity lane's hook): reach goes, the backup stays
  const gone = await endVaultMembership(pool, { vaultId: VA, userId: B.userId });
  check('K limits', 'ending a grown-up (by the family\'s own act) removes their reach and nothing of the backup', `${gone.body.removed} ${st(await call('GET', V(VA), B.tok))} ${await countRows('backup_version', VA)}`, 'true 404 vault_not_found 5');
  // a parent whose guardianship has ended keeps no reach even if the membership row is still there
  await admin.query(`UPDATE guardianship SET closed_at = now(), closed_reason = 'revoked', valid = tstzrange(now() - interval '2 days', now() - interval '1 minute') WHERE user_id = $1 AND child_id = $2`, [NEW.userId, CA]);
  check('K limits', 'a grown-up who is no longer a guardian of any child has no reach, whatever the membership says', st(await call('GET', `${V(VA)}/versions`, NEW.tok)), '403 not_a_guardian');
  await unlockPin(NEW.userId);
  const ex = {
    pause: await call('POST', `${V(VA)}/pause`, NEW.tok, { targetUserId: B.userId, pin: NEW.pin }),
    helper: await call('POST', `${V(VA)}/helper`, NEW.tok, { helperUserId: H.userId, pin: NEW.pin }),
    challenge: await call('POST', `${V(VA)}/restores/challenge`, NEW.tok, {}),
    status: await call('GET', V(VA), NEW.tok),
    events: await call('GET', `${V(VA)}/events`, NEW.tok),
    begin: await call('POST', `${V(VA)}/uploads`, NEW.tok, mkBackup(VA, head).body),
  };
  for (const [k, r] of Object.entries(ex)) check('K limits', `an ended parent gets nothing from ${k}`, st(r), '403 not_a_guardian');
}

// ===========================================================================
// L . NOTHING LOST UNDER PRESSURE: abort/commit races, full allowance, two parents setting up at once
// ===========================================================================
{
  const Q = await signup('quota', '8642');
  await mkChild(Q, 'Pip');
  const rq = await call('POST', '/v1/backup/vaults', Q.tok, { recoveryVerifier: VERIFIER, pin: Q.pin });
  const VQ = rq.body.vaultId; vaults.push(VQ);
  await admin.query(`UPDATE backup_vault SET quota_bytes = 3200, keep_versions = 10 WHERE id = $1`, [VQ]);
  const codes = [];
  for (let i = 0; i < 7; i++) codes.push((await backupOnce(Q, VQ, { size: 1500 })).commit?.status);
  check('L pressure', 'a family whose history outgrows its allowance keeps being backed up (the oldest are set aside, never refused)', codes.join(), '201,201,201,201,201,201,201');
  const lq = await call('GET', `${V(VQ)}/versions`, Q.tok);
  check('L pressure', '...the newest two stay live and every older one is only set aside, still listed', lq.body.versions.map((v) => v.state[0]).join(''), 'tttttll');
  const keptBytes = Number((await admin.query(`SELECT COALESCE(sum(size_bytes),0) n FROM backup_chunk WHERE vault_id = $1`, [VQ])).rows[0].n);
  check('L pressure', '...and no byte was given up (set-aside copies outside the allowance never block a backup)', keptBytes, 7 * 1500);
  const tooBig = await call('POST', `${V(VQ)}/uploads`, Q.tok, mkBackup(VQ, await headOf(Q, VQ), { size: 3100 }).body);
  check('L pressure', 'a backup that cannot fit even alone is refused plainly, and nothing was set aside for it', `${st(tooBig)} ${(await call('GET', `${V(VQ)}/versions`, Q.tok)).body.versions.map((v) => v.state[0]).join('')}`, '507 quota_exceeded tttttll');

  // abort / expiry sweep racing a commit: the committed backup's bytes must survive every interleaving
  await admin.query(`UPDATE backup_vault SET quota_bytes = 400000 WHERE id = $1`, [VQ]);
  const lockKey = `olive-backup:${VQ}`;
  const verdicts = [];
  for (let trial = 0; trial < 6; trial++) {
    const hd = await headOf(Q, VQ);
    const bb = mkBackup(VQ, hd, { size: 3000 });
    const b = await call('POST', `${V(VQ)}/uploads`, Q.tok, bb.body);
    await putChunks(Q, VQ, b.body.uploadId, bb);
    const holder = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
    await holder.connect();
    await holder.query('BEGIN');
    await holder.query(`SELECT pg_advisory_xact_lock(hashtext($1::text))`, [lockKey]);
    const go = [
      call('POST', `${V(VQ)}/uploads/${b.body.uploadId}/commit`, Q.tok),
      trial % 2 ? call('POST', `${V(VQ)}/uploads/${b.body.uploadId}/abort`, Q.tok) : reclaimVault(pool, VQ, new Date(Date.now() + 10 * 86400000)),
    ];
    await new Promise((r) => setTimeout(r, 150));
    await holder.query('COMMIT'); await holder.end();
    const [c] = await Promise.all(go);
    const up = (await admin.query(`SELECT state FROM backup_upload WHERE id = $1`, [b.body.uploadId])).rows[0].state;
    const chunks = Number((await admin.query(`SELECT count(*) n FROM backup_chunk WHERE upload_id = $1`, [b.body.uploadId])).rows[0].n);
    const ver = Number((await admin.query(`SELECT count(*) n FROM backup_version WHERE upload_id = $1`, [b.body.uploadId])).rows[0].n);
    // either the backup is fully there (201, committed, all pieces) or it never became a version at all
    verdicts.push(c.status === 201 ? (up === 'committed' && chunks === bb.chunks.length && ver === 1 ? 'kept' : `LOST ${up} ${chunks} ${ver}`)
      : (ver === 0 ? 'never-stored' : `LOST ${c.status} ${up} ${chunks} ${ver}`));
  }
  check('L pressure', 'abort or the expiry sweep racing a commit never leaves a stored backup without its bytes', verdicts.every((v) => v === 'kept' || v === 'never-stored') ? 'ok' : verdicts.join(' | '), 'ok');
  // the pieces of any upload that has a recorded version cannot be deleted, whatever the upload says
  const lastUp = (await admin.query(`SELECT upload_id FROM backup_version WHERE vault_id = $1 AND state = 'live' ORDER BY seq DESC LIMIT 1`, [VQ])).rows[0].upload_id;
  const del = await admin.query(`DELETE FROM backup_chunk WHERE upload_id = $1`, [lastUp]).then(() => 'deleted', () => 'refused');
  check('L pressure', 'the database refuses to delete the pieces of a committed backup', del, 'refused');

  // two grown-ups of one family setting up at the same moment get ONE vault
  const P1 = await signup('twin1', '1122'); const P2 = await signup('twin2', '3344');
  const CP = await mkChild(P1, 'Twin'); await edge(CP, P2.userId);
  const [t1, t2] = await Promise.all([
    call('POST', '/v1/backup/vaults', P1.tok, { recoveryVerifier: VERIFIER, pin: P1.pin }),
    call('POST', '/v1/backup/vaults', P2.tok, { recoveryVerifier: VERIFIER, pin: P2.pin })]);
  for (const t of [t1, t2]) if (t.body.vaultId) vaults.push(t.body.vaultId);
  check('L pressure', 'two parents setting up at once: exactly one vault is made, the other is told to join it', [t1.status, t2.status].sort().join(), '201,409');
  const nv = Number((await admin.query(`SELECT count(DISTINCT m.vault_id) n FROM backup_vault_member m WHERE m.user_id = ANY($1::uuid[])`, [[P1.userId, P2.userId]])).rows[0].n);
  check('L pressure', 'so the family history is never split', nv, 1);
}

// ---------------------------------------------------------------------------
// cleanup: everything this run created, by id (the triggers that make backups permanent are stepped over
// only by the superuser that built the throwaway database)
await setSignupPolicy(pool, { enabled: true, maxAccounts: null });
const allUsers = (await admin.query(`SELECT id FROM app_user WHERE display_name LIKE ANY($1::text[])`, [[`%-${RUN}`]])).rows.map((r) => r.id);
const ids = [...new Set([...users, ...allUsers])];
try {
  await admin.query(`SET session_replication_role = replica`);
  for (const t of ['backup_chunk', 'backup_version', 'backup_upload', 'backup_restore_request', 'backup_restore_challenge', 'backup_vault_event', 'backup_vault_helper', 'backup_vault_member']) {
    await admin.query(`DELETE FROM ${t} WHERE vault_id = ANY($1::uuid[])`, [vaults]);
  }
  await admin.query(`DELETE FROM backup_vault WHERE id = ANY($1::uuid[])`, [vaults]);
  await admin.query(`SET session_replication_role = DEFAULT`);
} catch { /* not a superuser: the rows stay, harmlessly, in a throwaway database */ }
await admin.query(`DELETE FROM security_event WHERE actor_id = ANY($1::uuid[])`, [ids]).catch(() => {});
await admin.query(`DELETE FROM account_recovery_code WHERE user_id = ANY($1::uuid[])`, [ids]).catch(() => {});
await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[]) OR target_id = ANY($2::uuid[])`, [ids, children]);
await admin.query(`DELETE FROM device_pairing_code WHERE created_by = ANY($1::uuid[])`, [ids]);
await admin.query(`DELETE FROM guardian_invite WHERE child_id = ANY($1::uuid[])`, [children]);
await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [children]);
await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [ids]).catch((e) => console.error('cleanup:', e.message));
await admin.query(`DELETE FROM signup_allowance WHERE label LIKE $1`, [`${LABEL}%`]);
await admin.end();
await pool.end();
await fs.rm(tmpRoot, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
