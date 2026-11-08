/**
 * The scheduler's `backup` job end to end (audit P-04): a REAL pg_dump of this
 * database through tools/backup-db.sh, real media archive, real encryption,
 * real retention pruning, a real off-host sync command, and the stale-backup
 * alarm in the real tools/health-alert.mjs subprocess.
 *
 * Needs ADMIN_DATABASE_URL (a superuser: the dump must read FORCE-RLS tables,
 * which is exactly why production uses the BYPASSRLS backup_reader role) and
 * PG_DUMP_BIN (verify.sh exports it from PGBIN).
 *
 *   A. Off unless configured: no BACKUP_DIR / no BACKUP_DATABASE_URL -> skipped.
 *   B. A real run writes a valid custom-format dump (PGDMP magic, and
 *      pg_restore --list parses it) plus a gzip media archive.
 *   C. Encryption: files are .enc, no plaintext left beside them, and the
 *      decrypted dump is a valid dump that pg_restore accepts.
 *   D. Retention runs after a good backup: 7 daily + 4 weekly, unrelated
 *      files untouched.
 *   E. A failed dump changes NOTHING: no prune, no sync, history intact.
 *   F. Sync command: runs in the backup dir with BACKUP_NEW_FILES; a failing
 *      sync fails the job but never deletes the local backup.
 *   G. runNamedJob('backup') under the real advisory lock / JOB_NAMES order.
 *   H. health-alert: stale or missing backup -> ALERT backup_stale + exit 1;
 *      fresh -> no such alert; BACKUP_DIR unset -> exactly as before.
 */
import pg from 'pg';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, readdirSync, existsSync, rmSync, mkdirSync }
  from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPool } from '../src/pool.mjs';
import { runBackupJob, runNamedJob, JOB_NAMES } from '../../../tools/scheduler.mjs';
import { decryptFile, parseBackupName } from '../../../tools/backup_lib.mjs';

const ADMIN = process.env.ADMIN_DATABASE_URL;
const DATABASE_URL = process.env.DATABASE_URL ?? ADMIN;
const PG_DUMP_BIN = process.env.PG_DUMP_BIN;
if (!ADMIN || !PG_DUMP_BIN) {
  console.error('ADMIN_DATABASE_URL and PG_DUMP_BIN required — this suite takes a real pg_dump.');
  process.exit(2);
}
const PG_RESTORE_BIN = join(dirname(PG_DUMP_BIN), 'pg_restore');

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const healthAlert = join(here, '..', '..', '..', 'tools', 'health-alert.mjs');
const tmp = (p) => mkdtempSync(join(tmpdir(), `olive-${p}-`));
const stamp = (d) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const oldDump = (daysAgo, db = 'olive_prod') =>
  `olive_${db}_${stamp(new Date(Date.now() - daysAgo * 864e5))}.dump`;
const restoreList = (file) => spawnSync(PG_RESTORE_BIN, ['--list', file], { encoding: 'utf8' });
const magic = (file, n) => readFileSync(file).subarray(0, n);

const dirs = [];
const mk = (p) => { const d = tmp(p); dirs.push(d); return d; };
const baseEnv = (dir, extra = {}) => ({
  ...process.env, BACKUP_DIR: dir, BACKUP_DATABASE_URL: ADMIN, PG_DUMP_BIN,
  MEDIA_STORAGE_ROOT: '', BACKUP_ENCRYPTION_PASSPHRASE: '', BACKUP_SYNC_COMMAND: '', ...extra,
});

try {
  // ---- A · off unless configured -------------------------------------------
  {
    const a = await runBackupJob({}, {});
    check('A off by default', 'no BACKUP_DIR: skipped (not_configured), never a failure',
      `${a.status}/${a.reason}`, 'skipped/not_configured');
    const b = await runBackupJob({ BACKUP_DIR: mk('off') }, {});
    check('A off by default', 'BACKUP_DIR without BACKUP_DATABASE_URL: skipped (no_database_url), no invented credential',
      `${b.status}/${b.reason}`, 'skipped/no_database_url');
  }

  // ---- B · a real run --------------------------------------------------------
  const media = mk('media');
  mkdirSync(join(media, 'children', 'c1'), { recursive: true });
  writeFileSync(join(media, 'children', 'c1', 'photo.bin'), Buffer.alloc(2048, 9));
  {
    const dir = mk('b');
    const r = await runBackupJob(baseEnv(dir, { MEDIA_STORAGE_ROOT: media }), {});
    check('B real run', 'the job reports ok', `${r.status}/${r.error ?? ''}`, 'ok/');
    const files = readdirSync(dir);
    const dump = files.find((f) => parseBackupName(f)?.kind === 'db');
    const tar = files.find((f) => parseBackupName(f)?.kind === 'media');
    check('B real run', 'one database dump and one media archive were written', `${Boolean(dump)}/${Boolean(tar)}`, 'true/true');
    check('B real run', 'the dump is a real custom-format pg_dump (PGDMP magic)', magic(join(dir, dump), 5).toString(), 'PGDMP');
    const lst = restoreList(join(dir, dump));
    check('B real run', 'and pg_restore --list can read it (a restorable archive, not just a non-empty file)',
      `${lst.status}/${/app_user/.test(lst.stdout)}`, '0/true');
    check('B real run', 'the media archive is a gzip stream', magic(join(dir, tar), 2).toString('hex'), '1f8b');
    check('B real run', 'no .partial file is left behind', files.some((f) => f.endsWith('.partial')), false);
    check('B real run', 'the result lists the new files and nothing was pruned from an empty history',
      `${r.files.length}/${r.pruned.length}/${r.encrypted}`, '2/0/false');
  }

  // ---- C · encryption ---------------------------------------------------------
  {
    const dir = mk('c');
    const r = await runBackupJob(baseEnv(dir, { MEDIA_STORAGE_ROOT: media,
      BACKUP_ENCRYPTION_PASSPHRASE: 'a long operator-chosen passphrase' }), {});
    const files = readdirSync(dir);
    check('C encryption', 'job ok and flagged encrypted', `${r.status}/${r.encrypted}`, 'ok/true');
    check('C encryption', 'every backup file is .enc and NO plaintext dump/archive remains',
      files.every((f) => f.endsWith('.enc')) && files.length === 2, 'true');
    const enc = files.find((f) => f.endsWith('.dump.enc'));
    check('C encryption', 'the encrypted file does not start with the PGDMP magic', magic(join(dir, enc), 5).toString() !== 'PGDMP', 'true');
    const back = join(dir, 'restored.dump');
    await decryptFile(join(dir, enc), back, 'a long operator-chosen passphrase');
    check('C encryption', 'decrypting yields a valid dump pg_restore accepts', `${magic(back, 5)}/${restoreList(back).status}`, 'PGDMP/0');
    let wrong = '';
    try { await decryptFile(join(dir, enc), join(dir, 'x.dump'), 'wrong'); } catch (e) { wrong = e.message; }
    check('C encryption', 'the wrong passphrase cannot recover it', /wrong passphrase/.test(wrong), true);
  }

  // ---- D · retention after a good backup ----------------------------------------
  {
    const dir = mk('d');
    for (let d = 1; d <= 30; d++) writeFileSync(join(dir, oldDump(d)), 'old');
    writeFileSync(join(dir, 'operator-notes.txt'), 'keep me');
    const r = await runBackupJob(baseEnv(dir), {});
    const left = readdirSync(dir);
    const dumps = left.filter((f) => parseBackupName(f)?.kind === 'db');
    check('D retention', 'job ok', r.status, 'ok');
    check('D retention', '31 dumps (30 old + 1 fresh) are thinned to the 7-daily + 4-weekly set (<= 11, >= 8)',
      dumps.length <= 11 && dumps.length >= 8, 'true');
    check('D retention', 'the brand-new backup survived and is the newest', dumps.includes(r.files[0]), 'true');
    check('D retention', 'the 6 most recent old days survive alongside it (days 1-6)',
      [1, 2, 3, 4, 5, 6].every((d) => dumps.some((f) => f.startsWith(oldDump(d).slice(0, 25)))), 'true');
    check('D retention', 'something old WAS pruned, and the result reports exactly what',
      r.pruned.length > 0 && r.pruned.every((n) => !left.includes(n)), 'true');
    check('D retention', 'an unrelated operator file in the directory is never touched', left.includes('operator-notes.txt'), 'true');
  }

  // ---- E · a failed dump changes nothing -------------------------------------------
  {
    const dir = mk('e');
    for (let d = 1; d <= 12; d++) writeFileSync(join(dir, oldDump(d)), 'old');
    const before = readdirSync(dir).sort().join(',');
    const bad = new URL(ADMIN); bad.pathname = '/olive_no_such_database_xyz';
    const r = await runBackupJob(baseEnv(dir, { BACKUP_DATABASE_URL: bad.toString(),
      BACKUP_SYNC_COMMAND: 'touch SYNC_RAN' }), {});
    check('E failure', 'a dump that cannot connect is reported failed at the dump stage',
      `${r.status}/${r.stage}`, 'failed/dump');
    check('E failure', 'with the error text for the operator', String(r.error).length > 0, 'true');
    check('E failure', 'the existing history is completely untouched (no prune on a failing night)',
      readdirSync(dir).filter((f) => f !== 'SYNC_RAN').sort().join(','), before);
    check('E failure', 'and the sync command was NOT run for a backup that never happened',
      existsSync(join(dir, 'SYNC_RAN')), false);
    check('E failure', 'no .partial file left behind', readdirSync(dir).some((f) => f.endsWith('.partial')), false);
  }

  // ---- F · sync ---------------------------------------------------------------------
  {
    const dir = mk('f');
    const r = await runBackupJob(baseEnv(dir, { BACKUP_SYNC_COMMAND: 'printf "%s" "$BACKUP_NEW_FILES" > sync_marker.txt; pwd > sync_cwd.txt' }), {});
    check('F sync', 'a good sync leaves the job ok with synced=true', `${r.status}/${r.synced}`, 'ok/true');
    const marker = readFileSync(join(dir, 'sync_marker.txt'), 'utf8');
    check('F sync', 'the command saw exactly the newly written file in BACKUP_NEW_FILES', marker, r.files.join('\n'));
    check('F sync', 'and ran with the backup directory as its working directory',
      readFileSync(join(dir, 'sync_cwd.txt'), 'utf8').trim().endsWith(dir.split(/[\\/]/).pop()), 'true');
    const dir2 = mk('f2');
    const bad = await runBackupJob(baseEnv(dir2, { BACKUP_SYNC_COMMAND: 'echo "remote unreachable" >&2; exit 7' }), {});
    check('F sync', 'a failing sync command fails the job and says why', `${bad.status}/${bad.synced}/${/remote unreachable/.test(bad.error)}`, 'failed/false/true');
    check('F sync', 'but the local backup is kept (a sync outage must never delete the only copy)',
      readdirSync(dir2).some((f) => parseBackupName(f)?.kind === 'db'), 'true');
  }

  // ---- G · through the scheduler's own runner ------------------------------------------
  {
    check('G scheduler', 'JOB_NAMES includes purge-challenges, expiry-digest and backup, and health-alert runs LAST (so it sees the new backup)',
      JOB_NAMES.join(','), 'rematerialize,reap-media,sweep-orphan-media,purge-challenges,expiry-digest,backup,health-alert');
    const pool = createPool(DATABASE_URL);
    const saved = { ...process.env };
    try {
      for (const k of ['BACKUP_DIR', 'BACKUP_DATABASE_URL']) delete process.env[k];
      const off = await runNamedJob(pool, DATABASE_URL, 'backup');
      check('G scheduler', 'runNamedJob(backup) with nothing configured is ok+skipped, not a failure',
        `${off.ok}/${off.skipped}`, 'true/true');
      const dir = mk('g');
      Object.assign(process.env, baseEnv(dir));
      const on = await runNamedJob(pool, DATABASE_URL, 'backup');
      check('G scheduler', 'runNamedJob(backup) configured really produces a backup under the job lock',
        `${on.ok}/${readdirSync(dir).filter((f) => f.endsWith('.dump')).length}`, 'true/1');
    } finally {
      for (const k of Object.keys(process.env)) if (!(k in saved)) delete process.env[k];
      Object.assign(process.env, saved);
      await pool.end();
    }
  }

  // ---- H · the stale-backup alarm in the real health-alert -------------------------------
  {
    const run = (extra) => spawnSync(process.execPath, [healthAlert], {
      env: { ...process.env, DATABASE_URL: ADMIN, ...extra }, encoding: 'utf8' });
    const none = (() => { const e = { ...process.env, DATABASE_URL: ADMIN }; delete e.BACKUP_DIR;
      return spawnSync(process.execPath, [healthAlert], { env: e, encoding: 'utf8' }); })();
    check('H alarm', 'BACKUP_DIR unset: no backup_stale alert (behaviour identical to before this pass)',
      /backup_stale/.test(none.stderr), false);

    const empty = mk('h1');
    const r1 = run({ BACKUP_DIR: empty });
    check('H alarm', 'BACKUP_DIR set but empty: ALERT backup_stale, severity high, count=never, exit 1',
      `${/ALERT check_name=backup_stale severity=high count=never/.test(r1.stderr)}/${r1.status}`, 'true/1');

    const stale = mk('h2');
    writeFileSync(join(stale, oldDump(3)), 'x');
    const r2 = run({ BACKUP_DIR: stale });
    check('H alarm', 'a 3-day-old newest dump (limit 36 h): ALERT backup_stale with its age',
      `${/check_name=backup_stale severity=high count=7\d\.\d/.test(r2.stderr)}/${r2.status}`, 'true/1');
    const r2b = run({ BACKUP_DIR: stale, BACKUP_MAX_AGE_HOURS: '100' });
    check('H alarm', 'BACKUP_MAX_AGE_HOURS=100 silences it', /backup_stale/.test(r2b.stderr), false);

    const fresh = mk('h3');
    await runBackupJob(baseEnv(fresh), {});
    const r3 = run({ BACKUP_DIR: fresh });
    check('H alarm', 'right after a real backup: no backup_stale alert', /backup_stale/.test(r3.stderr), false);
  }
} finally {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
