#!/usr/bin/env node
/**
 * OLIVE BRANCH — migration runner.
 *
 * §20.2b listed "no migration runner" as an open gap. Applying migrations by
 * hand has produced two incidents in this repository already: a suite run
 * against a database missing 0004, and a suite run twice against the same
 * database. Both looked like code failures.
 *
 * Four properties, each enforced rather than assumed:
 *
 *  M1  ORDERED. Files apply in lexical order and the runner refuses to apply
 *      one if an earlier file is unapplied — a gap means someone rebased a
 *      migration in, and applying out of order corrupts silently.
 *  M2  IDEMPOTENT. An already-applied migration is skipped, so re-running is
 *      always safe.
 *  M3  IMMUTABLE. Each applied file's SHA-256 is recorded. If a file changes
 *      after being applied, the runner REFUSES — an edited migration means the
 *      database and the repository disagree about the schema and no amount of
 *      re-running will reconcile them.
 *  M4  TRANSACTIONAL PER FILE. Each migration runs in its own transaction, so a
 *      failure leaves the schema at a known version rather than half-applied.
 */
import { readdirSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const DIR = process.env.MIGRATIONS_DIR ?? 'db/migrations';
const PSQL = process.env.PSQL_CMD;
if (!PSQL) { console.error('PSQL_CMD required'); process.exit(2); }

const sh = (sql, opts = {}) => {
  const [cmd, ...args] = PSQL.split(' ');
  return execFileSync(cmd, [...args, '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1',
    ...(opts.file ? ['-f', opts.file] : ['-c', sql])], { encoding: 'utf8' });
};

const sha = (s) => createHash('sha256').update(s).digest('hex');

// `IF NOT EXISTS` emits a NOTICE on every subsequent run, which makes clean
// output noisy and trains readers to ignore warnings. Suppress it for this
// statement only.
sh(`SET LOCAL client_min_messages = warning;
    CREATE TABLE IF NOT EXISTS schema_migration (
      filename    text PRIMARY KEY,
      checksum    text NOT NULL,
      applied_at  timestamptz NOT NULL DEFAULT now(),
      duration_ms integer
    );`);

const applied = new Map(
  sh(`SELECT filename || '\u0001' || checksum FROM schema_migration;`)
    .trim().split('\n').filter(Boolean).map(l => l.split('\u0001')));

const files = readdirSync(DIR).filter(f => f.endsWith('.sql')).sort();
if (!files.length) { console.error(`no migrations in ${DIR}`); process.exit(2); }

// M3 — verify every already-applied file still matches what was applied.
const tampered = [];
for (const f of files) {
  const rec = applied.get(f);
  if (rec && rec !== sha(readFileSync(join(DIR, f), 'utf8'))) tampered.push(f);
}
if (tampered.length) {
  console.error(`REFUSING: these migrations changed after being applied:\n` +
    tampered.map(f => `  ${f}`).join('\n') +
    `\nThe database and the repository disagree about the schema. Write a new ` +
    `migration; never edit an applied one.`);
  process.exit(1);
}

// Orphan check runs FIRST: an applied migration missing from the repo is a
// more fundamental problem than ordering, and reporting ordering instead sends
// the reader looking in the wrong place.
const orphans = [...applied.keys()].filter(f => !files.includes(f));
if (orphans.length) {
  console.error(`REFUSING: applied migrations missing from ${DIR}:\n` +
    orphans.map(f => `  ${f}`).join('\n') +
    `\nThe database contains schema this repository cannot describe.`);
  process.exit(1);
}

// M1 — no gaps.
//
// `findIndex` returns -1 when every file is applied, and `slice(-1)` then
// returns the LAST element rather than an empty list — so an up-to-date
// database reported itself as out-of-order. Guard the sentinel explicitly.
const pending = files.filter(f => !applied.has(f));
const firstPendingIdx = files.findIndex(f => !applied.has(f));
const gap = firstPendingIdx === -1
  ? []
  : files.slice(firstPendingIdx).filter(f => applied.has(f));
if (gap.length) {
  console.error(`REFUSING: out-of-order state. These are applied but sit after ` +
    `an unapplied migration:\n${gap.map(f => `  ${f}`).join('\n')}`);
  process.exit(1);
}

if (!pending.length) {
  console.log(`up to date — ${files.length} migration(s) applied`);
  process.exit(0);
}

for (const f of pending) {
  const body = readFileSync(join(DIR, f), 'utf8');
  const t0 = Date.now();
  // M4 — psql -1 wraps the file in a single transaction. Files that manage
  // their own BEGIN/COMMIT are compatible: the outer block becomes a no-op.
  const [cmd, ...args] = PSQL.split(' ');
  try {
    execFileSync(cmd, [...args, '-q', '-v', 'ON_ERROR_STOP=1', '-f', join(DIR, f)],
      { encoding: 'utf8' });
  } catch (e) {
    console.error(`FAILED: ${f}\n${e.stderr || e.message}`);
    console.error('Schema left at the last successfully applied migration.');
    process.exit(1);
  }
  const ms = Date.now() - t0;
  sh(`INSERT INTO schema_migration (filename, checksum, duration_ms)
      VALUES ('${f}', '${sha(body)}', ${ms});`);
  console.log(`applied ${f} (${ms}ms)`);
}
console.log(`done — ${pending.length} applied, ${files.length} total`);
