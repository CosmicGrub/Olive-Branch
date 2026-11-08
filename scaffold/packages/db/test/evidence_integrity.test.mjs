/**
 * packages/db/test/evidence_integrity.test.mjs — migration 0043, against a REAL
 * Postgres. Data-model audit S-D15 (the DB checked the SHAPE of the message_log
 * chain, never its contents) and the "fail loudly" requirement on migrating
 * existing evidence.
 *
 *   A. The SQL hash is the engine's hash. Rows written by the real writer
 *      (appendHandoverNote -> packages/ledger entryHash) are accepted by the
 *      trigger that now RECOMPUTES the hash with pgcrypto — for ASCII, accents,
 *      CJK, newlines, a long body and EMOJI (the framing prefix is the UTF-16
 *      length, which differs from Postgres' own length() for astral characters).
 *   B. A linked-but-FORGED row (right link and seq, wrong hash; or a changed
 *      body under the old hash) is refused. hash_version is constrained.
 *      TRUNCATE is refused. The whole chain still verifies with the engine's
 *      verifyChain.
 *   C. The migration itself: against a scratch database migrated to 0042 with
 *      (i) a good chain and some expenses and (ii) a tampered chain. 0043 must
 *      REFUSE the tampered one (non-zero exit, naming child and seq), and apply
 *      to the good one, backfilling expense_event.
 *
 * Needs ADMIN_DATABASE_URL (a superuser: it creates a scratch database) and
 * DATABASE_URL (the NOSUPERUSER app role).
 */
import pg from 'pg';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, copyFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPool, appendHandoverNote } from '../src/pool.mjs';
import { entryHash, verifyChain, GENESIS } from '../../ledger/src/ledger.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SCAFFOLD = fileURLToPath(new URL('../../../', import.meta.url));
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();
const pool = createPool(DATABASE_URL);

const DAD = '5e5e5e5e-0043-4043-9043-0000000000a1';
const CHILD = '5e5e5e5e-0043-4043-9043-0000000000c1';

async function cleanup() {
  await admin.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete');
  try { await admin.query('DELETE FROM message_log WHERE child_id = $1', [CHILD]); }
  finally { await admin.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete'); }
  await admin.query('DELETE FROM guardianship WHERE child_id = $1', [CHILD]);
  await admin.query('DELETE FROM child WHERE id = $1', [CHILD]);
  await admin.query('DELETE FROM app_user WHERE id = $1', [DAD]);
}
await cleanup();
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad43','America/New_York')`, [DAD]);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'C43','2016-04-02','America/New_York')`, [CHILD]);
// Edge-based RLS (migration 0040): the writer must hold a live edge to the child.
await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1,$2,'guardian','{}', tstzrange(now() - interval '1 year', null))`, [CHILD, DAD]);

// ------------------------------------------------ A. SQL hash == engine hash --
{
  const g = 'A the SQL hash is the engine hash';
  const bodies = ['plain ascii', 'café déjà vu — “quotes”', '日本語のメッセージ', 'line one\nline two\r\nline three',
    'emoji 😀 and 👨‍👩‍👧 family, math 𝔸𝔹', 'x'.repeat(20000), '', ' ', '0:1:2:fake:frame', 'a\ttab'];
  let accepted = 0, err = null;
  for (const b of bodies) {
    try { await appendHandoverNote(pool, 'guardian', DAD, CHILD, b); accepted++; }
    catch (e) { err = e.message; break; }
  }
  check(g, 'every body — including astral-plane emoji — is accepted by the recomputing trigger', `${accepted}${err ? ' ' + err : ''}`, String(bodies.length));
  const chain = (await admin.query(
    `SELECT seq, child_id, author_id, to_char(at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS at, body, prev_hash, hash, hash_version
       FROM message_log WHERE child_id = $1 ORDER BY seq`, [CHILD])).rows
    .map(r => ({ seq: Number(r.seq), childId: r.child_id, authorId: r.author_id, at: r.at, body: r.body, prevHash: r.prev_hash, hash: r.hash, v: r.hash_version }));
  check(g, 'the stored chain verifies with the engine verifyChain (independent of the trigger)', verifyChain(chain).ok, true);
  check(g, 'every row has hash_version 1', chain.every(c => c.v === 1), true);
  check(g, 'the SQL function agrees with entryHash() row for row',
    (await Promise.all(chain.map(async c => (await admin.query(
      `SELECT message_log_hash_v1($1::bigint,$2::uuid,$3::uuid,$4::timestamptz,$5,$6) AS h`,
      [c.seq, c.childId, c.authorId, c.at, c.body, c.prevHash])).rows[0].h === entryHash(c)))).every(Boolean), true);
  for (const s of ['abc', 'é', '日本', '😀', 'a😀b', '𝔸𝔹𝔺', '']) {
    check(g, `olive_utf16_length(${JSON.stringify(s)}) equals JavaScript's .length`,
      (await admin.query('SELECT olive_utf16_length($1) AS n', [s])).rows[0].n, s.length);
  }
}

// ------------------------------------------------------------ B. forgeries ---
{
  const g = 'B forged rows are refused';
  const tip = (await admin.query(`SELECT seq, hash FROM message_log WHERE child_id = $1 ORDER BY seq DESC LIMIT 1`, [CHILD])).rows[0];
  const ins = async (seq, prev, hash, body, version = 1) => {
    await admin.query('SAVEPOINT f');
    try {
      await admin.query(
        `INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash, hash_version)
         VALUES ($1,$2,$3,'2026-01-01T00:00:00.000Z',$4,$5,$6,$7)`, [CHILD, seq, DAD, body, prev, hash, version]);
      await admin.query('RELEASE SAVEPOINT f'); return null;
    } catch (e) { await admin.query('ROLLBACK TO SAVEPOINT f'); return e.message; }
  };
  await admin.query('BEGIN');
  const nextSeq = Number(tip.seq) + 1;
  check(g, 'linked, contiguous, well-formed hex — but a hash that is NOT this row’s hash — is refused',
    (await ins(nextSeq, tip.hash, 'f'.repeat(64), 'forged'))?.includes('does not match its content'), true);
  const honest = entryHash({ seq: nextSeq, childId: CHILD, authorId: DAD, at: '2026-01-01T00:00:00.000Z', body: 'honest', prevHash: tip.hash });
  check(g, 'a body changed under an honest hash is refused',
    (await ins(nextSeq, tip.hash, honest, 'honest but edited'))?.includes('does not match its content'), true);
  check(g, 'the honestly hashed row is accepted', await ins(nextSeq, tip.hash, honest, 'honest'), null);
  check(g, 'an unknown hash_version is refused by CHECK',
    (await ins(nextSeq + 1, honest, 'a'.repeat(64), 'x', 2))?.includes('message_log_hash_version_known'), true);
  await admin.query('ROLLBACK');

  await admin.query('BEGIN');
  let truncateErr = null;
  try { await admin.query('TRUNCATE message_log'); } catch (e) { truncateErr = e.message; }
  await admin.query('ROLLBACK');
  check(g, 'TRUNCATE is refused like UPDATE and DELETE', truncateErr?.includes('append-only'), true);
  check(g, 'the chain is intact afterwards',
    Number((await admin.query(`SELECT count(*) AS n FROM message_log WHERE child_id = $1`, [CHILD])).rows[0].n) >= 10, true);
}

await cleanup();

// ----------------------------------------------- C. the migration, loudly ----
{
  const g = 'C 0043 verifies existing evidence before touching it';
  const url = new URL(ADMIN_DATABASE_URL);
  const scratch = `olive_mig0043_${process.pid}`;
  const asDb = (db) => { const u = new URL(url); u.pathname = '/' + db; return u.toString(); };
  const maint = new pg.Client({ connectionString: asDb('postgres') });
  await maint.connect();
  await maint.query(`DROP DATABASE IF EXISTS ${scratch}`);
  await maint.query(`CREATE DATABASE ${scratch}`);
  const dir = mkdtempSync(join(tmpdir(), 'olive-mig-'));
  const all = readdirSync(join(SCAFFOLD, 'db', 'migrations')).filter(f => f.endsWith('.sql')).sort();
  for (const f of all.filter(f => f < '0043')) copyFileSync(join(SCAFFOLD, 'db', 'migrations', f), join(dir, f));
  const migrate = () => spawnSync(process.execPath, [join(SCAFFOLD, 'tools', 'migrate.mjs')],
    { env: { ...process.env, DATABASE_URL: asDb(scratch), MIGRATIONS_DIR: dir, PSQL_CMD: '' }, encoding: 'utf8' });
  try {
    const r1 = migrate();
    check(g, 'a scratch database migrates cleanly to 0042', r1.status, 0);
    const db = new pg.Client({ connectionString: asDb(scratch) });
    await db.connect();
    const P1 = '5e5e5e5e-0043-4043-9043-0000000000b1', P2 = '5e5e5e5e-0043-4043-9043-0000000000b2';
    const C1 = '5e5e5e5e-0043-4043-9043-0000000000d1', C2 = '5e5e5e5e-0043-4043-9043-0000000000d2';
    await db.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'P1','UTC'),($2,'P2','UTC')`, [P1, P2]);
    await db.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES ($1,'A','2016-01-01','UTC'),($2,'B','2016-01-01','UTC')`, [C1, C2]);
    const mkChain = async (child, n, tamper = false) => {
      let prev = GENESIS;
      for (let i = 0; i < n; i++) {
        const e = { seq: i, childId: child, authorId: P1, at: `2026-02-0${i + 1}T10:00:00.000Z`, body: `entry ${i} 😀`, prevHash: prev };
        const hash = entryHash(e);
        await db.query(`INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
          [child, i, P1, e.at, e.body, prev, hash]);
        prev = hash;
      }
      if (tamper) {
        await db.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_update');
        await db.query(`UPDATE message_log SET body = 'quietly edited' WHERE child_id = $1 AND seq = 1`, [child]);
        await db.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_update');
      }
    };
    await mkChain(C1, 3);
    await mkChain(C2, 3, true);
    // two expenses with different histories
    await db.query(`INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule, status, description)
                    VALUES ($1,$2,500,'other','2026-02-01','{"payerSharePercent":50}','proposed','a'),
                           ($1,$2,700,'other','2026-02-02','{"payerSharePercent":50}','accepted','b')`, [C1, P1]);

    copyFileSync(join(SCAFFOLD, 'db', 'migrations', all.find(f => f.startsWith('0043'))), join(dir, all.find(f => f.startsWith('0043'))));
    const refused = migrate();
    const out = (refused.stdout ?? '') + (refused.stderr ?? '');
    check(g, 'a tampered existing chain makes the migration FAIL (non-zero exit)', refused.status === 0, false);
    check(g, 'the failure says why', out.includes('0043 REFUSED'), true);
    check(g, 'it names the child and the sequence number', out.includes(C2) && /seq 1/.test(out), true);
    check(g, 'it does not complain about the good chain', out.includes(C1), false);
    check(g, 'nothing was applied (no hash_version column, no expense_event table)',
      (await db.query(`SELECT count(*)::int AS n FROM information_schema.columns WHERE table_name = 'message_log' AND column_name = 'hash_version'`)).rows[0].n +
      (await db.query(`SELECT count(*)::int AS n FROM information_schema.tables WHERE table_name = 'expense_event'`)).rows[0].n, 0);

    // repair the evidence the only honest way available here: remove the tampered chain
    await db.query('ALTER TABLE message_log DISABLE TRIGGER message_log_no_delete');
    await db.query('DELETE FROM message_log WHERE child_id = $1', [C2]);
    await db.query('ALTER TABLE message_log ENABLE TRIGGER message_log_no_delete');
    const ok = migrate();
    check(g, 'with only verifying chains the same migration applies', ok.status, 0);
    check(g, 'existing chains are marked hash_version 1',
      (await db.query(`SELECT DISTINCT hash_version FROM message_log`)).rows.map(r => r.hash_version).join(','), '1');
    const ev = (await db.query(`SELECT e.seq, e.from_status, e.to_status, e.actor_id, e.backfilled, x.status
        FROM expense_event e JOIN expense x ON x.id = e.expense_id ORDER BY x.amount_cents, e.seq`)).rows;
    check(g, 'a proposed expense got one event: null -> proposed, actor = who paid, not backfilled',
      JSON.stringify(ev.filter(e => e.status === 'proposed').map(e => [e.seq, e.from_status, e.to_status, e.actor_id, e.backfilled])),
      JSON.stringify([[1, null, 'proposed', P1, false]]));
    check(g, 'an already-accepted expense got proposed + a BACKFILLED accepted event with an unknown actor',
      JSON.stringify(ev.filter(e => e.status === 'accepted').map(e => [e.seq, e.to_status, e.actor_id, e.backfilled])),
      JSON.stringify([[1, 'proposed', P1, false], [2, 'accepted', null, true]]));
    const again = migrate();
    check(g, 're-running is a no-op', again.status, 0);
    await db.end();
  } finally {
    rmSync(dir, { recursive: true, force: true });
    await maint.query(`DROP DATABASE IF EXISTS ${scratch} WITH (FORCE)`);
    await maint.end();
  }
}

await admin.end();
await pool.end();

let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
