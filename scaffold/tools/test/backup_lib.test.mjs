/**
 * tools/backup_lib.mjs (audit P-04): backup naming, 7-daily + 4-weekly
 * retention, the stale-backup alarm, and at-rest encryption. No database.
 * The end-to-end job (real pg_dump through the scheduler, health-alert
 * subprocess) lives in packages/db/test/backup_job.test.mjs.
 */
import { mkdtempSync, writeFileSync, readFileSync, readdirSync, existsSync, rmSync, utimesSync }
  from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  parseBackupName, listBackups, planRetention, pruneBackups, newestBackupAgeHours,
  staleBackupAlarm, encryptFile, decryptFile, DEFAULT_MAX_BACKUP_AGE_HOURS,
} from '../backup_lib.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const stamp = (d) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const dbName = (d, db = 'olive_prod') => `olive_${db}_${stamp(d)}.dump`;
const mediaName = (d) => `olive_media_${stamp(d)}.tar.gz`;
const at = (iso) => new Date(iso);

// ---- A · naming -------------------------------------------------------------
{
  const p = parseBackupName('olive_olive_prod_20261107T030000Z.dump');
  check('A naming', 'a database dump parses: kind, timestamp, not encrypted',
    `${p.kind}/${p.ts.toISOString()}/${p.encrypted}`, 'db/2026-11-07T03:00:00.000Z/false');
  const m = parseBackupName('olive_media_20261107T030105Z.tar.gz');
  check('A naming', 'a media archive parses as kind media', `${m.kind}/${m.ts.toISOString()}`, 'media/2026-11-07T03:01:05.000Z');
  check('A naming', 'an encrypted file (.enc) parses and is flagged',
    parseBackupName('olive_olive_prod_20261107T030000Z.dump.enc').encrypted, true);
  for (const bad of ['olive_olive_prod_20261107T030000Z.dump.partial', 'notes.txt', 'olive_x_garbage.dump',
    'olive_olive_prod_20261399T030000Z.dump', 'olive_foo_20261107T030000Z.tar.gz', 'README.md']) {
    check('A naming', `"${bad}" is NOT a backup (never parsed, so never pruned)`, parseBackupName(bad), null);
  }
}

// ---- B · retention ----------------------------------------------------------
{
  // One dump per day at 03:00 UTC, 2026-10-01 .. 2026-11-07 (38 days). 2026-11-07 is a Saturday.
  const files = [];
  for (let d = at('2026-10-01T03:00:00Z'); d <= at('2026-11-07T03:00:00Z'); d = new Date(d.getTime() + 864e5)) {
    files.push(parseBackupName(dbName(d)));
  }
  const plan = planRetention(files);
  const keptDays = plan.keep.map((n) => parseBackupName(n).ts.toISOString().slice(5, 10)).sort();
  check('B retention', '38 nightly dumps -> exactly 7 daily + the 4-weekly picks survive (9 files)',
    plan.keep.length, 9);
  check('B retention', 'the 7 daily: the most recent 7 days (11-01 .. 11-07)',
    keptDays.filter((d) => d >= '11-01').join(','), '11-01,11-02,11-03,11-04,11-05,11-06,11-07');
  check('B retention', 'the weekly picks beyond that: the newest of the older ISO weeks (10-18, 10-25)',
    keptDays.filter((d) => d < '11-01').join(','), '10-18,10-25');
  check('B retention', 'everything else is pruned (29 files)', plan.prune.length, 29);
  check('B retention', 'keep and prune partition the input (nothing lost, nothing double-listed)',
    new Set([...plan.keep, ...plan.prune]).size === files.length && plan.keep.length + plan.prune.length === files.length, 'true');

  // Several backups the same day: only the newest of that day is a daily.
  const same = [at('2026-11-07T01:00:00Z'), at('2026-11-07T13:00:00Z'), at('2026-11-07T23:00:00Z')]
    .map((d) => parseBackupName(dbName(d)));
  const sp = planRetention(same);
  check('B retention', 'three backups in one day: the newest is kept, the older two pruned',
    `${sp.keep.length}/${sp.prune.length}/${sp.keep[0].includes('230000Z')}`, '1/2/true');

  // An outage must not shorten retention: 30 daily dumps ending 12 days ago, then one fresh dump.
  const gap = [];
  for (let i = 0; i < 30; i++) gap.push(parseBackupName(dbName(new Date(at('2026-10-06T03:00:00Z').getTime() - i * 864e5))));
  gap.push(parseBackupName(dbName(at('2026-11-07T03:00:00Z'))));
  const gp = planRetention(gap);
  check('B retention', 'after a 10+ day outage the older history is NOT wiped: today + 6 prior backup-days kept',
    gp.keep.filter((n) => n.includes('202610')).length >= 6 && gp.keep.some((n) => n.includes('20261107')), 'true');
  check('B retention', 'and the newest-ever backup is always kept', gp.keep.includes(dbName(at('2026-11-07T03:00:00Z'))), 'true');

  // db and media are independent families.
  const mixed = [
    parseBackupName(dbName(at('2026-11-07T03:00:00Z'))),
    parseBackupName(mediaName(at('2026-11-03T03:00:00Z'))),
  ];
  const mp = planRetention(mixed);
  check('B retention', 'a database dump and a media archive never count against each other', mp.prune.length, 0);
  const twoDbs = [
    parseBackupName(dbName(at('2026-11-07T03:00:00Z'), 'olive_prod')),
    parseBackupName(dbName(at('2026-11-06T03:00:00Z'), 'olive_staging')),
  ];
  check('B retention', 'two different databases in one directory are retained independently (each keeps its newest)',
    planRetention(twoDbs, { daily: 1, weekly: 1 }).prune.length, 0);
  const lonely = planRetention([parseBackupName(mediaName(at('2026-01-01T03:00:00Z')))]);
  check('B retention', 'a single very old backup is still kept (never prune to zero)', lonely.keep.length, 1);
  const custom = planRetention(files, { daily: 2, weekly: 1 });
  check('B retention', 'custom limits apply (2 daily + 1 weekly -> 2 files, as the weekly pick is a daily)',
    custom.keep.length, 2);

  // Real directory: prune deletes backups only.
  const dir = mkdtempSync(join(tmpdir(), 'olive-bk-'));
  try {
    for (const f of files.slice(0, 20)) writeFileSync(join(dir, f.name), 'x');
    writeFileSync(join(dir, 'notes.txt'), 'operator notes');
    writeFileSync(join(dir, 'olive_olive_prod_20260101T000000Z.dump.partial'), 'half');
    const dry = pruneBackups(dir, { dryRun: true });
    check('B retention', 'dryRun reports the plan and deletes nothing',
      `${dry.prune.length > 0}/${readdirSync(dir).length}`, 'true/22');
    const real = pruneBackups(dir);
    const left = readdirSync(dir);
    check('B retention', 'pruneBackups deletes exactly the planned files',
      left.filter((n) => parseBackupName(n)).length, real.keep.length);
    check('B retention', 'a non-backup file and a .partial file are never touched',
      left.includes('notes.txt') && left.includes('olive_olive_prod_20260101T000000Z.dump.partial'), 'true');
    check('B retention', 'listBackups on a missing directory is empty, not a throw', listBackups(join(dir, 'nope')).length, 0);
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

// ---- C · stale-backup alarm -------------------------------------------------
{
  const dir = mkdtempSync(join(tmpdir(), 'olive-alarm-'));
  const now = at('2026-11-07T12:00:00Z').getTime();
  try {
    check('C alarm', 'BACKUP_DIR unset: no alarm (backups were never promised)', staleBackupAlarm({}, now), null);
    const never = staleBackupAlarm({ BACKUP_DIR: dir }, now);
    check('C alarm', 'BACKUP_DIR set but no dump exists: alarm "never"',
      `${never.checkName}/${never.severity}/${never.observed}`, 'backup_stale/high/never');
    writeFileSync(join(dir, dbName(at('2026-11-07T03:00:00Z'))), 'x');
    check('C alarm', 'a 9-hour-old dump: no alarm', staleBackupAlarm({ BACKUP_DIR: dir }, now), null);
    const old = mkdtempSync(join(tmpdir(), 'olive-alarm-old-'));
    try {
      writeFileSync(join(old, dbName(at('2026-11-05T12:00:00Z'))), 'x');
      const a = staleBackupAlarm({ BACKUP_DIR: old }, now);
      check('C alarm', 'a 48-hour-old dump (limit 36): alarm with the age', `${a?.checkName}/${a?.observed}`, 'backup_stale/48.0');
      check('C alarm', 'the alarm text names the directory and the limit',
        a.meaning.includes(old) && a.meaning.includes('36'), 'true');
      check('C alarm', 'BACKUP_MAX_AGE_HOURS raises the limit (72h -> no alarm)',
        staleBackupAlarm({ BACKUP_DIR: old, BACKUP_MAX_AGE_HOURS: '72' }, now), null);
      check('C alarm', 'an invalid BACKUP_MAX_AGE_HOURS falls back to the default, not "never alarm"',
        staleBackupAlarm({ BACKUP_DIR: old, BACKUP_MAX_AGE_HOURS: 'abc' }, now)?.threshold, DEFAULT_MAX_BACKUP_AGE_HOURS);
      writeFileSync(join(old, dbName(at('2026-11-07T11:00:00Z')) + '.enc'), 'x');
      check('C alarm', 'a fresh ENCRYPTED dump satisfies the check (it is the backup)',
        staleBackupAlarm({ BACKUP_DIR: old }, now), null);
    } finally { rmSync(old, { recursive: true, force: true }); }
    const mediaOnly = mkdtempSync(join(tmpdir(), 'olive-alarm-media-'));
    try {
      writeFileSync(join(mediaOnly, mediaName(at('2026-11-07T11:00:00Z'))), 'x');
      check('C alarm', 'a fresh MEDIA archive does not satisfy the database-dump check',
        staleBackupAlarm({ BACKUP_DIR: mediaOnly }, now)?.observed, 'never');
    } finally { rmSync(mediaOnly, { recursive: true, force: true }); }
    check('C alarm', 'newestBackupAgeHours is Infinity for a directory that does not exist',
      newestBackupAgeHours(join(dir, 'missing'), now), Infinity);
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

// ---- D · encryption ---------------------------------------------------------
{
  const dir = mkdtempSync(join(tmpdir(), 'olive-enc-'));
  try {
    const plain = join(dir, 'dump.bin');
    const body = Buffer.concat([Buffer.from('PGDMP-SECRET-MARKER-'), randomBytes(1_500_000)]);
    writeFileSync(plain, body);
    const enc = join(dir, 'dump.bin.enc');
    await encryptFile(plain, enc, 'correct horse battery staple');
    const encBytes = readFileSync(enc);
    check('D encryption', 'ciphertext is larger than the plaintext by exactly header+tag (5+16+12+16)',
      encBytes.length - body.length, 49);
    check('D encryption', 'the plaintext marker does not appear in the encrypted file',
      encBytes.includes(Buffer.from('PGDMP-SECRET-MARKER-')), false);
    const back = join(dir, 'back.bin');
    await decryptFile(enc, back, 'correct horse battery staple');
    check('D encryption', '1.5 MB round-trips byte-exact', readFileSync(back).equals(body), true);

    const enc2 = join(dir, 'dump2.enc');
    await encryptFile(plain, enc2, 'correct horse battery staple');
    check('D encryption', 'two encryptions of one file differ (fresh random salt and iv)',
      readFileSync(enc2).equals(encBytes), false);

    let err = '';
    try { await decryptFile(enc, join(dir, 'wrong.bin'), 'WRONG'); } catch (e) { err = e.message; }
    check('D encryption', 'the wrong passphrase is refused with a clear message', /wrong passphrase or corrupted/.test(err), true);
    check('D encryption', 'a refused decrypt leaves NO output or partial file behind',
      existsSync(join(dir, 'wrong.bin')) || existsSync(join(dir, 'wrong.bin.partial')), false);

    const tampered = Buffer.from(encBytes); tampered[1000] ^= 0x01;
    writeFileSync(join(dir, 'tampered.enc'), tampered);
    err = '';
    try { await decryptFile(join(dir, 'tampered.enc'), join(dir, 't.bin'), 'correct horse battery staple'); } catch (e) { err = e.message; }
    check('D encryption', 'one flipped bit anywhere is detected (AES-GCM authentication), not silently mis-decrypted',
      /corrupted\/tampered/.test(err), true);

    writeFileSync(join(dir, 'trunc.enc'), encBytes.subarray(0, encBytes.length - 100));
    err = '';
    try { await decryptFile(join(dir, 'trunc.enc'), join(dir, 'tr.bin'), 'correct horse battery staple'); } catch (e) { err = e.message; }
    check('D encryption', 'a truncated file is refused', /wrong passphrase or corrupted/.test(err), true);

    writeFileSync(join(dir, 'notenc.enc'), Buffer.alloc(200, 7));
    err = '';
    try { await decryptFile(join(dir, 'notenc.enc'), join(dir, 'n.bin'), 'x'); } catch (e) { err = e.message; }
    check('D encryption', 'a file that is not one of ours says so', /not an Olive Branch encrypted backup/.test(err), true);

    err = '';
    try { await encryptFile(plain, join(dir, 'e.enc'), ''); } catch (e) { err = e.message; }
    check('D encryption', 'an empty passphrase is refused (no silent "encrypted" with a blank key)', /passphrase required/.test(err), true);

    // The CLI.
    const cli = join(here, '..', 'backup-decrypt.mjs');
    const run = (args, pass) => spawnSync(process.execPath, [cli, ...args],
      { env: { ...process.env, BACKUP_ENCRYPTION_PASSPHRASE: pass ?? '' }, encoding: 'utf8' });
    const ok = run([enc, join(dir, 'cli.bin')], 'correct horse battery staple');
    check('D encryption', 'backup-decrypt.mjs: right passphrase -> exit 0 and the file is restored',
      `${ok.status}/${readFileSync(join(dir, 'cli.bin')).equals(body)}`, '0/true');
    check('D encryption', 'backup-decrypt.mjs: wrong passphrase -> exit 1', run([enc, join(dir, 'cli2.bin')], 'nope').status, 1);
    check('D encryption', 'backup-decrypt.mjs: missing args or passphrase -> exit 2 (usage)', run([enc], 'x').status, 2);
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
