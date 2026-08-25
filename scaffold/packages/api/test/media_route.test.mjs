/**
 * server/routes.mjs — POST /v1/children/:childId/media and
 * GET /v1/children/:childId/messages/:artifactId/media. MASTERFILE §20.2b:
 * "packages/storage/src/storage.ts's StoragePort has no production
 * implementation anywhere in this codebase (MemoryStorage is test-only) ...
 * receipt_screen.dart's real camera capture never uploads the recorded
 * bytes; media_artifact.storage_key is a locally-meaningful reference
 * only." This suite proves that gap closed end to end: real bytes, written
 * through the real HTTP route, land on a real (throwaway) filesystem via
 * FilesystemStorage, and read back byte-for-byte identical through the real
 * download route — not merely that the response bodies look plausible.
 *
 * Same DATABASE_URL/ADMIN_DATABASE_URL split as messages_route.test.mjs
 * (which this file's fixtures otherwise mirror) and the identical reason:
 * a route that writes real rows needs a real database under it, not a fake
 * `db` object. `registerRoutes()`'s third, injectable `storage` argument
 * (see that function's own doc comment) points FilesystemStorage at a real
 * `fs.mkdtemp()` temp directory for this run — mirroring
 * packages/storage/test/storage.test.mjs's own convention — rather than
 * this repo's real, persistent `MEDIA_STORAGE_ROOT`, so this suite never
 * touches or depends on real deployment data.
 */
import pg from 'pg';
import { promises as fs } from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';
import { Api } from '../src/api.mjs';
import { createPool, dbPort } from '../../db/src/pool.mjs';
import { registerRoutes } from '../../../server/routes.mjs';
import { issueSession } from '../../auth/src/auth.mjs';
import { FilesystemStorage } from '../../storage/src/storage.mjs';

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

// Randomly generated, not readable hex constants like other suites' fixture
// ids (e.g. messages_route.test.mjs's 'aaaaaaaa-...') -- every DB suite
// verify.sh runs shares ONE database, and a real, live collision was found
// during this pass between a hand-picked constant here and
// server/test/calls_route.test.mjs's own CHILD/DAD ids (both suites happened
// to pick the identical 'eeeeeeee.../ffffffff...' pattern). Sequential runs
// that each clean up after themselves tolerate that by luck; a crash before
// cleanup would not. randomUUID() removes the whole class of risk rather
// than trading one hand-picked collision for another.
const CHILD   = randomUUID();
const CHILD_B = randomUUID();
const DAD  = randomUUID();
const SITTER = randomUUID();
// A real guardian of CHILD_B ONLY -- exists so "does mediaArtifactFor()'s
// OWN double-scoping refuse a wrong child" can be tested with a caller who
// genuinely clears the OUTER api.ts `action: 'message'` gate for CHILD_B
// (a real edge exists) and would therefore reach the handler at all --
// proving the boundary that actually matters, not the outer gate a
// no-edge-at-all caller would already be stopped by.
const MOM = randomUUID();

await admin.query('BEGIN');
for (const cid of [CHILD, CHILD_B]) {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM media_artifact WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
}
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2, $3)`, [DAD, SITTER, MOM]);
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Dad','America/Chicago'), ($2,'Sitter','America/Chicago'),
     ($3,'Mom','America/Chicago')`, [DAD, SITTER, MOM]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Ivy','2016-04-02','America/New_York'),
     ($2,'Wren','2016-04-02','America/New_York')`, [CHILD, CHILD_B]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'sitter',   '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $5, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, DAD, SITTER, CHILD_B, MOM]);
await admin.query(
  `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week,
                        reachable, effective)
   VALUES ($1,'bedtime','20:30','21:00','{0,1,2,3,4,5,6}', true, '[2020-01-01,2099-01-01)'),
          ($2,'bedtime','20:30','21:00','{0,1,2,3,4,5,6}', true, '[2020-01-01,2099-01-01)')`,
  [CHILD, CHILD_B]);
await admin.query('COMMIT');

// A real, throwaway temp directory -- real disk I/O, never this repo's own
// persistent MEDIA_STORAGE_ROOT. Cleaned up at the end of this file.
const storageRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-media-route-test-'));
const storage = new FilesystemStorage(storageRoot);

const SECRET = Buffer.from('b'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool));
registerRoutes(api, pool, storage);

const dadTok = issueSession(SECRET,
  { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const momTok = issueSession(SECRET,
  { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);
const sitterTok = issueSession(SECRET,
  { userId: SITTER, roleName: 'sitter', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET,
  { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);

const post = (p, tok, body) => api.handle('POST', p,
  tok ? { authorization: `Bearer ${tok}` } : {}, JSON.stringify(body));
const get = (p, tok) => api.handle('GET', p,
  tok ? { authorization: `Bearer ${tok}` } : {}, '');

// A real "recorded video" -- not text pretending to be bytes: every byte
// value 0-255 once, so a base64/UTF-8 mangling bug anywhere in the pipeline
// (server or storage) would show up as a real mismatch, not pass by luck.
const REAL_BYTES = Buffer.from(Array.from({ length: 256 }, (_, i) => i));
const b64 = REAL_BYTES.toString('base64');

// ===========================================================================
// A · the real roundtrip — upload real bytes, land on real disk, read back
//     byte-for-byte identical through the real download route
// ===========================================================================
let uploadedKey;
{
  const up = await post(`/v1/children/${CHILD}/media`, dadTok, { bytes: b64 });
  check('A roundtrip', 'a valid guardian upload returns 201', up.status, 201);
  check('A roundtrip', 'response names a real, non-empty storageKey',
    typeof up.body.storageKey === 'string' && up.body.storageKey.length > 0, 'true');
  check('A roundtrip', 'response carries a real md5 etag, not a placeholder',
    /^[0-9a-f]{32}$/.test(up.body.etag), 'true');
  uploadedKey = up.body.storageKey;

  // Proven by reading the REAL file directly off disk -- not by trusting
  // the HTTP response alone. This is the exact discipline
  // storage.test.mjs's own "P filesystem" group already applies to
  // FilesystemStorage in isolation; here it is proven through the real
  // HTTP route on top of it.
  const onDisk = await fs.readFile(path.join(storageRoot, uploadedKey));
  check('A roundtrip', 'the real bytes genuinely landed on the real filesystem, '
    + 'byte-for-byte', onDisk.equals(REAL_BYTES), 'true');

  const send = await post(`/v1/children/${CHILD}/messages`, dadTok,
    { storageKey: uploadedKey, durationMs: 4200 });
  check('A roundtrip', 'sendMessage with the REAL uploaded key returns 201', send.status, 201);
  const artifactId = send.body.artifactId;

  const art = await admin.query(
    `SELECT storage_key FROM media_artifact WHERE id = $1`, [artifactId]);
  check('A roundtrip', 'media_artifact.storage_key is the REAL key FilesystemStorage '
    + 'returned, not a placeholder', art.rows[0]?.storage_key, uploadedKey);

  const dl = await get(`/v1/children/${CHILD}/messages/${artifactId}/media`, dadTok);
  check('A roundtrip', 'a valid, authorized download returns 200', dl.status, 200);
  check('A roundtrip', 'the download names the real artifact kind', dl.body.kind, 'video_msg');
  const roundtripped = Buffer.from(dl.body.bytes, 'base64');
  check('A roundtrip', 'the bytes read back through the real HTTP route are '
    + 'IDENTICAL, byte-for-byte, to what was originally uploaded — the real '
    + 'write-then-retrieve roundtrip this pass was built to prove',
    roundtripped.equals(REAL_BYTES), 'true');

  // The SAME storageKey a second guardian download reads back the exact
  // same way -- proving this isn't consumed/one-shot.
  const dl2 = await get(`/v1/children/${CHILD}/messages/${artifactId}/media`, dadTok);
  check('A roundtrip', 'a second read of the same artifact still returns the '
    + 'same real bytes', Buffer.from(dl2.body.bytes, 'base64').equals(REAL_BYTES), 'true');
}

// ===========================================================================
// B · upload validation — never writes a blob for a malformed request
// ===========================================================================
{
  const listBefore = await storage.list('children/');
  const empty = await post(`/v1/children/${CHILD}/media`, dadTok, { bytes: '' });
  check('B validation', 'an empty bytes field is refused', empty.status, 400);
  check('B validation', 'reason is bytes_required', empty.body.error, 'bytes_required');

  const missing = await post(`/v1/children/${CHILD}/media`, dadTok, {});
  check('B validation', 'a missing bytes field is refused', missing.status, 400);
  check('B validation', 'reason is bytes_required (missing)', missing.body.error, 'bytes_required');

  const listAfter = await storage.list('children/');
  check('B validation', 'no new blob was written for either malformed request',
    listAfter.length, listBefore.length);
}

// ===========================================================================
// C · authorization on UPLOAD — the same `action: 'message'` gate the
//     existing POST .../messages route already runs, not a separate check
// ===========================================================================
{
  const sitterUp = await post(`/v1/children/${CHILD}/media`, sitterTok, { bytes: b64 });
  check('C upload auth', 'a sitter (no message capability) cannot upload', sitterUp.status, 403);

  const noEdgeUp = await post(`/v1/children/${CHILD_B}/media`, dadTok, { bytes: b64 });
  check('C upload auth', 'a guardian with no edge to this child cannot upload',
    noEdgeUp.status, 403);

  const childUp = await post(`/v1/children/${CHILD}/media`, childTok, { bytes: b64 });
  check('C upload auth', 'the child herself CAN upload her own capture', childUp.status, 201);
}

// ===========================================================================
// D · authorization + real authorization BOUNDARY on DOWNLOAD — mirrors C,
//     plus the cross-child leak this pass was specifically asked to close
//     (mediaArtifactFor()'s own child_id + id double-scoping, pool.ts)
// ===========================================================================
{
  // A real artifact that genuinely belongs to CHILD.
  const up = await post(`/v1/children/${CHILD}/media`, dadTok, { bytes: b64 });
  const send = await post(`/v1/children/${CHILD}/messages`, dadTok,
    { storageKey: up.body.storageKey, durationMs: 1000 });
  const realArtifactId = send.body.artifactId;

  const sitterDl = await get(`/v1/children/${CHILD}/messages/${realArtifactId}/media`, sitterTok);
  check('D download auth', 'a sitter cannot download', sitterDl.status, 403);

  // MOM has a REAL edge -- but to CHILD_B, not CHILD. She clears the outer
  // api.ts `action: 'message'` gate for CHILD_B and reaches the handler,
  // which must then refuse via mediaArtifactFor()'s own scoping, not the
  // outer gate (that is the whole point of this case).
  const crossChild = await get(`/v1/children/${CHILD_B}/messages/${realArtifactId}/media`, momTok);
  check('D download auth', "a real artifact belonging to a DIFFERENT child than the "
    + "one named in the path is refused -- never served under the wrong child's scope",
    crossChild.status, 404);
  check('D download auth', 'the reason is artifact_not_found, not a leak of the real '
    + 'kind/bytes', crossChild.body.error, 'artifact_not_found');

  const wrongId = await get(`/v1/children/${CHILD}/messages/${randomUUID()}/media`, dadTok);
  check('D download auth', 'a real but nonexistent artifact id is a real 404',
    wrongId.status, 404);
  check('D download auth', 'reason is artifact_not_found', wrongId.body.error,
    'artifact_not_found');
}

// ===========================================================================
// E · a row that outlived its blob -- honest 404, not a 500 or a fabricated
//     empty success (the reaper's own "blob before row" case, from the read
//     side: packages/storage/src/storage.ts's reap() and its own dedicated
//     coverage in packages/api/test/stack.test.mjs are UNTOUCHED by this
//     pass -- this only proves the DOWNLOAD route's own honest response to
//     that same real-world shape)
// ===========================================================================
{
  const up = await post(`/v1/children/${CHILD}/media`, dadTok, { bytes: b64 });
  const send = await post(`/v1/children/${CHILD}/messages`, dadTok,
    { storageKey: up.body.storageKey, durationMs: 1000 });
  const artifactId = send.body.artifactId;

  // Simulate the blob having been removed out from under a still-real row
  // (a tombstoned reap, or any other real-world loss) by deleting it
  // directly off the real filesystem -- not through this route.
  await storage.delete(up.body.storageKey);

  const dl = await get(`/v1/children/${CHILD}/messages/${artifactId}/media`, dadTok);
  check('E orphaned row', 'a row whose real blob is gone is an honest 404, '
    + 'never a 500 or an empty-but-200 body', dl.status, 404);
  check('E orphaned row', 'reason is media_not_found, distinct from '
    + 'artifact_not_found', dl.body.error, 'media_not_found');
}

for (const cid of [CHILD, CHILD_B]) {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM media_artifact WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
}
await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2, $3)`, [DAD, SITTER, MOM]);
await admin.end();
await pool.end();
await fs.rm(storageRoot, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
