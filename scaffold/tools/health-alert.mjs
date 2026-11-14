#!/usr/bin/env node
/**
 * OLIVE BRANCH — health-check alerting.
 *
 * MASTERFILE §20.2b: "orphan_risk and retention_breach are also still views
 * with no alerting." That line is stale in one respect and still true in
 * another, both worth being honest about:
 *
 *   - `tools/healthcheck.mjs` already exists and already turns the
 *     `health_check` view — grep db/migrations/*.sql for
 *     `CREATE OR REPLACE VIEW health_check` for its real, current shape
 *     rather than trusting any specific migration number named here:
 *     pinning one has already gone stale on this exact line TWICE (0006,
 *     then 0028) — into a
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
 * more. Since migration 0047 the view reads through an aggregate-only
 * SECURITY DEFINER function, so the counts are true for any caller under FORCE
 * RLS and this script declares no app.role (before 0047 it had to claim
 * `system`, a blanket read of every family's rows, or read zeros). Prefer the
 * dedicated `health_monitor` login via HEALTH_DATABASE_URL.
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
import { staleBackupAlarm } from './backup_lib.mjs';

// 0047: HEALTH_DATABASE_URL is the dedicated monitoring login (`health_monitor`:
// SELECT on health_check and nothing else, so it can count but never read a row).
// It wins when set; DATABASE_URL / ADMIN_DATABASE_URL remain valid fallbacks.
const DATABASE_URL = process.env.HEALTH_DATABASE_URL || process.env.DATABASE_URL || process.env.ADMIN_DATABASE_URL;
if (!DATABASE_URL) {
  console.error('HEALTH_DATABASE_URL (or DATABASE_URL / ADMIN_DATABASE_URL) required');
  process.exit(2);
}

const client = new pg.Client({ connectionString: DATABASE_URL });
let rows;
try {
  await client.connect();
  // 0047: no app.role is needed (or wanted). health_check reads through
  // health_counts(), an aggregate-only SECURITY DEFINER function, so the counts
  // are true for ANY caller under FORCE RLS. Before 0047 this connection had to
  // declare itself `system`, which is a blanket read of every family's rows just
  // to count them; and a caller that forgot read zeros and never alerted.
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

// P-04: stale-backup alarm. Not a row of the health_check VIEW (a backup lives
// on a filesystem, which SQL cannot see), so it is evaluated here and merged
// into the same ALERT stream / exit code. Only active when BACKUP_DIR is set
// (see tools/backup_lib.mjs's staleBackupAlarm for why: unset means backups
// were never promised, so there is nothing to be late).
const staleBackup = staleBackupAlarm(process.env);
if (staleBackup) {
  breaches.push({
    check_name: staleBackup.checkName, severity: staleBackup.severity,
    observed: staleBackup.observed, threshold: staleBackup.threshold,
    meaning: staleBackup.meaning,
  });
  rows.push(breaches[breaches.length - 1]);
}

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
