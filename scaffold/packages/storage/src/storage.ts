import { createHash, randomBytes } from 'node:crypto';
import { promises as fsp } from 'node:fs';
import * as path from 'node:path';

/**
 * MASTERFILE §10.1, §5.6 — object storage and the retention reaper.
 *
 * §20.2 recorded this as a live COPPA exposure: `expires_at` currently expires a
 * database row while the blob lives forever. Under the amended Rule the blob IS
 * the regulated personal information — voiceprints, face templates, audio. A
 * reaper that deletes rows and leaves media is not a retention policy.
 */

export interface StoragePort {
  put(key: string, bytes: Buffer): Promise<{ key: string; etag: string }>;
  get(key: string): Promise<Buffer | null>;
  delete(key: string): Promise<boolean>;   // true if it existed
  exists(key: string): Promise<boolean>;
  /** Short-lived, single-key, read-only. */
  signedUrl(key: string, ttlSeconds: number, now: number): string;
  list(prefix: string): Promise<string[]>;
  /**
   * The real counterpart to signedUrl() — verifies a signature MINTED BY
   * THIS SAME INSTANCE (against its own internal secret) rather than
   * exposing the secret itself for an external caller to check by hand.
   * The signature already cryptographically binds the exact key string
   * (verifySignedUrl()'s own comment: "a valid signature for one object
   * cannot be replayed against another") — for a key namespaced
   * `children/<childId>/messages/<uuid>` (server/routes.mjs's own real
   * convention), that means the childId segment is already covered by the
   * signature, with no separate childId-binding needed.
   */
  verifySignedKey(
    key: string, expiresAt: number, sig: string, now: number,
  ): { ok: true } | { ok: false; reason: 'expired' | 'bad_signature' };
}

/** §11 — signed URLs are minutes, not hours; a leaked URL is a leaked child. */
export const SIGNED_URL_TTL_SECONDS = 300;

export function signKey(secret: Buffer, key: string, expiresAt: number): string {
  return createHash('sha256')
    .update(secret).update('\u0000').update(key).update('\u0000')
    .update(String(expiresAt)).digest('base64url');
}

export function verifySignedUrl(
  secret: Buffer, key: string, expiresAt: number, sig: string, now: number,
): { ok: true } | { ok: false; reason: 'expired' | 'bad_signature' } {
  if (expiresAt * 1000 <= now) return { ok: false, reason: 'expired' };
  const want = signKey(secret, key, expiresAt);
  // Signature binds the KEY as well as the expiry, so a valid signature for one
  // object cannot be replayed against another.
  if (want.length !== sig.length) return { ok: false, reason: 'bad_signature' };
  let diff = 0;
  for (let i = 0; i < want.length; i++) diff |= want.charCodeAt(i) ^ sig.charCodeAt(i);
  return diff === 0 ? { ok: true } : { ok: false, reason: 'bad_signature' };
}

/** In-memory adapter for tests. A filesystem/S3 adapter implements the same port. */
export class MemoryStorage implements StoragePort {
  private m = new Map<string, Buffer>();
  constructor(private secret: Buffer = randomBytes(32)) {}
  async put(key: string, bytes: Buffer) {
    this.m.set(key, bytes);
    return { key, etag: createHash('md5').update(bytes).digest('hex') };
  }
  async get(key: string) { return this.m.get(key) ?? null; }
  async delete(key: string) { return this.m.delete(key); }
  async exists(key: string) { return this.m.has(key); }
  async list(prefix: string) { return [...this.m.keys()].filter(k => k.startsWith(prefix)); }
  signedUrl(key: string, ttlSeconds: number, now: number) {
    const exp = Math.floor(now / 1000) + ttlSeconds;
    return `/media/${encodeURIComponent(key)}?exp=${exp}&sig=${signKey(this.secret, key, exp)}`;
  }
  verifySignedKey(key: string, expiresAt: number, sig: string, now: number) {
    return verifySignedUrl(this.secret, key, expiresAt, sig, now);
  }
  get size() { return this.m.size; }
}

/**
 * Filesystem-backed adapter — the "filesystem/S3 adapter" MemoryStorage's own
 * docstring above named as the intended next implementer of this port. Real,
 * not test-only: bytes actually land on disk, `get()` actually reads them
 * back, `delete()` actually removes them. Meant for self-hosted deployment,
 * where the app owns a local or mounted volume rather than a cloud account.
 *
 * A cloud provider (S3/GCS/Azure Blob) still needs a real account and real
 * credentials, neither of which exist in this environment — see MASTERFILE
 * §20.2b. This does not pretend to be that; it closes the narrower, honest
 * half of the gap: `StoragePort` having exactly one implementation
 * (MemoryStorage), and that implementation being explicitly test-only.
 */
export class FilesystemStorage implements StoragePort {
  constructor(private root: string, private secret: Buffer = randomBytes(32)) {}

  /**
   * A storage key is built from artifact ids elsewhere in the system, not
   * typed by a stranger — but a path-traversal key (`../../etc/passwd`)
   * reaching this far would be a severe bug, not a remote attack, and the
   * cost of checking is one `path.relative` call. Refuse rather than trust.
   */
  private resolve(key: string): string {
    const full = path.join(this.root, key);
    const rel = path.relative(this.root, full);
    if (rel.startsWith('..') || path.isAbsolute(rel)) {
      throw new Error(`storage key escapes root: ${key}`);
    }
    return full;
  }

  async put(key: string, bytes: Buffer) {
    const full = this.resolve(key);
    await fsp.mkdir(path.dirname(full), { recursive: true });
    await fsp.writeFile(full, bytes);
    return { key, etag: createHash('md5').update(bytes).digest('hex') };
  }

  async get(key: string) {
    try {
      return await fsp.readFile(this.resolve(key));
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'ENOENT') return null;
      throw e;
    }
  }

  async delete(key: string) {
    try {
      await fsp.unlink(this.resolve(key));
      return true;
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'ENOENT') return false;
      throw e;
    }
  }

  async exists(key: string) {
    try {
      await fsp.access(this.resolve(key));
      return true;
    } catch {
      return false;
    }
  }

  async list(prefix: string) {
    const out: string[] = [];
    const walk = async (dir: string) => {
      let entries: import('node:fs').Dirent[];
      try {
        entries = await fsp.readdir(dir, { withFileTypes: true });
      } catch {
        return; // root not created yet — an empty store, not an error
      }
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) await walk(full);
        else {
          const rel = path.relative(this.root, full).split(path.sep).join('/');
          if (rel.startsWith(prefix)) out.push(rel);
        }
      }
    };
    await walk(this.root);
    return out.sort();
  }

  signedUrl(key: string, ttlSeconds: number, now: number) {
    const exp = Math.floor(now / 1000) + ttlSeconds;
    return `/media/${encodeURIComponent(key)}?exp=${exp}&sig=${signKey(this.secret, key, exp)}`;
  }
  verifySignedKey(key: string, expiresAt: number, sig: string, now: number) {
    return verifySignedUrl(this.secret, key, expiresAt, sig, now);
  }
}

// Retention policy lives in `retention.ts` — it must not require a Node runtime.
export * from './retention.ts';

// ------------------------------------------------------------------- reaper --
export interface ReapCandidate {
  artifactId: string;
  storageKey: string;
  preserved: boolean;
  expiresAt: string | null;
}

export interface ReapResult {
  examined: number;
  blobsDeleted: number;
  // storage.delete() returned false (its own "true if it existed"
  // contract) rather than throwing — the blob was already gone, so the row
  // is still safely deleted below, but this is recorded SEPARATELY from
  // blobsDeleted rather than silently merged into it: a real spike here is
  // itself an operational signal (e.g. this process was pointed at the
  // wrong storage root, the exact bug this project's own post-tier audit
  // found and fixed in both docker-compose files), not proof retention
  // worked. See reap()'s own loop body for where this is set.
  blobsAlreadyGone: number;
  rowsDeleted: number;
  tombstoned: string[];      // blob delete failed OR row delete failed
                             // after a successful/no-op blob delete; retry
                             // required either way — see reap()'s own body.
  skippedPreserved: number;
  refusedNoClock: number;
}

export interface ReaperDb {
  dueForReaping(now: Date, limit: number): Promise<ReapCandidate[]>;
  deleteArtifactRow(id: string): Promise<boolean>;
  tombstone(id: string, key: string, error: string): Promise<void>;
}

/**
 * ORDER IS THE WHOLE DESIGN: blob first, then row.
 *
 * Row first, then blob:  if the blob delete fails you have media containing a
 *   child's face and voice in storage with **no record that it exists** — an
 *   undiscoverable COPPA violation. Nothing will ever retry it.
 *
 * Blob first, then row:  if the row delete fails you have a row pointing at
 *   nothing. Recoverable, visible, and already detected by `orphan_risk`.
 *
 * Both orders have a failure mode. Only one of them is discoverable.
 */
export async function reap(
  db: ReaperDb, storage: StoragePort, now: Date, limit = 500,
): Promise<ReapResult> {
  const out: ReapResult = {
    examined: 0, blobsDeleted: 0, blobsAlreadyGone: 0, rowsDeleted: 0,
    tombstoned: [], skippedPreserved: 0, refusedNoClock: 0,
  };
  const candidates = await db.dueForReaping(now, limit);

  // Best-effort tombstone write — used on BOTH failure paths below. Never
  // allowed to itself throw: this function's whole point is that one bad
  // candidate must not stop the rest of the batch from being examined, and
  // a tombstone write failing on top of an already-failed delete is
  // exactly the kind of compounding failure that must degrade to "retried
  // next sweep," not "the rest of tonight's 500 candidates are never
  // looked at."
  const tombstoneBestEffort = async (id: string, key: string, reason: string) => {
    out.tombstoned.push(id);
    try { await db.tombstone(id, key, reason); } catch { /* retried next sweep */ }
  };

  for (const c of candidates) {
    out.examined++;

    // Belt and braces over the §5.6 CHECK. A preserved artifact has no clock and
    // must never be reaped — it is the child's, pending the §9.8.4 handover.
    if (c.preserved) { out.skippedPreserved++; continue; }

    // A candidate with no expiry should be unrepresentable. If one appears, the
    // CHECK has been dropped or bypassed: refuse rather than guess.
    if (!c.expiresAt) { out.refusedNoClock++; continue; }
    if (new Date(c.expiresAt) > now) { continue; }

    try {
      // storage.delete()'s own contract: resolves `true` if a blob existed
      // and was deleted, `false` if it never existed, THROWS on a real I/O
      // failure. The boolean is real signal, not noise — see
      // blobsAlreadyGone's own doc comment on ReapResult.
      const existed = await storage.delete(c.storageKey);
      if (existed) out.blobsDeleted++; else out.blobsAlreadyGone++;
    } catch (e) {
      await tombstoneBestEffort(c.artifactId, c.storageKey,
        e instanceof Error ? e.message : String(e));
      continue;                 // row survives so the blob stays discoverable
    }

    try {
      if (await db.deleteArtifactRow(c.artifactId)) out.rowsDeleted++;
    } catch (e) {
      // Found by this project's own post-tier audit: this call used to be
      // unguarded. The blob is ALREADY gone at this point (the try block
      // above either deleted it or found it already gone), so a failed row
      // delete here leaves a row pointing at nothing — it MUST be
      // discoverable the same way a failed blob delete already is (a real
      // reap_tombstone row), not a thrown exception that propagates out of
      // this whole loop. An unguarded throw here previously killed the
      // rest of the batch outright, and because the row survived
      // un-tombstoned, dueForReaping()'s own `ORDER BY expires_at` and its
      // `NOT EXISTS (SELECT 1 FROM reap_tombstone ...)` filter guaranteed
      // the SAME row would be returned first again on every future sweep —
      // a single transient failure could indefinitely block every other
      // family's overdue media behind it.
      await tombstoneBestEffort(c.artifactId, c.storageKey,
        `row delete failed after blob delete resolved: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  return out;
}
