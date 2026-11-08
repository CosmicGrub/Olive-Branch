/**
 * Migration 0037 (audit P-17): the foreign-key columns that had no index now
 * have one, the planner can actually use each, and nothing about row-level
 * security moved. Real Postgres.
 */
import pg from 'pg';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ADMIN = process.env.ADMIN_DATABASE_URL ?? process.env.DATABASE_URL;
if (!ADMIN) { console.error('ADMIN_DATABASE_URL (or DATABASE_URL) required'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const db = new pg.Client({ connectionString: ADMIN });
await db.connect();

const TARGETS = [
  ['guardianship', 'user_id'], ['call_log', 'child_id'], ['medication_dose', 'child_id'],
  ['media_artifact', 'author_id'], ['intent_batch', 'child_id'], ['export_record', 'child_id'],
  ['auth_challenge', 'issued_at'],
];

// ---- A · an index leads with each column --------------------------------------
for (const [table, col] of TARGETS) {
  const r = await db.query(
    `SELECT i.indexrelid::regclass::text AS idx
       FROM pg_index i
       JOIN pg_class t ON t.oid = i.indrelid
       JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = i.indkey[0]
      WHERE t.relname = $1 AND a.attname = $2 AND i.indisvalid AND i.indisready`, [table, col]);
  check('A indexes exist', `${table}.${col} is the leading column of a valid index`, r.rows.length >= 1, 'true');
}

// ---- B · the planner can use them (seqscan disabled so a tiny table cannot hide a missing index)
{
  await db.query('SET enable_seqscan = off');
  const plan = async (sql, params) => (await db.query(`EXPLAIN ${sql}`, params)).rows
    .map((r) => r['QUERY PLAN']).join('\n');
  const U = '00000000-0000-4000-8000-000000000000';
  const cases = [
    ['guardianship by user (edgesFor)', `SELECT * FROM guardianship WHERE user_id = $1`, 'guardianship_user_id_idx'],
    ['call_log by child', `SELECT * FROM call_log WHERE child_id = $1`, 'call_log_child_id_idx'],
    ['medication_dose by child', `SELECT * FROM medication_dose WHERE child_id = $1`, 'medication_dose_child_id_idx'],
    ['media_artifact by author', `SELECT * FROM media_artifact WHERE author_id = $1`, 'media_artifact_author_id_idx'],
    ['intent_batch by child', `SELECT * FROM intent_batch WHERE child_id = $1`, 'intent_batch_child_id_idx'],
    ['export_record by child', `SELECT * FROM export_record WHERE child_id = $1`, 'export_record_child_id_idx'],
  ];
  for (const [name, sql, idx] of cases) {
    check('B planner uses them', `${name} plans through ${idx}`, (await plan(sql, [U])).includes(idx), 'true');
  }
  check('B planner uses them', 'the challenge purge range scan uses auth_challenge_issued_at_idx',
    (await plan(`SELECT id FROM auth_challenge WHERE issued_at < now() - interval '2 hours'`)).includes('auth_challenge_issued_at_idx'), 'true');
  await db.query('RESET enable_seqscan');
}

// ---- C · RLS untouched ----------------------------------------------------------------
{
  const sql = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..',
    'db', 'migrations', '0037_fk_indexes.sql'), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  check('C RLS untouched', '0037 contains only CREATE INDEX statements (no policy, RLS, grant, revoke, alter or drop)',
    /\b(POLICY|ROW\s+LEVEL|GRANT|REVOKE|ALTER|DROP|DISABLE|NO\s+FORCE)\b/i.test(sql), false);
  check('C RLS untouched', '...and uses IF NOT EXISTS so a hand-patched database re-runs cleanly',
    (sql.match(/CREATE INDEX IF NOT EXISTS/g) ?? []).length, 7);
  const rls = await db.query(
    `SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class
      WHERE relname = ANY($1::text[]) AND relkind = 'r' ORDER BY relname`,
    [['guardianship', 'call_log', 'medication_dose', 'media_artifact', 'intent_batch', 'export_record', 'auth_challenge']]);
  // Whatever RLS state each table has, "enabled" must imply "forced" -- the
  // project's own invariant (health_check's rls_unforced) -- and the
  // tables this schema protects are still protected.
  check('C RLS untouched', 'every one of these tables that has RLS enabled still has it FORCED',
    rls.rows.filter((r) => r.relrowsecurity && !r.relforcerowsecurity).length, 0);
  check('C RLS untouched', 'auth_challenge, call_log, medication_dose and export_record are still RLS-protected',
    rls.rows.filter((r) => ['auth_challenge', 'call_log', 'medication_dose', 'export_record'].includes(r.relname)
      && r.relrowsecurity && r.relforcerowsecurity).length, 4);
  const hc = await db.query(`SELECT observed FROM health_check WHERE check_name = 'rls_unforced'`);
  check('C RLS untouched', 'health_check rls_unforced still reports 0', hc.rows[0]?.observed, 0);
}

await db.end();
let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
