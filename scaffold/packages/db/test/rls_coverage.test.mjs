/**
 * packages/db/test/rls_coverage.test.mjs — the automated backstop for a real,
 * recurring failure mode: `health_check`'s `rls_unforced` sub-check used to be a
 * hand-maintained `c.relname IN (...)` list that fell behind THREE times
 * (medication/medical_record 0026, the exchange tables 0027, ...) and never
 * named the core tables from 0001 at all, so a new table with no policy was
 * never flagged.
 *
 * Since migration 0044 (data-model audit S-D21) the view reads the CATALOG:
 * any ordinary table in the public schema that does not ENABLE and FORCE
 * row-level security is a critical breach unless it is named, with a reason,
 * in `rls_allow_list`. This suite proves that mechanism rather than a list:
 *
 *   A. the catalog and the allow-list agree: every table without RLS is
 *      allow-listed (no blind spot), and every allow-list entry names a table
 *      that exists and really lacks RLS (the list cannot rot — whoever adds RLS
 *      to a table must delete its row).
 *   B. every RLS-enabled table also has RLS FORCED (the table owner bypasses a
 *      non-forced policy outright, db/DEPLOYMENT.md point #1).
 *   C. the view really flags a NEW public table with no RLS, stops flagging it
 *      once it is allow-listed, and stops again once it has FORCEd RLS — the
 *      behaviour the old list could not have.
 *   D. the view no longer carries a hard-coded table list.
 *
 * Needs ADMIN_DATABASE_URL (falls back to DATABASE_URL) to create a scratch
 * table for section C.
 */
import pg from 'pg';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const client = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await client.connect();

const { rows: tables } = await client.query(`
  SELECT c.relname, c.relrowsecurity AS enabled, c.relforcerowsecurity AS forced
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') ORDER BY c.relname`);
const { rows: allow } = await client.query(`SELECT table_name, reason FROM rls_allow_list ORDER BY table_name`);
const allowed = new Set(allow.map(a => a.table_name));
const byName = new Map(tables.map(t => [t.relname, t]));

check('A catalog vs allow-list', 'the catalog returned real tables (a suspiciously empty result means the wrong database)',
  tables.length > 30, true);
check('A catalog vs allow-list', 'a good number of tables DO enforce RLS (so the check is not vacuous)',
  tables.filter(t => t.enabled && t.forced).length > 20, true);

const blindSpots = tables.filter(t => !(t.enabled && t.forced) && !allowed.has(t.relname)).map(t => t.relname);
check('A catalog vs allow-list', 'every table without ENABLE+FORCE RLS is on the allow-list (no blind spot)',
  blindSpots.length ? `not allow-listed: ${blindSpots.join(', ')}` : 'none', 'none');

const stale = allow.filter(a => !byName.has(a.table_name) || (byName.get(a.table_name).enabled && byName.get(a.table_name).forced))
  .map(a => a.table_name);
check('A catalog vs allow-list', 'every allow-list entry names a table that exists and genuinely lacks RLS (delete the row when you add RLS)',
  stale.length ? `stale: ${stale.join(', ')}` : 'none', 'none');
check('A catalog vs allow-list', 'every allow-list entry carries a reason',
  allow.every(a => a.reason && a.reason.trim().length > 10), true);
check('A catalog vs allow-list', 'the sensitive tables are NOT quietly allow-listed (message_log, expense, medication_dose, expiry_digest)',
  ['message_log', 'expense', 'medication_dose', 'expiry_digest', 'delivery_intent', 'media_artifact'].some(t => allowed.has(t)), false);

const enabledNotForced = tables.filter(t => t.enabled && !t.forced).map(t => t.relname);
check('B forced too', 'every RLS-enabled table also has RLS FORCED, not merely enabled',
  enabledNotForced.length ? `enabled-not-forced: ${enabledNotForced.join(', ')}` : 'none', 'none');

const observed = async () => Number((await client.query(
  `SELECT observed FROM health_check WHERE check_name = 'rls_unforced'`)).rows[0].observed);
check('C the view reads the catalog', 'health_check.rls_unforced is clean on the migrated schema', await observed(), 0);

await client.query('DROP TABLE IF EXISTS rls_probe_table');
await client.query('CREATE TABLE rls_probe_table (id int)');
try {
  check('C the view reads the catalog', 'a brand-new public table with no RLS is flagged immediately', await observed(), 1);
  await client.query(`INSERT INTO rls_allow_list (table_name, reason) VALUES ('rls_probe_table', 'scratch table for the coverage test')`);
  check('C the view reads the catalog', 'allow-listing it (with a reason) silences exactly that table', await observed(), 0);
  await client.query(`DELETE FROM rls_allow_list WHERE table_name = 'rls_probe_table'`);
  check('C the view reads the catalog', 'removing the entry flags it again', await observed(), 1);
  await client.query('ALTER TABLE rls_probe_table ENABLE ROW LEVEL SECURITY');
  check('C the view reads the catalog', 'ENABLE without FORCE is still a breach', await observed(), 1);
  await client.query('ALTER TABLE rls_probe_table FORCE ROW LEVEL SECURITY');
  check('C the view reads the catalog', 'ENABLE + FORCE clears it with no list to update', await observed(), 0);
} finally {
  await client.query(`DELETE FROM rls_allow_list WHERE table_name = 'rls_probe_table'`);
  await client.query('DROP TABLE IF EXISTS rls_probe_table');
}
check('C the view reads the catalog', 'and the view is clean again after the scratch table is gone', await observed(), 0);

// 0047: health_check is a thin view over health_counts(); the checks (and so the catalog read) live in the function.
const { rows: viewRows } = await client.query(`SELECT pg_get_viewdef('health_check'::regclass, true) AS v, pg_get_functiondef('health_counts'::regproc) AS def`);
const def = viewRows[0].def;
check('D no hard-coded list', 'health_check reads through health_counts()', /health_counts\(\)/.test(viewRows[0].v), true);
check('D no hard-coded list', "the view no longer carries a 'relname IN (...)' table list",
  /relname\s+IN\s*\(|relname\s*=\s*ANY\s*\(\s*ARRAY/i.test(def), false);
check('D no hard-coded list', 'it consults rls_allow_list', /rls_allow_list/.test(def), true);

// ---------------------------------------------------------------------------
// F · S-B4 -- the allow-list direction. D/E above only look at tables that
// ALREADY have RLS. This asks the opposite question of every public base table:
// does it have ENABLE + FORCE row level security? A table that does not must be
// named below WITH A REASON, so "forgot to add RLS to the new table" fails in CI
// on the PR that adds it instead of surviving until an audit.
//
// Every entry here is a known, disclosed gap or a table with no tenant data, not
// an endorsement: the child-keyed ones (child_tz_interval, day_part,
// contact_ladder, sibling_link, child_ping) are follow-up work for the next
// isolation pass (the sensitive tables were done in migration 0040).
const NO_RLS_ALLOWED = {
  schema_migration: 'migration-runner bookkeeping; no tenant data',
  rls_allow_list: 'the catalog-driven health check\'s own configuration table (migration 0044); no tenant data',
  reap_tombstone: 'retention-reaper bookkeeping (storage keys + errors); system-only access, no UI path',
  household: 'dead schema: no query call site anywhere in the app (see the header above)',
  succession_directive: 'dead schema: no query call site anywhere in the app',
  child_ping: 'dead schema: no query call site anywhere in the app',
  sibling_link: 'child-keyed, read by the system role only today; edge policy is follow-up',
  contact_ladder: 'child-keyed via guardianship; read through effective_guardianship; edge policy is follow-up',
  child_tz_interval: 'child-keyed scheduling data; read/written by system sessions; edge policy is follow-up',
  day_part: 'child-keyed scheduling data; read/written by system sessions; edge policy is follow-up',
};
const { rows: allTables } = await client.query(`
  SELECT c.relname, c.relrowsecurity AS enabled, c.relforcerowsecurity AS forced
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY c.relname`);
const unprotected = allTables.filter(t => !(t.enabled && t.forced)).map(t => t.relname);
const undeclared = unprotected.filter(t => !(t in NO_RLS_ALLOWED));
check('F coverage', 'every public table has ENABLE+FORCE RLS or is allow-listed with a reason',
  undeclared.length ? `no RLS and not allow-listed: ${undeclared.join(', ')}` : 'none', 'none');
const staleAllow = Object.keys(NO_RLS_ALLOWED).filter(
  t => !allTables.some(x => x.relname === t) || !unprotected.includes(t));
check('F coverage', 'the allow-list has no stale entries (a table that gained RLS or was dropped must leave it)',
  staleAllow.length ? `stale: ${staleAllow.join(', ')}` : 'none', 'none');
check('F coverage', 'every allow-list entry carries a reason',
  Object.values(NO_RLS_ALLOWED).every(r => typeof r === 'string' && r.length > 10), 'true');
for (const t of ['child', 'guardianship', 'app_user', 'message_log', 'security_event', 'media_upload',
                 'expense', 'medication', 'medication_dose', 'medical_record', 'export_record',
                 'exchange_bag_item', 'exchange_running_late_log', 'exchange_arrival_event',
                 'care_note', 'custody_order']) {
  const row = allTables.find(x => x.relname === t);
  check('F coverage', `${t} is ENABLE+FORCE row level security`,
    row ? `${row.enabled}/${row.forced}` : 'missing', 'true/true');
}
// The backup role must keep working past FORCE RLS (migration 0022): BYPASSRLS.
const { rows: br } = await client.query(`SELECT rolbypassrls FROM pg_roles WHERE rolname = 'backup_reader'`);
check('F coverage', 'backup_reader still BYPASSRLS (backups keep working under the new policies)',
  br[0]?.rolbypassrls, 'true');

await client.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
