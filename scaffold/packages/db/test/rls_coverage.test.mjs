/**
 * packages/db/test/rls_coverage.test.mjs — the automated backstop for a real,
 * recurring failure mode: `health_check`'s own `rls_unforced` sub-check
 * (db/migrations/0028_care_note_letter.sql) is a hand-maintained
 * `c.relname IN (...)` list, and that list has silently fallen behind THREE
 * times so far, per 0028's own header — medication/medical_record (0026) and
 * exchange_bag_item/exchange_running_late_log/exchange_arrival_event (0027)
 * both shipped with real `ENABLE`+`FORCE ROW LEVEL SECURITY` and were never
 * added to the monitor's list, so the health-check that exists specifically
 * to catch "a table lost its RLS" had a blind spot for every one of them
 * from the day they shipped until 0028 finally caught up.
 *
 * This test closes that at the SOURCE rather than waiting for the next
 * migration author to remember: it derives the real, current set of
 * RLS-enabled tables directly from `pg_class` (the same catalog
 * `health_check`'s own SQL already reads), and asserts the view's list
 * covers every one of them. Add a table, run `ALTER TABLE x ENABLE ROW
 * LEVEL SECURITY`, forget to touch the view — this test fails, in CI, on
 * that PR, instead of waiting for the fourth accidental discovery.
 *
 * Deliberately scoped to tables someone ALREADY decided need RLS (i.e.
 * `relrowsecurity = true`), not "every table in the schema" — several
 * tables from 0001_phase0_init.sql (household, sibling_link,
 * succession_directive, child_ping, webauthn_challenge — the last
 * explicitly superseded by auth_challenge, per pool.ts's own comment) have
 * no real query call site anywhere in the app at all today and no RLS
 * either; whether they need RLS, or are dead schema that should be
 * dropped, is a real, separate architectural question this test does not
 * decide unilaterally. What it DOES guarantee: a table that has real RLS
 * enabled is never silently missing from the one view that watches for RLS
 * regressing.
 */
import pg from 'pg';

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const client = new pg.Client({ connectionString: DATABASE_URL });
await client.connect();

// The real, current set of RLS-enabled tables — independent of anything
// health_check's own view text claims, read straight from the catalog.
const { rows: rlsTables } = await client.query(`
  SELECT c.relname,
         c.relrowsecurity  AS enabled,
         c.relforcerowsecurity AS forced
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = true
   ORDER BY c.relname`);

check('A coverage', 'at least one real RLS-enabled table exists to check against '
  + '(a suspiciously-empty result usually means the wrong database/role)',
  rlsTables.length > 0, true);

// The view's own SQL text — parsed for its rls_unforced sub-check's
// `c.relname IN (...)` list, the exact same way a human reviewing a diff
// would read it. Regex against the view definition itself (not a copy of
// the list retyped here) so this test can never silently drift from what
// the view actually checks — if the view's own SQL shape changes enough
// to break this regex, THAT failure is itself the signal to look.
const { rows: viewRows } = await client.query(
  `SELECT pg_get_viewdef('health_check'::regclass, true) AS def`);
const viewDef = viewRows[0].def;
const listMatch = viewDef.match(/relname\s*=\s*ANY\s*\(\s*ARRAY\[([\s\S]*?)\]\)|relname\s+IN\s*\(([\s\S]*?)\)/i);
check('B view readable', 'health_check’s own rls_unforced table list is present and parseable',
  listMatch !== null, true);

const listText = listMatch ? (listMatch[1] ?? listMatch[2] ?? '') : '';
const trackedTables = new Set(
  [...listText.matchAll(/'([a-z_][a-z0-9_]*)'/g)].map(m => m[1]));

check('C list non-empty', 'the parsed rls_unforced list actually contains real table names',
  trackedTables.size >= 15, true);

// The real assertion: every table with RLS actually enabled must appear in
// the monitor's own list. A table present in the list but not currently
// RLS-enabled is a DIFFERENT, already-covered case (health_check's own
// `relrowsecurity=false OR relforcerowsecurity=false` clause reports that
// live, at runtime, every time the view is queried) — this test's job is
// only the direction that clause structurally cannot catch: a table the
// list has never heard of at all.
const untracked = rlsTables
  .filter(t => !trackedTables.has(t.relname))
  .map(t => t.relname);
check('D no blind spot', 'every RLS-enabled table is named in health_check’s rls_unforced list',
  untracked.length ? `untracked: ${untracked.join(', ')}` : 'none', 'none');

// The regression this test exists to catch structurally, not just via the
// list: a tracked table that has RLS ENABLED but not FORCED is still a real
// gap (the table owner — every role every migration in this repo runs
// as — bypasses a non-forced policy outright, per db/DEPLOYMENT.md's own
// point #1), and health_check's live query already reports it. Proven here
// too, directly against the catalog, so this suite doesn't just trust the
// view's own SQL is correct.
const enabledNotForced = rlsTables.filter(t => t.enabled && !t.forced).map(t => t.relname);
check('E forced too', 'every RLS-enabled table also has RLS FORCED, not merely enabled',
  enabledNotForced.length ? `enabled-not-forced: ${enabledNotForced.join(', ')}` : 'none', 'none');

await client.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
