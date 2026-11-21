// OLIVE BRANCH -- encrypted family backup: the SERVER half. MASTERFILE 7.22.
// db/migrations/0054_family_backup.sql has the tables, the row level security
// and the append-only triggers; server/backup_chain.mjs has the pure hashing and
// the reference client-side history check. This file is the logic between them.
//
// The server stores opaque ciphertext and the minimal metadata listed in
// MASTERFILE 7.22. It holds no key that opens a backup. Every function returns
// `{ status, body }` so the route layer (family_backup_routes.mjs) stays thin
// and the logic can be driven directly by the tests.
//
// Two locks on every path (the same split pairing and invites use):
//   1. here / the route: a guardian session on a DEVICE session, an ACTIVE
//      membership of the vault, the grown-up's own PIN for the sensitive acts;
//   2. the database: a guardian session can only reach its own vault's rows
//      (RLS), and triggers refuse to rewrite or delete committed backups.
// Writes to the access-control tables and to the restore state machine run as
// `system` inside ONE transaction behind the checks above, each with a
// compare-and-swap so two simultaneous requests cannot both win.
import { withSession, withSystemSession } from '../packages/db/src/pool.mjs';
import { createHash } from 'node:crypto';
import {
  GENESIS_CHAIN, sha256, hex32, b64, chainHash, restoreChallengeMessage, ed25519Verify,
  newToken, tokenDigest,
} from './backup_chain.mjs';

const MIB = 1024 * 1024;
const HOUR = 3600_000;
const DAY = 24 * HOUR;

function posInt(raw, fallback, min = 1) {
  const n = Number(raw);
  return Number.isFinite(n) && n >= min ? Math.floor(n) : fallback;
}

/** Policy knobs, read per call so an operator or a test can change them without a re-import. */
export function backupConfig(env = process.env) {
  return {
    quotaBytes: posInt(env.BACKUP_VAULT_QUOTA_BYTES, 512 * MIB),
    maxVersionBytes: posInt(env.BACKUP_MAX_VERSION_BYTES, 256 * MIB),
    keepVersions: Math.min(100, posInt(env.BACKUP_KEEP_VERSIONS, 10, 3)),
    recoveryWindowDays: Math.min(730, posInt(env.BACKUP_RECOVERY_WINDOW_DAYS, 180, 30)),
    maxChunkBytes: Math.min(MIB, posInt(env.BACKUP_MAX_CHUNK_BYTES, MIB, 1024)),
    maxChunks: 4096,
    uploadTtlHours: posInt(env.BACKUP_UPLOAD_TTL_HOURS, 168),
    // The waiting period. The 24 hour floor cannot be configured away.
    waitHoursWithApprover: posInt(env.BACKUP_RESTORE_WAIT_HOURS, 48, 24),
    waitHoursSolo: posInt(env.BACKUP_RESTORE_WAIT_HOURS_SOLO, 72, 24),
    helperSettleHours: posInt(env.BACKUP_HELPER_SETTLE_HOURS, 24, 1),
    requestLifetimeDays: posInt(env.BACKUP_RESTORE_REQUEST_DAYS, 7),
    tokenTtlHours: posInt(env.BACKUP_RESTORE_TOKEN_HOURS, 24),
    maxTokenIssues: 5,
    maxTokenFailures: 10,
    challengeTtlMs: 5 * 60_000,
    maxVaultsPerUser: 3,
    maxMembers: 6,
    maxOpenUploads: 3,
    maxRequestsPerDevicePerDay: 3,
    maxChallengesPerDeviceHour: 10,
    maxRequestsPerVaultPerDay: 6,
  };
}

const err = (status, error, extra = {}) => ({ status, body: { error, ...extra } });
const ok = (body, status = 200) => ({ status, body });

// Plain adult words, chosen by the server from this fixed list. Never request input.
const SUMMARY = {
  vault_created: () => 'A family backup was set up.',
  member_joined: () => 'Another grown-up joined the family backup.',
  member_paused: () => 'A grown-up’s reach to the family backup was paused. It can be turned back on.',
  member_resumed: () => 'A grown-up’s reach to the family backup was turned back on.',
  helper_named: () => 'A trusted helper was named. They can only confirm a recovery.',
  helper_removed: () => 'The trusted helper was removed.',
  version_deleted: (d) => `A backup was set aside. It is kept for ${d} more days and can be brought back.`,
  version_restored: () => 'A backup that was set aside was brought back.',
  restore_requested: (h) => `Someone asked to restore the family backup onto a new phone. Nothing happens for ${h} hours. Anyone can cancel it.`,
  restore_approved: () => 'The restore was confirmed. The waiting period still applies.',
  restore_cancelled: () => 'The restore was cancelled. Nothing was restored.',
  restore_token_issued: () => 'The waiting period is over and the new phone may now fetch the backup.',
  restore_completed: () => 'The restore finished.',
  restore_expired: () => 'The restore request ran out of time. Nothing was restored.',
};
const RESTORE_KINDS = new Set(['restore_requested', 'restore_approved', 'restore_cancelled',
  'restore_token_issued', 'restore_completed', 'restore_expired']);

async function addEvent(q, vaultId, kind, actorId, arg, restoreId = null) {
  await q(
    `INSERT INTO backup_vault_event (vault_id, scope, kind, actor_user, restore_id, summary)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [vaultId, RESTORE_KINDS.has(kind) ? 'restore' : 'vault', kind, actorId, restoreId, SUMMARY[kind](arg)]);
}

const guardianSession = (userId) => ({ roleName: 'guardian', userId, childId: null });
const asGuardian = (pool, userId, fn) => withSession(pool, guardianSession(userId), fn);

const num = (v) => (v === null || v === undefined ? null : Number(v));
const b64col = (c) => `translate(encode(${c}, 'base64'), E'\\n', '')`;
const VERSION_COLS = `v.seq, encode(v.prev_chain_hash, 'hex') AS prev_chain_hash,
  encode(v.chain_hash, 'hex') AS chain_hash, encode(v.blob_sha256, 'hex') AS blob_sha256,
  v.size_bytes, v.chunk_size, v.chunk_count, ${b64col('v.manifest')} AS manifest,
  ${b64col('v.signature')} AS signature, v.created_at, v.state, v.tombstone_reason,
  v.tombstoned_at, v.purge_after, v.purged_at`;
const versionOut = (r) => ({
  seq: num(r.seq), prevChainHash: r.prev_chain_hash, chainHash: r.chain_hash, blobSha256: r.blob_sha256,
  sizeBytes: num(r.size_bytes), chunkSize: r.chunk_size, chunkCount: r.chunk_count,
  manifest: r.manifest, signature: r.signature, createdAt: r.created_at, state: r.state,
  tombstoneReason: r.tombstone_reason ?? null, tombstonedAt: r.tombstoned_at ?? null,
  purgeAfter: r.purge_after ?? null, purged: r.purged_at != null,
});

/** The vault's newest version (any state), or the genesis position. */
async function headOf(q, vaultId) {
  const r = await q(
    `SELECT seq, encode(chain_hash, 'hex') AS chain_hash FROM backup_version
      WHERE vault_id = $1 ORDER BY seq DESC LIMIT 1`, [vaultId]);
  return r.length
    ? { seq: Number(r[0].seq), chainHash: r[0].chain_hash }
    : { seq: 0, chainHash: GENESIS_CHAIN.toString('hex') };
}

const lockVault = (q, vaultId) =>
  q(`SELECT pg_advisory_xact_lock(hashtext($1::text))`, [`olive-backup:${vaultId}`]);

/** Own membership of a vault: { state } or null. Inside a guardian session RLS already shows only own rows. */
async function myState(q, vaultId, userId) {
  const r = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, userId]);
  return r[0]?.state ?? null;
}

/**
 * Is this account still a grown-up of at least one child right now? A grown-up whose guardianship has
 * ended (a parent who was ended by the family) keeps no reach to the family's backup, whatever the
 * membership row says.
 */
async function stillAGuardian(q, userId) {
  const r = await q(
    `SELECT 1 FROM effective_guardianship WHERE user_id = $1 AND role = 'guardian' AND restricted = false LIMIT 1`, [userId]);
  return r.length > 0;
}

/** 404 for a stranger (never reveal that a vault exists), 403 for a paused member or one who is no longer a guardian. */
async function needActive(q, vaultId, userId) {
  const s = await myState(q, vaultId, userId);
  if (s === null) return err(404, 'vault_not_found');
  if (s === 'paused') return err(403, 'reach_paused');
  if (!(await stillAGuardian(q, userId))) return err(403, 'not_a_guardian');
  return null;
}

// ------------------------------------------------------------ space ----------
async function spaceUsed(q, vaultId, now) {
  // stored: the versions in use. setAside: tombstoned versions kept for their recovery window; they have
  // their OWN allowance (one more quota) so a family that fills its quota with live backups is never
  // forced to give up the recoverable ones, and a pile of set-aside copies never blocks a new backup.
  const r = await q(
    `SELECT
       (SELECT COALESCE(SUM(v.size_bytes), 0) FROM backup_version v
         WHERE v.vault_id = $1 AND v.state = 'live')::bigint AS stored,
       (SELECT COALESCE(SUM(v.size_bytes), 0) FROM backup_version v
         WHERE v.vault_id = $1 AND v.state = 'tombstone' AND v.purged_at IS NULL)::bigint AS set_aside,
       (SELECT COALESCE(SUM(size_bytes), 0) FROM backup_upload
         WHERE vault_id = $1 AND state = 'open' AND expires_at > $2)::bigint AS reserved`,
    [vaultId, now]);
  return { stored: Number(r[0].stored), setAside: Number(r[0].set_aside), reserved: Number(r[0].reserved) };
}

/**
 * Give back only what is expendable: bytes of uploads that never finished and
 * bytes of versions whose recovery window has ended. Everything else stays.
 * Runs as `system`; the triggers refuse anything not expendable anyway.
 */
export async function reclaimVault(pool, vaultId, now = new Date()) {
  return withSystemSession(pool, async (q) => {
    const exp = await q(
      `UPDATE backup_upload SET state = 'expired'
        WHERE vault_id = $1 AND state = 'open' AND expires_at <= $2 RETURNING id`, [vaultId, now]);
    const aborted = await q(`SELECT id FROM backup_upload WHERE vault_id = $1 AND state IN ('aborted','expired')`, [vaultId]);
    let freed = 0;
    for (const u of aborted) {
      const d = await q(`DELETE FROM backup_chunk WHERE upload_id = $1 RETURNING size_bytes`, [u.id]);
      freed += d.reduce((s, r) => s + r.size_bytes, 0);
    }
    const purged = await q(
      `UPDATE backup_version SET purged_at = now()
        WHERE vault_id = $1 AND state = 'tombstone' AND purged_at IS NULL AND purge_after <= now()
        RETURNING upload_id`, [vaultId]);
    for (const v of purged) {
      const d = await q(`DELETE FROM backup_chunk WHERE upload_id = $1 RETURNING size_bytes`, [v.upload_id]);
      freed += d.reduce((s, r) => s + r.size_bytes, 0);
    }
    return { expiredUploads: exp.length, purgedVersions: purged.length, freedBytes: freed };
  });
}

/** Every vault, for a scheduler tick. Returns the totals. */
export async function sweepBackups(pool, now = new Date()) {
  const ids = await withSystemSession(pool, (q) => q(`SELECT id FROM backup_vault`));
  const total = { vaults: ids.length, expiredUploads: 0, purgedVersions: 0, freedBytes: 0, expiredRestores: 0 };
  for (const { id } of ids) {
    const r = await reclaimVault(pool, id, now);
    total.expiredUploads += r.expiredUploads; total.purgedVersions += r.purgedVersions; total.freedBytes += r.freedBytes;
    total.expiredRestores += await withSystemSession(pool, async (q) => {
      const rows = await q(
        `UPDATE backup_restore_request SET state = 'expired', token_hash = NULL
          WHERE vault_id = $1 AND state = 'pending' AND expires_at <= $2 RETURNING id`, [id, now]);
      for (const x of rows) await addEvent(q, id, 'restore_expired', null, null, x.id);
      return rows.length;
    });
  }
  return total;
}

// ------------------------------------------------------------ vaults ---------
export async function createVault(pool, { userId, recoveryVerifier, now, cfg = backupConfig() }) {
  const verifier = hex32(recoveryVerifier);
  if (!verifier) return err(400, 'recovery_verifier_invalid');
  return withSystemSession(pool, async (q) => {
    const mine = await q(`SELECT count(*)::int AS n FROM backup_vault_member WHERE user_id = $1`, [userId]);
    if (mine[0].n >= cfg.maxVaultsPerUser) return err(409, 'too_many_vaults');
    // One backup per family: if another grown-up of this family already keeps one, join it instead of
    // starting a second (two vaults would split the family's history).
    const existing = await q(
      `SELECT m.vault_id
         FROM backup_vault_member m
         JOIN effective_guardianship theirs ON theirs.user_id = m.user_id
         JOIN effective_guardianship ours ON ours.child_id = theirs.child_id AND ours.user_id = $1
        WHERE m.state = 'active' AND theirs.role = 'guardian' AND ours.role = 'guardian'
          AND theirs.restricted = false AND ours.restricted = false
          AND m.user_id <> $1 LIMIT 1`, [userId]);
    if (existing.length) return err(409, 'join_existing_vault', { vaultId: existing[0].vault_id });
    const v = await q(
      `INSERT INTO backup_vault (created_by, recovery_verifier, quota_bytes, keep_versions, recovery_window_days, created_at)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
      [userId, verifier, cfg.quotaBytes, cfg.keepVersions, cfg.recoveryWindowDays, now]);
    const id = v[0].id;
    await q(`INSERT INTO backup_vault_member (vault_id, user_id, joined_at) VALUES ($1, $2, $3)`, [id, userId, now]);
    await addEvent(q, id, 'vault_created', userId);
    return ok({ vaultId: id, quotaBytes: cfg.quotaBytes, keepVersions: cfg.keepVersions,
      recoveryWindowDays: cfg.recoveryWindowDays }, 201);
  });
}

export async function listVaults(pool, { userId }) {
  return withSystemSession(pool, async (q) => {
    const mine = await q(
      `SELECT m.vault_id, m.state FROM backup_vault_member m WHERE m.user_id = $1 ORDER BY m.joined_at`, [userId]);
    // Vaults a grown-up could join: an active member of the vault shares a live
    // guardian edge to one of the same children. Existence only; no content.
    const joinable = await q(
      `SELECT DISTINCT m.vault_id
         FROM backup_vault_member m
         JOIN effective_guardianship theirs ON theirs.user_id = m.user_id
         JOIN effective_guardianship ours ON ours.child_id = theirs.child_id AND ours.user_id = $1
        WHERE m.state = 'active' AND theirs.role = 'guardian' AND ours.role = 'guardian'
          AND theirs.restricted = false AND ours.restricted = false
          AND NOT EXISTS (SELECT 1 FROM backup_vault_member me WHERE me.vault_id = m.vault_id AND me.user_id = $1)`,
      [userId]);
    const helperOf = await q(
      `SELECT vault_id FROM backup_vault_helper WHERE user_id = $1 AND removed_at IS NULL`, [userId]);
    return ok({
      vaults: mine.map((r) => ({ vaultId: r.vault_id, state: r.state })),
      joinable: joinable.map((r) => ({ vaultId: r.vault_id })),
      helperFor: helperOf.map((r) => ({ vaultId: r.vault_id })),
    });
  });
}

export async function joinVault(pool, { userId, vaultId, now, cfg = backupConfig() }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const v = await q(`SELECT id FROM backup_vault WHERE id = $1`, [vaultId]);
    if (!v.length) return err(404, 'vault_not_found');
    const existing = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, userId]);
    if (existing.length) return ok({ vaultId, state: existing[0].state, alreadyMember: true });
    const mine = await q(`SELECT count(*)::int AS n FROM backup_vault_member WHERE user_id = $1`, [userId]);
    if (mine[0].n >= cfg.maxVaultsPerUser) return err(409, 'too_many_vaults');
    const members = await q(`SELECT count(*)::int AS n FROM backup_vault_member WHERE vault_id = $1`, [vaultId]);
    if (members[0].n >= cfg.maxMembers) return err(409, 'vault_full');
    const shared = await q(
      `SELECT 1
         FROM backup_vault_member m
         JOIN effective_guardianship theirs ON theirs.user_id = m.user_id
         JOIN effective_guardianship ours ON ours.child_id = theirs.child_id AND ours.user_id = $2
        WHERE m.vault_id = $1 AND m.state = 'active'
          AND theirs.role = 'guardian' AND ours.role = 'guardian'
          AND theirs.restricted = false AND ours.restricted = false LIMIT 1`, [vaultId, userId]);
    // The same answer as a vault that does not exist: a stranger learns nothing.
    if (!shared.length) return err(404, 'vault_not_found');
    await q(`INSERT INTO backup_vault_member (vault_id, user_id, joined_at) VALUES ($1, $2, $3)`, [vaultId, userId, now]);
    await addEvent(q, vaultId, 'member_joined', userId);
    // A helper is the safeguard for ONE grown-up. Once a second grown-up is in, that grown-up is the
    // safeguard, so the helper steps down (and the notice says so).
    const gone = await q(`UPDATE backup_vault_helper SET removed_at = $2, removed_by = NULL
                           WHERE vault_id = $1 AND removed_at IS NULL RETURNING id`, [vaultId, now]);
    if (gone.length) await addEvent(q, vaultId, 'helper_removed', userId);
    return ok({ vaultId, state: 'active', alreadyMember: false }, 201);
  });
}

function restoreOut(r, now) {
  let phase = r.state;
  if (r.state === 'pending') {
    if (now >= new Date(r.expires_at)) phase = 'expired';
    else if (r.token_hash && r.token_expires_at && now < new Date(r.token_expires_at)) phase = 'token_issued';
    else if (now < new Date(r.not_before)) phase = 'waiting';
    else if (r.approval_required && !r.approved_at) phase = 'needs_yes';
    else phase = 'ready';
  }
  return {
    restoreId: r.id, phase, requestedAt: r.created_at, notBefore: r.not_before, expiresAt: r.expires_at,
    waitHours: r.wait_hours, approvalRequired: r.approval_required,
    approved: r.approved_at != null, approvedAt: r.approved_at ?? null,
    approverKind: r.approver_kind ?? null, cancelledAt: r.cancelled_at ?? null,
    completedAt: r.completed_at ?? null, requestedByName: r.requested_by_name ?? null,
  };
}
const RESTORE_COLS = `r.id, r.created_at, r.wait_hours, r.not_before, r.approval_required, r.approved_at,
  r.approver_kind, r.expires_at, r.state, r.cancelled_at, r.completed_at, r.token_hash, r.token_expires_at,
  (SELECT display_name FROM app_user u WHERE u.id = r.requested_by) AS requested_by_name`;

export async function vaultStatus(pool, { userId, vaultId, now }) {
  const base = await asGuardian(pool, userId, async (q) => {
    const state = await myState(q, vaultId, userId);
    if (state === null) return err(404, 'vault_not_found');
    const restores = await q(
      `SELECT ${RESTORE_COLS} FROM backup_restore_request r
        WHERE r.vault_id = $1 AND r.state = 'pending' ORDER BY r.created_at DESC LIMIT 1`, [vaultId]);
    const pending = restores.length ? restoreOut(restores[0], now) : null;
    if (state === 'paused') {
      // A paused grown-up sees that they are paused and any restore (so they can cancel it); nothing else.
      return ok({ vaultId, me: { state }, pendingRestore: pending });
    }
    const [vault] = await q(
      `SELECT quota_bytes, keep_versions, recovery_window_days, created_at FROM backup_vault WHERE id = $1`, [vaultId]);
    const head = await headOf(q, vaultId);
    const counts = await q(
      `SELECT count(*) FILTER (WHERE state = 'live')::int AS live,
              count(*) FILTER (WHERE state = 'tombstone')::int AS tombstones
         FROM backup_version WHERE vault_id = $1`, [vaultId]);
    const lastLive = await q(
      `SELECT created_at FROM backup_version WHERE vault_id = $1 AND state = 'live' ORDER BY seq DESC LIMIT 1`, [vaultId]);
    const sp = await spaceUsed(q, vaultId, now);
    return ok({
      vaultId, me: { state },
      head: head.seq ? { seq: head.seq, chainHash: head.chainHash } : null,
      liveVersions: counts[0].live, tombstones: counts[0].tombstones,
      lastBackupAt: lastLive[0]?.created_at ?? null,
      quotaBytes: Number(vault.quota_bytes), usedBytes: sp.stored + sp.reserved, setAsideBytes: sp.setAside,
      keepVersions: vault.keep_versions, recoveryWindowDays: vault.recovery_window_days,
      pendingRestore: pending,
    });
  });
  if (base.status !== 200 || base.body.me.state === 'paused') return base;
  // Members and the helper are listed by a system read, behind the membership check above.
  const extra = await withSystemSession(pool, async (q) => {
    const members = await q(
      `SELECT m.user_id, m.state, u.display_name FROM backup_vault_member m JOIN app_user u ON u.id = m.user_id
        WHERE m.vault_id = $1 ORDER BY m.joined_at`, [vaultId]);
    const helper = await q(
      `SELECT h.user_id, h.named_at, u.display_name FROM backup_vault_helper h JOIN app_user u ON u.id = h.user_id
        WHERE h.vault_id = $1 AND h.removed_at IS NULL`, [vaultId]);
    return { members, helper };
  });
  base.body.members = extra.members.map((m) => ({ userId: m.user_id, displayName: m.display_name, state: m.state }));
  base.body.helper = extra.helper.length
    ? { userId: extra.helper[0].user_id, displayName: extra.helper[0].display_name, namedAt: extra.helper[0].named_at }
    : null;
  return base;
}

// ----------------------------------------------------------- uploads ---------
export async function beginUpload(pool, { userId, deviceId, vaultId, body, now, cfg = backupConfig() }) {
  const b = body ?? {};
  const clientRef = typeof b.clientRef === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(b.clientRef) ? b.clientRef : null;
  const blobSha = hex32(b.blobSha256);
  const prevChain = hex32(b.prevChainHash);
  const claimedChain = hex32(b.chainHash);
  const manifest = b64(b.manifest, 1, 4096);
  const signature = b64(b.signature, 16, 512);
  const size = Number(b.sizeBytes);
  const chunkSize = Number(b.chunkSize);
  const baseSeq = Number(b.baseSeq);
  if (!clientRef || !blobSha || !prevChain || !claimedChain || !manifest || !signature
      || !Number.isSafeInteger(size) || size < 1 || !Number.isSafeInteger(chunkSize)
      || !Number.isSafeInteger(baseSeq) || baseSeq < 0) {
    return err(400, 'invalid_upload');
  }
  if (chunkSize < 1024 || chunkSize > cfg.maxChunkBytes) return err(400, 'invalid_chunk_size', { maxChunkBytes: cfg.maxChunkBytes });
  if (size > cfg.maxVersionBytes) return err(413, 'backup_too_large', { maxBytes: cfg.maxVersionBytes });
  const chunkCount = Math.ceil(size / chunkSize);
  if (chunkCount > cfg.maxChunks) return err(400, 'too_many_chunks', { maxChunks: cfg.maxChunks });
  const seq = baseSeq + 1;
  const want = chainHash({ vaultId, seq, prevChain, blobSha256: blobSha, size, manifest });
  if (want.compare(claimedChain) !== 0) return err(422, 'chain_mismatch');

  const attempt = async () => asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    await lockVault(q, vaultId);
    const [vault] = await q(`SELECT quota_bytes FROM backup_vault WHERE id = $1`, [vaultId]);
    // idempotent: the phone's own id for this attempt (a lost response leaves no second upload behind)
    const prior = await q(
      `SELECT id, state, base_seq, size_bytes, chunk_size, chunk_count, encode(blob_sha256,'hex') AS blob_sha256,
              encode(chain_hash,'hex') AS chain_hash, expires_at
         FROM backup_upload WHERE vault_id = $1 AND device_id = $2 AND client_ref = $3`, [vaultId, deviceId, clientRef]);
    if (prior.length) {
      const p = prior[0];
      if (Number(p.base_seq) !== baseSeq || Number(p.size_bytes) !== size || p.blob_sha256 !== blobSha.toString('hex')
          || p.chain_hash !== claimedChain.toString('hex') || p.chunk_size !== chunkSize) {
        return err(409, 'client_ref_reused');
      }
      // an attempt that ended (aborted or ran out of time) is over: the phone starts a new one under a new id
      if (p.state === 'aborted' || p.state === 'expired' || (p.state === 'open' && new Date(p.expires_at) <= now)) {
        return err(409, 'client_ref_finished', { state: p.state === 'open' ? 'expired' : p.state });
      }
      return ok({ uploadId: p.id, state: p.state, seq, chunkSize: p.chunk_size, chunkCount: p.chunk_count,
        expiresAt: p.expires_at, resumed: true });
    }
    const head = await headOf(q, vaultId);
    if (head.seq !== baseSeq || head.chainHash !== prevChain.toString('hex')) {
      return err(409, 'head_moved', { headSeq: head.seq, headChainHash: head.chainHash });
    }
    const open = await q(`SELECT count(*)::int AS n FROM backup_upload WHERE vault_id = $1 AND state = 'open' AND expires_at > $2`, [vaultId, now]);
    if (open[0].n >= cfg.maxOpenUploads) return err(429, 'too_many_uploads');
    const sp = await spaceUsed(q, vaultId, now);
    const quota = Number(vault.quota_bytes);
    // The newest versions in use plus anything still uploading must fit the quota; the copies set aside
    // for the recovery window have their own allowance of the same size, so they never crowd out a backup.
    if (sp.stored + sp.reserved + size > quota || sp.setAside > quota) {
      return { status: 507, body: { error: 'quota_exceeded', quotaBytes: quota, usedBytes: sp.stored + sp.reserved,
        setAsideBytes: sp.setAside }, retryAfterReclaim: true };
    }
    const u = await q(
      `INSERT INTO backup_upload (vault_id, user_id, device_id, client_ref, base_seq, seq, size_bytes, chunk_size, chunk_count,
                                  blob_sha256, prev_chain_hash, chain_hash, manifest, signature, created_at, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16) RETURNING id, expires_at`,
      [vaultId, userId, deviceId, clientRef, baseSeq, seq, size, chunkSize, chunkCount, blobSha, prevChain, claimedChain,
        manifest, signature, now, new Date(now.getTime() + cfg.uploadTtlHours * HOUR)]);
    return ok({ uploadId: u[0].id, state: 'open', seq, chunkSize, chunkCount, expiresAt: u[0].expires_at, resumed: false }, 201);
  });

  let r = await attempt();
  if (r.retryAfterReclaim) {
    // Only expendable bytes are ever given back (unfinished uploads, versions past their recovery window).
    await reclaimVault(pool, vaultId, now);
    r = await attempt();
  }
  if (r.retryAfterReclaim) delete r.retryAfterReclaim;
  return r;
}

/** Load an upload this DEVICE began, still open and unexpired. */
async function ownOpenUpload(q, { vaultId, uploadId, deviceId, now }) {
  const r = await q(
    `SELECT id, device_id, state, size_bytes, chunk_size, chunk_count, expires_at, seq, base_seq
       FROM backup_upload WHERE id = $1 AND vault_id = $2`, [uploadId, vaultId]);
  if (!r.length) return { fail: err(404, 'upload_not_found') };
  const u = r[0];
  if (u.device_id !== deviceId) return { fail: err(403, 'not_your_upload') };
  return { u };
}

export async function putChunk(pool, { userId, deviceId, vaultId, uploadId, index, body, now, cfg = backupConfig() }) {
  const idx = Number(index);
  if (!Number.isSafeInteger(idx) || idx < 0) return err(400, 'invalid_chunk');
  const data = b64(body?.data, 1, cfg.maxChunkBytes);
  const claimed = hex32(body?.sha256);
  if (!data || !claimed) return err(400, 'invalid_chunk');
  if (sha256(data).compare(claimed) !== 0) return err(422, 'chunk_hash_mismatch');
  return asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    const { u, fail } = await ownOpenUpload(q, { vaultId, uploadId, deviceId, now });
    if (fail) return fail;
    if (u.state !== 'open') return err(409, `upload_${u.state}`);
    if (new Date(u.expires_at) <= now) return err(410, 'upload_expired');
    if (idx >= u.chunk_count) return err(400, 'invalid_chunk');
    const expected = idx === u.chunk_count - 1 ? Number(u.size_bytes) - u.chunk_size * (u.chunk_count - 1) : u.chunk_size;
    if (data.length !== expected) return err(400, 'chunk_wrong_size', { expected });
    const ins = await q(
      `INSERT INTO backup_chunk (upload_id, idx, vault_id, size_bytes, sha256, data)
       VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (upload_id, idx) DO NOTHING RETURNING idx`,
      [uploadId, idx, vaultId, data.length, claimed, data]);
    if (ins.length) return ok({ index: idx, stored: true, already: false });
    const have = await q(`SELECT encode(sha256,'hex') AS h FROM backup_chunk WHERE upload_id = $1 AND idx = $2`, [uploadId, idx]);
    if (have[0]?.h === claimed.toString('hex')) return ok({ index: idx, stored: true, already: true });
    return err(409, 'chunk_conflict');
  });
}

export async function uploadStatus(pool, { userId, deviceId, vaultId, uploadId, now }) {
  return asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    const { u, fail } = await ownOpenUpload(q, { vaultId, uploadId, deviceId, now });
    if (fail) return fail;
    const got = await q(`SELECT idx FROM backup_chunk WHERE upload_id = $1 ORDER BY idx`, [uploadId]);
    return ok({
      uploadId, state: u.state, seq: Number(u.seq), baseSeq: Number(u.base_seq),
      chunkSize: u.chunk_size, chunkCount: u.chunk_count, sizeBytes: Number(u.size_bytes),
      expiresAt: u.expires_at, received: got.map((r) => r.idx),
      missing: Array.from({ length: u.chunk_count }, (_, i) => i).filter((i) => !got.some((g) => g.idx === i)).slice(0, 4096),
    });
  });
}

export async function abortUpload(pool, { userId, deviceId, vaultId, uploadId, now }) {
  const r = await asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    const { u, fail } = await ownOpenUpload(q, { vaultId, uploadId, deviceId, now });
    if (fail) return fail;
    if (u.state === 'committed') return err(409, 'upload_committed');
    if (u.state === 'open') await q(`UPDATE backup_upload SET state = 'aborted' WHERE id = $1 AND state = 'open'`, [uploadId]);
    return ok({ uploadId, state: 'aborted' });
  });
  if (r.status === 200) await reclaimVault(pool, vaultId, now);
  return r;
}

export async function commitUpload(pool, { userId, deviceId, vaultId, uploadId, now }) {
  return asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    await lockVault(q, vaultId);
    const r = await q(
      `SELECT id, device_id, state, seq, base_seq, size_bytes, chunk_size, chunk_count, expires_at,
              blob_sha256, prev_chain_hash, chain_hash, manifest, signature
         FROM backup_upload WHERE id = $1 AND vault_id = $2`, [uploadId, vaultId]);
    if (!r.length) return err(404, 'upload_not_found');
    const u = r[0];
    if (u.device_id !== deviceId) return err(403, 'not_your_upload');
    if (u.state === 'committed') {
      const v = await q(`SELECT ${VERSION_COLS} FROM backup_version v WHERE v.upload_id = $1`, [uploadId]);
      return ok({ version: versionOut(v[0]), tombstoned: [], alreadyCommitted: true });
    }
    if (u.state !== 'open') return err(409, `upload_${u.state}`);
    if (new Date(u.expires_at) <= now) return err(410, 'upload_expired');

    const head = await headOf(q, vaultId);
    if (head.seq !== Number(u.base_seq) || head.chainHash !== u.prev_chain_hash.toString('hex')) {
      return err(409, 'head_moved', { headSeq: head.seq, headChainHash: head.chainHash });
    }
    // every chunk present, the right size, and the whole thing hashes to what the phone declared
    const stats = await q(`SELECT count(*)::int AS n, COALESCE(SUM(size_bytes),0)::bigint AS bytes FROM backup_chunk WHERE upload_id = $1`, [uploadId]);
    if (stats[0].n !== u.chunk_count) return err(409, 'upload_incomplete', { received: stats[0].n, expected: u.chunk_count });
    if (Number(stats[0].bytes) !== Number(u.size_bytes)) return err(422, 'size_mismatch');
    const h = createHash('sha256');
    for (let from = 0; from < u.chunk_count; from += 16) {
      const rows = await q(`SELECT data FROM backup_chunk WHERE upload_id = $1 AND idx >= $2 AND idx < $3 ORDER BY idx`,
        [uploadId, from, from + 16]);
      for (const row of rows) h.update(row.data);
    }
    if (h.digest().compare(u.blob_sha256) !== 0) return err(422, 'blob_hash_mismatch');
    // the chain value is recomputed from the stored parts: the server never trusts a stored claim
    const want = chainHash({ vaultId, seq: Number(u.seq), prevChain: u.prev_chain_hash, blobSha256: u.blob_sha256,
      size: Number(u.size_bytes), manifest: u.manifest });
    if (want.compare(u.chain_hash) !== 0) return err(422, 'chain_mismatch');

    const ins = await q(
      `INSERT INTO backup_version (vault_id, seq, upload_id, prev_chain_hash, chain_hash, blob_sha256, size_bytes, chunk_size,
                                   chunk_count, manifest, signature, device_id, uploaded_by, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) RETURNING id`,
      [vaultId, u.seq, uploadId, u.prev_chain_hash, u.chain_hash, u.blob_sha256, u.size_bytes, u.chunk_size,
        u.chunk_count, u.manifest, u.signature, deviceId, userId, now]);
    await q(`UPDATE backup_upload SET state = 'committed', committed_at = $2 WHERE id = $1 AND state = 'open'`, [uploadId, now]);

    // Retention: never an overwrite. The newest N stay live; older ones become TOMBSTONES whose bytes are kept
    // for the recovery window.
    const [vault] = await q(`SELECT keep_versions, recovery_window_days FROM backup_vault WHERE id = $1`, [vaultId]);
    const old = await q(
      `SELECT id, seq FROM backup_version WHERE vault_id = $1 AND state = 'live' ORDER BY seq DESC OFFSET $2`,
      [vaultId, vault.keep_versions]);
    const purgeAfter = new Date(now.getTime() + vault.recovery_window_days * DAY);
    for (const o of old) {
      await q(`UPDATE backup_version SET state = 'tombstone', tombstone_reason = 'retention', tombstoned_at = $2,
                      tombstoned_by = NULL, purge_after = $3 WHERE id = $1 AND state = 'live'`, [o.id, now, purgeAfter]);
    }
    const v = await q(`SELECT ${VERSION_COLS} FROM backup_version v WHERE v.id = $1`, [ins[0].id]);
    return ok({ version: versionOut(v[0]), tombstoned: old.map((o) => Number(o.seq)).reverse(), alreadyCommitted: false }, 201);
  });
}

// ---------------------------------------------------------- versions ---------
export async function listVersions(pool, { userId, vaultId, afterSeq = 0, limit = 100 }) {
  const lim = Math.min(200, Math.max(1, Number(limit) || 100));
  const after = Math.max(0, Number(afterSeq) || 0);
  return asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    const rows = await q(
      `SELECT ${VERSION_COLS} FROM backup_version v WHERE v.vault_id = $1 AND v.seq > $2 ORDER BY v.seq LIMIT $3`,
      [vaultId, after, lim + 1]);
    const head = await headOf(q, vaultId);
    return ok({
      head: head.seq ? { seq: head.seq, chainHash: head.chainHash } : null,
      versions: rows.slice(0, lim).map(versionOut), more: rows.length > lim });
  });
}

export async function deleteVersion(pool, { userId, vaultId, seq, now }) {
  const n = Number(seq);
  if (!Number.isSafeInteger(n) || n < 1) return err(400, 'invalid_version');
  return asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    await lockVault(q, vaultId);
    const v = await q(`SELECT id, state FROM backup_version WHERE vault_id = $1 AND seq = $2`, [vaultId, n]);
    if (!v.length) return err(404, 'version_not_found');
    if (v[0].state === 'tombstone') return ok({ seq: n, state: 'tombstone', alreadySetAside: true });
    const live = await q(`SELECT count(*)::int AS n FROM backup_version WHERE vault_id = $1 AND state = 'live'`, [vaultId]);
    if (live[0].n <= 1) return err(409, 'last_version');
    const [vault] = await q(`SELECT recovery_window_days FROM backup_vault WHERE id = $1`, [vaultId]);
    const purgeAfter = new Date(now.getTime() + vault.recovery_window_days * DAY);
    const upd = await q(
      `UPDATE backup_version SET state = 'tombstone', tombstone_reason = 'deleted', tombstoned_at = $3,
              tombstoned_by = $4, purge_after = $5 WHERE id = $1 AND state = 'live' AND vault_id = $2 RETURNING seq`,
      [v[0].id, vaultId, now, userId, purgeAfter]);
    if (!upd.length) return err(409, 'version_changed');
    await addEvent(q, vaultId, 'version_deleted', userId, vault.recovery_window_days);
    return ok({ seq: n, state: 'tombstone', purgeAfter });
  });
}

export async function undeleteVersion(pool, { userId, vaultId, seq }) {
  const n = Number(seq);
  if (!Number.isSafeInteger(n) || n < 1) return err(400, 'invalid_version');
  return asGuardian(pool, userId, async (q) => {
    const gate = await needActive(q, vaultId, userId);
    if (gate) return gate;
    const v = await q(`SELECT id, state, purged_at FROM backup_version WHERE vault_id = $1 AND seq = $2`, [vaultId, n]);
    if (!v.length) return err(404, 'version_not_found');
    if (v[0].state === 'live') return ok({ seq: n, state: 'live', alreadyLive: true });
    if (v[0].purged_at) return err(410, 'version_purged');
    const upd = await q(
      `UPDATE backup_version SET state = 'live', tombstone_reason = NULL, tombstoned_at = NULL,
              tombstoned_by = NULL, purge_after = NULL
        WHERE id = $1 AND state = 'tombstone' AND purged_at IS NULL RETURNING seq`, [v[0].id]);
    if (!upd.length) return err(409, 'version_changed');
    await addEvent(q, vaultId, 'version_restored', userId);
    return ok({ seq: n, state: 'live' });
  });
}

// ----------------------------------------------------------- notices ---------
export async function listEvents(pool, { userId, vaultId, afterSeq = 0, limit = 100 }) {
  const lim = Math.min(200, Math.max(1, Number(limit) || 100));
  const after = Math.max(0, Number(afterSeq) || 0);
  return asGuardian(pool, userId, async (q) => {
    // RLS: a member sees every notice, the helper only the restore notices, anyone else nothing.
    const mem = await myState(q, vaultId, userId);
    const helper = await q(`SELECT 1 FROM backup_vault_helper WHERE vault_id = $1 AND user_id = $2 AND removed_at IS NULL`, [vaultId, userId]);
    if (mem === null && !helper.length) return err(404, 'vault_not_found');
    const rows = await q(
      `SELECT seq, scope, kind, summary, created_at, restore_id FROM backup_vault_event
        WHERE vault_id = $1 AND seq > $2 ORDER BY seq LIMIT $3`, [vaultId, after, lim]);
    return ok({ events: rows.map((r) => ({ seq: Number(r.seq), scope: r.scope, kind: r.kind, summary: r.summary,
      at: r.created_at, restoreId: r.restore_id })) });
  });
}

// ------------------------------------------------------------ members --------
export async function setMemberPaused(pool, { actorId, vaultId, targetId, paused, now }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const actor = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, actorId]);
    if (!actor.length) return err(404, 'vault_not_found');
    if (actor[0].state !== 'active') return err(403, 'reach_paused');
    if (actorId === targetId) return err(409, 'cannot_pause_yourself');
    const t = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, targetId]);
    if (!t.length) return err(404, 'member_not_found');
    if (paused) {
      if (t[0].state === 'paused') return ok({ userId: targetId, state: 'paused', already: true });
      await q(`UPDATE backup_vault_member SET state = 'paused', paused_at = $3, paused_by = $4 WHERE vault_id = $1 AND user_id = $2 AND state = 'active'`,
        [vaultId, targetId, now, actorId]);
      await addEvent(q, vaultId, 'member_paused', actorId);
      return ok({ userId: targetId, state: 'paused' });
    }
    if (t[0].state === 'active') return ok({ userId: targetId, state: 'active', already: true });
    await q(`UPDATE backup_vault_member SET state = 'active', paused_at = NULL, paused_by = NULL WHERE vault_id = $1 AND user_id = $2 AND state = 'paused'`,
      [vaultId, targetId]);
    await addEvent(q, vaultId, 'member_resumed', actorId);
    return ok({ userId: targetId, state: 'active' });
  });
}

const HELPER_ROLES = ['guardian', 'trusted_adult', 'step_parent', 'foster_parent'];

export async function nameHelper(pool, { actorId, vaultId, helperId, now }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const actor = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, actorId]);
    if (!actor.length) return err(404, 'vault_not_found');
    if (actor[0].state !== 'active') return err(403, 'reach_paused');
    if (helperId === actorId) return err(409, 'helper_must_be_someone_else');
    const members = await q(`SELECT count(*)::int AS n FROM backup_vault_member WHERE vault_id = $1`, [vaultId]);
    // A helper is for a single grown-up. With two parents the second parent IS the safeguard.
    if (members[0].n > 1) return err(409, 'helper_only_for_single_parent');
    const mem = await q(`SELECT 1 FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, helperId]);
    if (mem.length) return err(409, 'helper_must_be_someone_else');
    const known = await q(
      `SELECT 1 FROM effective_guardianship h JOIN effective_guardianship a ON a.child_id = h.child_id
        WHERE h.user_id = $1 AND a.user_id = $2 AND a.role = 'guardian' AND h.restricted = false
          AND h.role = ANY($3::text[]) LIMIT 1`, [helperId, actorId, HELPER_ROLES]);
    // A helper must already be a welcomed adult in this family; nobody can be named out of the blue.
    if (!known.length) return err(404, 'helper_not_found');
    const cur = await q(`SELECT id FROM backup_vault_helper WHERE vault_id = $1 AND removed_at IS NULL`, [vaultId]);
    if (cur.length) return err(409, 'helper_already_named');
    await q(`INSERT INTO backup_vault_helper (vault_id, user_id, named_by, named_at) VALUES ($1,$2,$3,$4)`,
      [vaultId, helperId, actorId, now]);
    await addEvent(q, vaultId, 'helper_named', actorId);
    return ok({ vaultId, helperId }, 201);
  });
}

export async function removeHelper(pool, { actorId, vaultId, now }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const actor = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, actorId]);
    if (!actor.length) return err(404, 'vault_not_found');
    if (actor[0].state !== 'active') return err(403, 'reach_paused');
    const r = await q(`UPDATE backup_vault_helper SET removed_at = $2, removed_by = $3
                        WHERE vault_id = $1 AND removed_at IS NULL RETURNING id`, [vaultId, now, actorId]);
    if (!r.length) return err(404, 'no_helper');
    await addEvent(q, vaultId, 'helper_removed', actorId);
    return ok({ vaultId, removed: true });
  });
}

// ----------------------------------------------------------- restores --------
export async function restoreChallenge(pool, { userId, deviceId, vaultId, now, cfg = backupConfig(), nonce }) {
  const n = nonce ?? (await import('node:crypto')).randomBytes(32);
  return withSystemSession(pool, async (q) => {
    const m = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, userId]);
    if (!m.length) return err(404, 'vault_not_found');
    if (m[0].state !== 'active') return err(403, 'reach_paused');
    // a few outstanding challenges per device, no more
    const recent = await q(
      `SELECT count(*)::int AS n FROM backup_restore_challenge WHERE device_id = $1 AND created_at > $2`,
      [deviceId, new Date(now.getTime() - HOUR)]);
    if (recent[0].n >= cfg.maxChallengesPerDeviceHour) return err(429, 'rate_limited', { retryAfterSec: 600 });
    const c = await q(
      `INSERT INTO backup_restore_challenge (vault_id, user_id, device_id, nonce, created_at, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6) RETURNING id, expires_at`,
      [vaultId, userId, deviceId, n, now, new Date(now.getTime() + cfg.challengeTtlMs)]);
    return ok({ challengeId: c[0].id, nonce: n.toString('hex'), expiresAt: c[0].expires_at }, 201);
  });
}

async function expireDue(q, vaultId, now) {
  const rows = await q(
    `UPDATE backup_restore_request SET state = 'expired', token_hash = NULL
      WHERE vault_id = $1 AND state = 'pending' AND expires_at <= $2 RETURNING id`, [vaultId, now]);
  for (const r of rows) await addEvent(q, vaultId, 'restore_expired', null, null, r.id);
}

export async function requestRestore(pool, { userId, deviceId, vaultId, challengeId, signature, now, cfg = backupConfig() }) {
  const sig = b64(signature, 64, 64);
  if (!sig || typeof challengeId !== 'string') return err(400, 'invalid_restore_request');
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const m = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, userId]);
    if (!m.length) return err(404, 'vault_not_found');
    if (m[0].state !== 'active') return err(403, 'reach_paused');
    // The challenge is single-use whether or not the signature turns out right.
    let used;
    try {
      used = await q(
        `UPDATE backup_restore_challenge SET used_at = $4
          WHERE id = $1 AND vault_id = $2 AND user_id = $3 AND used_at IS NULL AND expires_at > $4
            AND device_id = $5
        RETURNING encode(nonce,'hex') AS nonce`, [challengeId, vaultId, userId, now, deviceId]);
    } catch (e) { if (/^22/.test(String(e?.code))) return err(400, 'invalid_restore_request'); throw e; }
    if (!used.length) return err(403, 'challenge_invalid');
    const [vault] = await q(`SELECT recovery_verifier FROM backup_vault WHERE id = $1`, [vaultId]);
    const msg = restoreChallengeMessage({ vaultId, userId, deviceId, nonce: Buffer.from(used[0].nonce, 'hex') });
    if (!ed25519Verify(vault.recovery_verifier, msg, sig)) return err(403, 'recovery_key_proof_invalid');

    await expireDue(q, vaultId, now);
    const open = await q(`SELECT ${RESTORE_COLS} FROM backup_restore_request r WHERE r.vault_id = $1 AND r.state = 'pending'`, [vaultId]);
    if (open.length) return err(409, 'restore_already_open', { restore: restoreOut(open[0], now) });
    const since = new Date(now.getTime() - DAY);
    const perDevice = await q(`SELECT count(*)::int AS n FROM backup_restore_request WHERE device_id = $1 AND created_at > $2`, [deviceId, since]);
    const perVault = await q(`SELECT count(*)::int AS n FROM backup_restore_request WHERE vault_id = $1 AND created_at > $2`, [vaultId, since]);
    if (perDevice[0].n >= cfg.maxRequestsPerDevicePerDay || perVault[0].n >= cfg.maxRequestsPerVaultPerDay) {
      return err(429, 'restore_requests_limited', { retryAfterSec: 3600 });
    }
    // Who could say yes? Another ACTIVE grown-up, or a helper who has settled in. If nobody, the wait is longer.
    const others = await q(
      `SELECT count(*)::int AS n FROM backup_vault_member WHERE vault_id = $1 AND state = 'active' AND user_id <> $2`, [vaultId, userId]);
    const helper = await q(
      `SELECT count(*)::int AS n FROM backup_vault_helper WHERE vault_id = $1 AND removed_at IS NULL AND user_id <> $2
          AND named_at <= $3`, [vaultId, userId, new Date(now.getTime() - cfg.helperSettleHours * HOUR)]);
    const approvalRequired = others[0].n + helper[0].n > 0;
    const waitHours = approvalRequired ? cfg.waitHoursWithApprover : cfg.waitHoursSolo;
    const notBefore = new Date(now.getTime() + waitHours * HOUR);
    const expiresAt = new Date(notBefore.getTime() + cfg.requestLifetimeDays * DAY);
    const r = await q(
      `INSERT INTO backup_restore_request (vault_id, requested_by, device_id, created_at, wait_hours, not_before, approval_required, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`,
      [vaultId, userId, deviceId, now, waitHours, notBefore, approvalRequired, expiresAt]);
    await addEvent(q, vaultId, 'restore_requested', userId, waitHours, r[0].id);
    const row = await q(`SELECT ${RESTORE_COLS} FROM backup_restore_request r WHERE r.id = $1`, [r[0].id]);
    return ok({ restore: restoreOut(row[0], now) }, 201);
  });
}

export async function listRestores(pool, { userId, vaultId, now }) {
  return asGuardian(pool, userId, async (q) => {
    const mem = await myState(q, vaultId, userId);
    const helper = await q(`SELECT 1 FROM backup_vault_helper WHERE vault_id = $1 AND user_id = $2 AND removed_at IS NULL`, [vaultId, userId]);
    if (mem === null && !helper.length) return err(404, 'vault_not_found');
    const rows = await q(
      `SELECT ${RESTORE_COLS} FROM backup_restore_request r WHERE r.vault_id = $1 ORDER BY r.created_at DESC LIMIT 10`, [vaultId]);
    return ok({ restores: rows.map((r) => restoreOut(r, now)), role: mem !== null ? 'member' : 'helper' });
  });
}

/** Who is this person to this vault, right now? Run inside a system transaction. */
async function standing(q, vaultId, userId, cfg, now) {
  const m = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, userId]);
  if (m.length) return { kind: 'member', state: m[0].state };
  const h = await q(`SELECT named_at FROM backup_vault_helper WHERE vault_id = $1 AND user_id = $2 AND removed_at IS NULL`, [vaultId, userId]);
  if (h.length) {
    return { kind: 'helper', settled: new Date(h[0].named_at).getTime() <= now.getTime() - cfg.helperSettleHours * HOUR };
  }
  return null;
}

export async function approveRestore(pool, { userId, vaultId, restoreId, now, cfg = backupConfig() }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const who = await standing(q, vaultId, userId, cfg, now);
    if (!who) return err(404, 'restore_not_found');
    if (who.kind === 'member' && who.state !== 'active') return err(403, 'reach_paused');
    if (who.kind === 'helper' && !who.settled) return err(403, 'helper_not_settled');
    await expireDue(q, vaultId, now);
    const r = await q(`SELECT id, requested_by, state, approval_required, approved_at FROM backup_restore_request WHERE id = $1 AND vault_id = $2`, [restoreId, vaultId]);
    if (!r.length) return err(404, 'restore_not_found');
    const row = r[0];
    // Nobody can approve their own request, from any of their phones.
    if (row.requested_by === userId) return err(403, 'cannot_approve_own_restore');
    if (row.state !== 'pending') return err(409, `restore_${row.state}`);
    if (!row.approval_required) return err(409, 'no_approval_needed');
    if (row.approved_at) return ok({ restoreId, approved: true, already: true });
    const upd = await q(
      `UPDATE backup_restore_request SET approved_by = $3, approved_at = $4, approver_kind = $5
        WHERE id = $1 AND vault_id = $2 AND state = 'pending' AND approved_at IS NULL RETURNING id`,
      [restoreId, vaultId, userId, now, who.kind]);
    if (!upd.length) return err(409, 'restore_changed');
    await addEvent(q, vaultId, 'restore_approved', userId, null, restoreId);
    return ok({ restoreId, approved: true, approverKind: who.kind });
  });
}

export async function cancelRestore(pool, { userId, vaultId, restoreId, now, cfg = backupConfig() }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const r = await q(`SELECT id, requested_by, state FROM backup_restore_request WHERE id = $1 AND vault_id = $2`, [restoreId, vaultId]);
    if (!r.length) return err(404, 'restore_not_found');
    // Anyone who belongs to the vault (a PAUSED grown-up too), the helper, or the requester can stop it.
    const who = await standing(q, vaultId, userId, cfg, now);
    if (!who && r[0].requested_by !== userId) return err(404, 'restore_not_found');
    if (r[0].state === 'cancelled') return ok({ restoreId, state: 'cancelled', already: true });
    if (r[0].state !== 'pending') return err(409, `restore_${r[0].state}`);
    const upd = await q(
      `UPDATE backup_restore_request SET state = 'cancelled', cancelled_by = $3, cancelled_at = $4, token_hash = NULL
        WHERE id = $1 AND vault_id = $2 AND state = 'pending' RETURNING id`, [restoreId, vaultId, userId, now]);
    if (!upd.length) return err(409, 'restore_changed');
    await addEvent(q, vaultId, 'restore_cancelled', userId, null, restoreId);
    return ok({ restoreId, state: 'cancelled' });
  });
}

export async function issueRestoreToken(pool, { userId, deviceId, vaultId, restoreId, now, cfg = backupConfig() }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const m = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, userId]);
    if (!m.length) return err(404, 'restore_not_found');
    if (m[0].state !== 'active') return err(403, 'reach_paused');
    await expireDue(q, vaultId, now);
    const r = await q(`SELECT ${RESTORE_COLS}, r.requested_by, r.device_id, r.token_issue_count
                         FROM backup_restore_request r WHERE r.id = $1 AND r.vault_id = $2`, [restoreId, vaultId]);
    if (!r.length) return err(404, 'restore_not_found');
    const row = r[0];
    // Only the phone that asked, signed in as the person who asked.
    if (row.requested_by !== userId || row.device_id !== deviceId) return err(403, 'not_the_requesting_phone');
    if (row.state !== 'pending') return err(409, `restore_${row.state}`);
    if (now < new Date(row.not_before)) {
      return err(409, 'waiting_period', { notBefore: row.not_before, secondsLeft: Math.ceil((new Date(row.not_before) - now) / 1000) });
    }
    if (row.approval_required && !row.approved_at) return err(409, 'waiting_for_approval');
    if (row.token_issue_count >= cfg.maxTokenIssues) return err(429, 'token_issue_limit');
    const { token, digest } = newToken();
    const expires = new Date(now.getTime() + cfg.tokenTtlHours * HOUR);
    const upd = await q(
      `UPDATE backup_restore_request SET token_hash = $3, token_issued_at = $4, token_expires_at = $5,
              token_issue_count = token_issue_count + 1, token_failures = 0
        WHERE id = $1 AND vault_id = $2 AND state = 'pending' AND not_before <= $4
          AND (NOT approval_required OR approved_at IS NOT NULL)
      RETURNING token_issue_count`, [restoreId, vaultId, digest, now, expires]);
    if (!upd.length) return err(409, 'restore_changed');
    if (upd[0].token_issue_count === 1) await addEvent(q, vaultId, 'restore_token_issued', userId, null, restoreId);
    return ok({ restoreId, token, expiresAt: expires });
  });
}

/** Check a download token. Runs as system; counts wrong tokens and revokes after too many. */
async function checkRestoreToken(q, { userId, deviceId, vaultId, token, now, cfg }) {
  if (typeof token !== 'string' || token.length < 20 || token.length > 100) return err(403, 'restore_token_required');
  const r = await q(
    `SELECT id, requested_by, device_id, token_hash, token_expires_at, token_failures
       FROM backup_restore_request WHERE vault_id = $1 AND state = 'pending' AND token_hash IS NOT NULL`, [vaultId]);
  if (!r.length) return err(403, 'restore_token_invalid');
  const row = r[0];
  if (row.requested_by !== userId || row.device_id !== deviceId) return err(403, 'restore_token_invalid');
  if (new Date(row.token_expires_at) <= now) return err(403, 'restore_token_expired');
  if (row.token_hash !== tokenDigest(token)) {
    const f = await q(
      `UPDATE backup_restore_request SET token_failures = token_failures + 1,
              token_hash = CASE WHEN token_failures + 1 >= $2 THEN NULL ELSE token_hash END
        WHERE id = $1 RETURNING token_failures`, [row.id, cfg.maxTokenFailures]);
    return err(403, 'restore_token_invalid', f[0].token_failures >= cfg.maxTokenFailures ? { revoked: true } : {});
  }
  const m = await q(`SELECT state FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2`, [vaultId, userId]);
  if (!m.length || m[0].state !== 'active') return err(403, 'reach_paused');
  return { good: row };
}

export async function downloadChunk(pool, { userId, deviceId, vaultId, restoreId, seq, index, token, now, cfg = backupConfig() }) {
  const s = Number(seq), idx = Number(index);
  if (!Number.isSafeInteger(s) || s < 1 || !Number.isSafeInteger(idx) || idx < 0) return err(400, 'invalid_chunk');
  return withSystemSession(pool, async (q) => {
    const t = await checkRestoreToken(q, { userId, deviceId, vaultId, token, now, cfg });
    if (!t.good) return t;
    if (t.good.id !== restoreId) return err(403, 'restore_token_invalid');
    const v = await q(`SELECT upload_id, chunk_count, purged_at FROM backup_version WHERE vault_id = $1 AND seq = $2`, [vaultId, s]);
    if (!v.length) return err(404, 'version_not_found');
    if (v[0].purged_at) return err(410, 'version_purged');
    if (idx >= v[0].chunk_count) return err(404, 'chunk_not_found');
    const c = await q(`SELECT size_bytes, encode(sha256,'hex') AS sha256, encode(data,'base64') AS data FROM backup_chunk WHERE upload_id = $1 AND idx = $2`, [v[0].upload_id, idx]);
    if (!c.length) return err(404, 'chunk_not_found');
    return ok({ seq: s, index: idx, sizeBytes: c[0].size_bytes, sha256: c[0].sha256, data: c[0].data.replace(/\n/g, '') });
  });
}

export async function completeRestore(pool, { userId, deviceId, vaultId, restoreId, token, now, cfg = backupConfig() }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const t = await checkRestoreToken(q, { userId, deviceId, vaultId, token, now, cfg });
    if (!t.good) return t;
    if (t.good.id !== restoreId) return err(404, 'restore_not_found');
    const upd = await q(
      `UPDATE backup_restore_request SET state = 'completed', completed_at = $3, token_hash = NULL
        WHERE id = $1 AND vault_id = $2 AND state = 'pending' RETURNING id`, [restoreId, vaultId, now]);
    if (!upd.length) return err(409, 'restore_changed');
    await addEvent(q, vaultId, 'restore_completed', userId, null, restoreId);
    return ok({ restoreId, state: 'completed' });
  });
}

/**
 * The hook for ENDING a grown-up (the family's own decision: both parents, or the 14-day wait). Called by
 * the identity lane when it closes the last guardianship edge; there is no route for it, because no one
 * parent may remove another alone. Removes the membership (and a helper role) and any restore that
 * person had asked for. Nothing in the backup is touched: every version stays, for the members who remain.
 */
export async function endVaultMembership(pool, { vaultId, userId, now = new Date() }) {
  return withSystemSession(pool, async (q) => {
    await lockVault(q, vaultId);
    const r = await q(`DELETE FROM backup_vault_member WHERE vault_id = $1 AND user_id = $2 RETURNING user_id`, [vaultId, userId]);
    await q(`UPDATE backup_vault_helper SET removed_at = $3, removed_by = NULL
              WHERE vault_id = $1 AND user_id = $2 AND removed_at IS NULL`, [vaultId, userId, now]);
    await q(`UPDATE backup_restore_request SET state = 'cancelled', cancelled_at = $3, token_hash = NULL
              WHERE vault_id = $1 AND requested_by = $2 AND state = 'pending'`, [vaultId, userId, now]);
    return ok({ vaultId, removed: r.length > 0 });
  });
}
