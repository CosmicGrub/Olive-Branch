/**
 * packages/db/test/health_alert.test.mjs — tools/health-alert.mjs, exercised
 * against a REAL Postgres and the REAL `health_check` view
 * (db/migrations/0006_court_tier.sql). MASTERFILE §20.2b: "orphan_risk and
 * retention_breach are also still views with no alerting." This is the
 * alerting half of closing that line.
 *
 * Same DATABASE_URL/ADMIN_DATABASE_URL split as pool.test.mjs and
 * custody_order.test.mjs: DATABASE_URL is the NOSUPERUSER NOBYPASSRLS role
 * the script itself is meant to run as; ADMIN_DATABASE_URL (falls back to
 * DATABASE_URL) seeds and tears down fixtures with full privileges. NOT part
 * of `npm test`'s default JS-suite chain, for the same reason its two
 * siblings above aren't — this needs a live, migrated Postgres, not a fake.
 *
 * Two cases:
 *   A) VIOLATION — seed exactly db/test/0004_e2e_message.test.sql's own
 *      "ORPHAN DETECTION" fixture shape (§7 of that file): a media_artifact
 *      that expires before the pending delivery_intent pointing at it.
 *      Assert the script exits non-zero and its stderr names
 *      check_name=orphan_risk with the view's own severity. Compares against
 *      a captured BASELINE `observed` count rather than asserting it was 0
 *      beforehand, so this suite still proves its point on a database another
 *      suite has already touched.
 *   B) HEALTHY — after this suite's own fixture is torn down, if (and only
 *      if) the whole database is independently confirmed to have zero rows
 *      across every health_check bucket, the script must exit 0 with an
 *      "all clear" line. A shared/dirty database left non-zero by another
 *      suite is reported honestly as a SKIP here rather than masked or
 *      turned into a false failure — this file did not create that mess and
 *      cannot safely clean up rows it does not own.
 */
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import pg from 'pg';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const SCRIPT = join(REPO_ROOT, 'tools', 'health-alert.mjs');

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CHILD = '77777777-7777-7777-7777-777777777777';
const DAD = '88888888-8888-8888-8888-888888888888';
const ARTIFACT = 'cccccccc-0000-0000-0000-00000000000a';
const INTENT = 'dddddddd-0000-0000-0000-00000000000a';

async function clearFixture() {
  await admin.query(`DELETE FROM delivery_intent WHERE id = $1`, [INTENT]);
  await admin.query(`DELETE FROM media_artifact WHERE id = $1`, [ARTIFACT]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
  await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
}
await clearFixture();

function runAlert() {
  try {
    const out = execFileSync(process.execPath, [SCRIPT], {
      encoding: 'utf8',
      env: { ...process.env, DATABASE_URL },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    return { code: 0, stdout: out, stderr: '' };
  } catch (e) {
    return { code: e.status, stdout: e.stdout?.toString() ?? '', stderr: e.stderr?.toString() ?? '' };
  }
}

// A · seed the exact db/test/0004_e2e_message.test.sql "ORPHAN DETECTION"
// shape: an artifact that expires before the pending intent pointing at it.
{
  const { rows: beforeRows } = await admin.query(
    `SELECT observed FROM health_check WHERE check_name = 'orphan_risk'`);
  const baseline = Number(beforeRows[0]?.observed ?? 0);

  await admin.query(
    `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`,
    [DAD]);
  await admin.query(
    `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
       ($1,'HealthAlertTestChild','2016-04-02','America/New_York')`, [CHILD]);
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, valid) VALUES
       ($1, $2, 'guardian', tstzrange(now() - interval '1 year', null))`, [CHILD, DAD]);
  await admin.query(
    `INSERT INTO media_artifact
       (id, child_id, author_id, kind, storage_key, duration_ms, captured_at,
        captured_tz, expires_at)
     VALUES ($1, $2, $3, 'video_msg', 'health-alert-test/short-clock', 5000, now(),
             'America/New_York', now() + interval '5 days')`,
    [ARTIFACT, CHILD, DAD]);
  await admin.query(
    `INSERT INTO delivery_intent
       (id, child_id, sender_id, payload_kind, payload_ref, policy,
        target_local_date, target_daypart, state, expires_at)
     VALUES ($1, $2, $3, 'e2e_video', $4, 'on_local_date',
             current_date + 40, 'bedtime', 'pending', now() + interval '60 days')`,
    [INTENT, CHILD, DAD, ARTIFACT]);

  const { rows: afterInsertRows } = await admin.query(
    `SELECT observed FROM health_check WHERE check_name = 'orphan_risk'`);
  check('A seed', 'orphan_risk observed increases by exactly 1 over baseline',
    Number(afterInsertRows[0]?.observed ?? -1), baseline + 1);

  const r = runAlert();
  check('A violation', 'exit code is non-zero when orphan_risk is breached', r.code !== 0, true);
  check('A violation', 'stderr names check_name=orphan_risk',
    r.stderr.includes('check_name=orphan_risk'), true);
  check('A violation', 'stderr carries the view\'s own severity (high)',
    r.stderr.includes('severity=high'), true);
  check('A violation', 'stderr carries the count', r.stderr.includes('count=1') || /count=\d+/.test(r.stderr), true);
  check('A violation', 'stdout is NOT the all-clear line on a breach',
    r.stdout.includes('all clear'), false);

  await clearFixture();

  const { rows: afterCleanupRows } = await admin.query(
    `SELECT observed FROM health_check WHERE check_name = 'orphan_risk'`);
  check('A cleanup', 'orphan_risk returns to its pre-suite baseline',
    Number(afterCleanupRows[0]?.observed ?? -1), baseline);
}

// B · healthy case — only assertable when the WHOLE database (not just
// orphan_risk) is independently confirmed clean, since health_check sums
// across everything any suite has left behind.
{
  const { rows: globalRows } = await admin.query(
    `SELECT coalesce(sum(observed), 0)::bigint AS total FROM health_check`);
  const totalObserved = Number(globalRows[0]?.total ?? 0);

  if (totalObserved === 0) {
    const r = runAlert();
    check('B healthy', 'exit code is 0 on an all-clear database', r.code, 0);
    check('B healthy', 'stdout reports "all clear"', r.stdout.includes('all clear'), true);
    check('B healthy', 'stderr is empty on the healthy path', r.stderr, '');
  } else {
    console.log(`\nB healthy`);
    console.log(`  SKIP  database already carries ${totalObserved} observed health_check ` +
      `row(s) left by another suite/fixture — not this file's mess to assert clean.`);
  }
}

await admin.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
