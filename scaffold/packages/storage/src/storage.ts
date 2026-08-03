import { createHash, randomBytes } from 'node:crypto';

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
  get size() { return this.m.size; }
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
  rowsDeleted: number;
  tombstoned: string[];      // blob delete failed; retry required
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
    examined: 0, blobsDeleted: 0, rowsDeleted: 0,
    tombstoned: [], skippedPreserved: 0, refusedNoClock: 0,
  };
  const candidates = await db.dueForReaping(now, limit);

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
      await storage.delete(c.storageKey);
      out.blobsDeleted++;
    } catch (e) {
      out.tombstoned.push(c.artifactId);
      await db.tombstone(c.artifactId, c.storageKey,
        e instanceof Error ? e.message : String(e));
      continue;                 // row survives so the blob stays discoverable
    }
    if (await db.deleteArtifactRow(c.artifactId)) out.rowsDeleted++;
  }
  return out;
}
