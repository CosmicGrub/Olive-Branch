// OLIVE BRANCH — backup automation helpers (audit P-04). Side-effect-free
// (no process.exit, no top-level work) so tools/scheduler.mjs's `backup` job,
// tools/health-alert.mjs's stale-backup alarm and the tests share ONE
// implementation of "what is a backup file", "which ones to keep", "how old
// is the newest one".
//
// What this file is NOT: it does not take a dump itself (tools/backup-db.sh /
// tools/backup-media.sh do, unchanged -- pg_dump -Fc, partial-file guard,
// 100-byte floor) and it invents no credentials: the database URL, the
// encryption passphrase and the off-host sync command all come from the
// operator's environment or the feature stays off.
import { createCipheriv, createDecipheriv, randomBytes, scrypt } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, readdirSync, statSync, unlinkSync,
         renameSync } from 'node:fs';
import { join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { promisify } from 'node:util';

const scryptAsync = promisify(scrypt);

export const DEFAULT_DAILY_KEEP = 7;
export const DEFAULT_WEEKLY_KEEP = 4;
/** health-alert fires `backup_stale` past this many hours since the newest DB dump. */
export const DEFAULT_MAX_BACKUP_AGE_HOURS = 36;

// ---------------------------------------------------------------- naming ---
// tools/backup-db.sh   -> olive_<dbname>_<YYYYMMDDTHHMMSSZ>.dump
// tools/backup-media.sh -> olive_media_<YYYYMMDDTHHMMSSZ>.tar.gz
// Either may carry a trailing `.enc` once encrypted. `.partial` files (an
// in-flight or failed dump) and anything else in the directory are NEVER
// parsed as backups and therefore NEVER pruned.
const NAME_RE = /^olive_(.+)_(\d{8}T\d{6}Z)\.(dump|tar\.gz)(\.enc)?$/;

/** @returns {{kind:'db'|'media', label:string, ts:Date, encrypted:boolean, name:string}|null} */
export function parseBackupName(name) {
  const m = NAME_RE.exec(name);
  if (!m) return null;
  const [, middle, stamp, ext, enc] = m;
  const kind = ext === 'tar.gz' ? (middle === 'media' ? 'media' : null) : 'db';
  if (!kind) return null;
  const iso = `${stamp.slice(0, 4)}-${stamp.slice(4, 6)}-${stamp.slice(6, 8)}T` +
              `${stamp.slice(9, 11)}:${stamp.slice(11, 13)}:${stamp.slice(13, 15)}Z`;
  const ts = new Date(iso);
  if (Number.isNaN(ts.getTime())) return null;
  return { kind, label: middle, ts, encrypted: Boolean(enc), name };
}

export function listBackups(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).map(parseBackupName).filter(Boolean)
    .sort((a, b) => b.ts - a.ts); // newest first
}

// -------------------------------------------------------------- retention ---
const dayKey = (d) => d.toISOString().slice(0, 10);
function isoWeekKey(d) {
  // ISO-8601 week-year + week number, computed in UTC.
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dow = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - dow);
  const yearStart = Date.UTC(t.getUTCFullYear(), 0, 1);
  const week = Math.ceil((((t - yearStart) / 86400000) + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

/**
 * 7 daily + 4 weekly retention (GFS-style), per backup FAMILY -- kind plus
 * database name, so a database dump, a media archive, or a second database in
 * the same directory are each pruned independently of one another:
 *   - daily : the NEWEST backup of each of the `daily` most recent UTC days
 *             that HAVE a backup;
 *   - weekly: the NEWEST backup of each of the `weekly` most recent ISO weeks
 *             that have one;
 *   - always: the single newest backup of the family.
 * Everything else of that kind is pruned. "Days/weeks that have a backup",
 * not "calendar days back from now", is deliberate: if the scheduler was down
 * for ten days, counting calendar windows would delete every older backup
 * the moment it came back -- exactly when they matter most. Counting only
 * days that have one means an outage never shortens retention.
 *
 * @param {ReturnType<typeof parseBackupName>[]} files (any order)
 * @returns {{ keep: string[], prune: string[] }}
 */
export function planRetention(files, { daily = DEFAULT_DAILY_KEEP, weekly = DEFAULT_WEEKLY_KEEP } = {}) {
  const keep = new Set();
  const families = [...new Set(files.map((f) => `${f.kind}|${f.label}`))];
  for (const family of families) {
    const ofKind = files.filter((f) => `${f.kind}|${f.label}` === family).sort((a, b) => b.ts - a.ts);
    if (!ofKind.length) continue;
    keep.add(ofKind[0].name);
    const days = new Set(), weeks = new Set();
    for (const f of ofKind) { // newest first, so the first seen per key IS the newest
      const dk = dayKey(f.ts), wk = isoWeekKey(f.ts);
      if (!days.has(dk) && days.size < daily) { days.add(dk); keep.add(f.name); }
      if (!weeks.has(wk) && weeks.size < weekly) { weeks.add(wk); keep.add(f.name); }
    }
  }
  return { keep: [...keep], prune: files.map((f) => f.name).filter((n) => !keep.has(n)) };
}

/** Deletes whatever planRetention() says to prune from `dir`. Returns the plan. */
export function pruneBackups(dir, opts = {}) {
  const plan = planRetention(listBackups(dir), opts);
  if (!opts.dryRun) for (const name of plan.prune) unlinkSync(join(dir, name));
  return plan;
}

// ------------------------------------------------------------------ alarm ---
/**
 * Hours since the newest backup of `kind` in `dir` (Infinity if none / dir
 * missing). An encrypted `.enc` file counts: it is the backup.
 */
export function newestBackupAgeHours(dir, now = Date.now(), kind = 'db') {
  const newest = listBackups(dir).find((f) => f.kind === kind);
  return newest ? (now - newest.ts.getTime()) / 3_600_000 : Infinity;
}

/**
 * The stale-backup check health-alert.mjs runs. `BACKUP_DIR` unset means "this
 * deployment has not configured automatic backups": no alarm (a dev machine or
 * CI database must not page about a backup it never promised). Set means "I
 * expect backups here": a missing or too-old newest dump IS the alarm.
 * @returns {null | { checkName: string, severity: string, observed: string, threshold: number, meaning: string }}
 */
export function staleBackupAlarm(env = process.env, now = Date.now()) {
  const dir = env.BACKUP_DIR;
  if (!dir) return null;
  const max = Number(env.BACKUP_MAX_AGE_HOURS);
  const threshold = Number.isFinite(max) && max > 0 ? max : DEFAULT_MAX_BACKUP_AGE_HOURS;
  const age = newestBackupAgeHours(dir, now, 'db');
  if (age <= threshold) return null;
  return {
    checkName: 'backup_stale', severity: 'high',
    observed: age === Infinity ? 'never' : age.toFixed(1), threshold,
    meaning: age === Infinity
      ? `No database backup exists in ${dir}. Backups are configured (BACKUP_DIR is set) but none has ever completed.`
      : `The newest database backup in ${dir} is ${age.toFixed(1)} hours old (limit ${threshold}). The scheduler's backup job has stopped succeeding.`,
  };
}

// ------------------------------------------------------------- encryption ---
// File format: "OLVB1" | salt(16) | iv(12) | AES-256-GCM ciphertext | tag(16).
// Key = scrypt(passphrase, salt). Node's own crypto: no extra dependency, and
// nothing about the passphrase is stored anywhere -- lose it and the backup is
// unreadable, by design (docs/backup-and-restore.md says so).
const MAGIC = Buffer.from('OLVB1');

export async function encryptFile(src, dst, passphrase) {
  if (!passphrase) throw new Error('encryptFile: passphrase required');
  const salt = randomBytes(16), iv = randomBytes(12);
  const key = await scryptAsync(passphrase, salt, 32);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const tmp = `${dst}.partial`;
  const out = createWriteStream(tmp);
  out.write(Buffer.concat([MAGIC, salt, iv]));
  await pipeline(createReadStream(src), cipher, out, { end: false });
  await new Promise((resolve, reject) => out.end(cipher.getAuthTag(), (e) => (e ? reject(e) : resolve())));
  renameSync(tmp, dst);
}

export async function decryptFile(src, dst, passphrase) {
  if (!passphrase) throw new Error('decryptFile: passphrase required');
  const size = statSync(src).size;
  const headLen = MAGIC.length + 16 + 12;
  if (size < headLen + 16) throw new Error('decryptFile: file too short to be an encrypted backup');
  const { open } = await import('node:fs/promises');
  const fh = await open(src, 'r');
  let head, tag;
  try {
    head = Buffer.alloc(headLen); await fh.read(head, 0, headLen, 0);
    tag = Buffer.alloc(16); await fh.read(tag, 0, 16, size - 16);
  } finally { await fh.close(); }
  if (!head.subarray(0, MAGIC.length).equals(MAGIC)) throw new Error('decryptFile: not an Olive Branch encrypted backup');
  const salt = head.subarray(MAGIC.length, MAGIC.length + 16);
  const iv = head.subarray(MAGIC.length + 16, headLen);
  const key = await scryptAsync(passphrase, salt, 32);
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const tmp = `${dst}.partial`;
  try {
    await pipeline(createReadStream(src, { start: headLen, end: size - 17 }), decipher, createWriteStream(tmp));
  } catch (e) {
    try { unlinkSync(tmp); } catch { /* nothing partial to remove */ }
    throw new Error('decryptFile: wrong passphrase or corrupted/tampered backup');
  }
  renameSync(tmp, dst);
}
