#!/usr/bin/env node
/**
 * OLIVE BRANCH — health-check alerting.
 *
 * MASTERFILE §20.2b: "orphan_risk and retention_breach are also still views
 * with no alerting." That line is stale in one respect and still true in
 * another, both worth being honest about:
 *
 *   - `tools/healthcheck.mjs` already exists and already turns the
 *     `health_check` view (db/migrations/0006_court_tier.sql — the latest
 *     `CREATE OR REPLACE VIEW health_check`; 0007_custody_order.sql does not
 *     touch it, and there is no 0008 migration in this repository) into a
 *     non-zero exit code, wired into `tools/verify.sh`'s own "Health"
 *     section. That much of the gap was already closed before this file.
 *   - What did NOT exist: a way to run that same check from cron or an
 *     external monitor without a `psql` binary on the runner, and without
 *     scraping a human-formatted table for machine-parseable output. That is
 *     what this script adds — a second, complementary path into the SAME
 *     canonical view, not a competing one.
 *
 * Connects with `pg` directly over DATABASE_URL (falling back to
 * ADMIN_DATABASE_URL if DATABASE_URL is unset) — the split used throughout
 * packages/db/test/*.mjs (see pool.test.mjs, custody_order.test.mjs):
 * DATABASE_URL is meant to be a NOSUPERUSER NOBYPASSRLS role in a real
 * deployment, and none of health_check's underlying reads require anything
 * more — the RLS-protected tables it touches (pin_credential, expense,
 * message_log, custody_order) all default-permit any non-'child' session,
 * including one that never set app.role at all (current_role_name() IS
 * DISTINCT FROM 'child' is true when the GUC is unset), so no session setup
 * is needed here.
 *
 * HONEST SCOPE — read this before wiring this into anything:
 *   This script DETECTS and REPORTS. It does not send an email, does not
 *   post to Slack, does not page anyone. No such integration exists ANYWHERE
 *   in this repository. Its contract with the outside world is exactly:
 *   non-zero exit code + a structured line per breach on stderr. Turning
 *   that into a real page is a real, separate piece of future work — a cron
 *   entry plus a notification channel, neither of which is built here.
 *   Claiming otherwise in this comment would misrepresent what is actually
 *   in the repo, which is the one thing this project's house style will not
 *   tolerate (see CHANGELOG.md's own "false-green" history in §20.4).
 */
import pg from 'pg';

const DATABASE_URL = process.env.DATABASE_URL || process.env.ADMIN_DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL (or ADMIN_DATABASE_URL) required');
  process.exit(2);
}

const client = new pg.Client({ connectionString: DATABASE_URL });
let rows;
try {
  await client.connect();
  const res = await client.query(
    'SELECT check_name, severity, observed, threshold, meaning FROM health_check ORDER BY severity, check_name;'
  );
  rows = res.rows;
} catch (e) {
  console.error(`ABORT: cannot query health_check — ${e.message}`);
  await client.end().catch(() => {});
  process.exit(2);
}
await client.end().catch(() => {});

if (!rows.length) {
  console.error('ABORT: health_check returned no rows');
  process.exit(2);
}

const breaches = rows.filter((r) => Number(r.observed) > Number(r.threshold));

if (breaches.length) {
  // One structured line per breach, to stderr, meant to be grepped — not the
  // human table tools/healthcheck.mjs already prints to stdout.
  for (const r of breaches) {
    const description = String(r.meaning).replace(/"/g, "'");
    console.error(
      `ALERT check_name=${r.check_name} severity=${r.severity} ` +
      `count=${r.observed} threshold=${r.threshold} description="${description}"`
    );
  }
  console.error(`\n${breaches.length} of ${rows.length} health check(s) breached.`);
  process.exit(1);
}

console.log(`all clear — ${rows.length} health check(s), 0 breaches`);
process.exit(0);
