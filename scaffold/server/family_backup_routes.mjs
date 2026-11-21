// OLIVE BRANCH -- encrypted family backup: the HTTP routes. MASTERFILE 7.22.
// A thin layer over server/family_backup.mjs: it decides WHO may call (a grown-up's session on an
// enrolled device, never a child), asks for the grown-up's own PIN on the acts that change who can
// reach the backup or what is kept, applies per-person rate limits, and turns the service's
// { status, body } into a response. Every route lives under /v1/backup/.
//
// The first lock is here (guardian session + device session + PIN for sensitive acts); the second is the
// database (row level security and the append-only triggers, db/migrations/0057_family_backup.sql).
// Nothing here ever sees a key: bodies carry opaque, already-sealed bytes and hashes.
import { TokenBuckets } from './rate_limit.mjs';
import { backupConfig } from './family_backup.mjs';
import * as svc from './family_backup.mjs';

/** Rate limits per signed-in grown-up. Overridable for tests; the defaults are generous for a person. */
export function createBackupLimiters({ now } = {}) {
  const mk = (capacity, perHour) => new TokenBuckets({ capacity, refillPerSec: perHour / 3600, now });
  return {
    begin: mk(8, 8),            // new backups started
    challenge: mk(10, 10),      // restore challenges
    request: mk(5, 5),          // restore requests
    token: mk(10, 10),          // restore tokens
    members: mk(12, 12),        // pause / resume / helper changes
    download: mk(1200, 12000),  // restore chunk reads (a whole large backup, then some)
    reads: mk(300, 6000),       // status / lists / events
  };
}

export function backupEnabled(env = process.env) {
  const v = String(env.BACKUP_VAULT_ENABLED ?? '').toLowerCase();
  return !(v === '0' || v === 'false' || v === 'off');
}

export function registerBackupRoutes(api, pool, { requireOwnPin, env = process.env, limiters = createBackupLimiters(), cfg } = {}) {
  const config = () => cfg ?? backupConfig(env);
  const nowDate = () => new Date();

  /** Who is calling: a grown-up on an enrolled device, with the feature on. Else a ready answer. */
  const who = (c, { device = true } = {}) => {
    if (!backupEnabled(env)) return { fail: { status: 404, body: { error: 'backup_not_enabled' } } };
    if (c.principal.roleName === 'child' || !c.principal.userId) {
      return { fail: { status: 403, body: { error: 'guardian_session_required' } } };
    }
    if (device && !c.principal.deviceId) {
      return { fail: { status: 403, body: { error: 'device_session_required' } } };
    }
    return { userId: c.principal.userId, deviceId: c.principal.deviceId ?? null };
  };
  const limited = (bucket, userId) => {
    const r = limiters[bucket].take(`u:${userId}`);
    return r.ok ? null : { status: 429, body: { error: 'rate_limited', retryAfterSec: r.retryAfterSec } };
  };
  const withPin = async (userId, pin) => {
    const p = await requireOwnPin(userId, pin);
    return p.ok ? null : { status: p.status, body: { error: p.error } };
  };
  const out = (r) => {
    if (r && r.retryAfterReclaim) delete r.retryAfterReclaim;
    return r;
  };
  const route = (method, path, handler) => api.register({
    method, path, action: null, skipOuterSession: true,
    // PUT and the big GETs carry bodies of ciphertext; every route is a guardian-only, vault-scoped one
    // whose handler does its own scoped sessions (family_backup.mjs).
    handler: async (c) => {
      try { return out(await handler(c)); } catch (e) {
        if (/^(22|23)/.test(String(e?.code ?? ''))) return { status: 400, body: { error: 'invalid_input' } };
        throw e;
      }
    },
  });

  // ---- what the server will accept (so a phone can plan for a weak link) --------------------------
  route('GET', '/v1/backup/limits', async (c) => {
    const w = who(c, { device: false });
    if (w.fail) return w.fail;
    const k = config();
    return { status: 200, body: {
      quotaBytes: k.quotaBytes, maxVersionBytes: k.maxVersionBytes, maxChunkBytes: k.maxChunkBytes,
      maxChunks: k.maxChunks, keepVersions: k.keepVersions, recoveryWindowDays: k.recoveryWindowDays,
      uploadTtlHours: k.uploadTtlHours, waitHoursWithApprover: k.waitHoursWithApprover,
      waitHoursSolo: k.waitHoursSolo, tokenTtlHours: k.tokenTtlHours } };
  });

  // ---- the vault ------------------------------------------------------------------------------------
  route('GET', '/v1/backup/vaults', async (c) => {
    const w = who(c, { device: false });
    if (w.fail) return w.fail;
    return svc.listVaults(pool, { userId: w.userId });
  });

  route('POST', '/v1/backup/vaults', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    return svc.createVault(pool, { userId: w.userId, recoveryVerifier: c.body?.recoveryVerifier, now: nowDate(), cfg: config() });
  });

  route('POST', '/v1/backup/vaults/:vaultId/join', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    return svc.joinVault(pool, { userId: w.userId, vaultId: c.params.vaultId, now: nowDate(), cfg: config() });
  });

  route('GET', '/v1/backup/vaults/:vaultId', async (c) => {
    const w = who(c, { device: false }); if (w.fail) return w.fail;
    const l = limited('reads', w.userId); if (l) return l;
    return svc.vaultStatus(pool, { userId: w.userId, vaultId: c.params.vaultId, now: nowDate() });
  });

  route('GET', '/v1/backup/vaults/:vaultId/events', async (c) => {
    const w = who(c, { device: false }); if (w.fail) return w.fail;
    const l = limited('reads', w.userId); if (l) return l;
    return svc.listEvents(pool, { userId: w.userId, vaultId: c.params.vaultId,
      afterSeq: c.query.get('after'), limit: c.query.get('limit') });
  });

  // ---- who can reach it: pause (reversible, visible to all) and the one trusted helper --------------
  const pauseRoute = (suffix, paused) => route('POST', `/v1/backup/vaults/:vaultId/${suffix}`, async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('members', w.userId); if (l) return l;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    const target = c.body?.targetUserId;
    if (typeof target !== 'string' || !/^[0-9a-f-]{36}$/i.test(target)) return { status: 400, body: { error: 'invalid_input' } };
    return svc.setMemberPaused(pool, { actorId: w.userId, vaultId: c.params.vaultId, targetId: target, paused, now: nowDate() });
  });
  pauseRoute('pause', true);
  pauseRoute('resume', false);

  route('POST', '/v1/backup/vaults/:vaultId/helper', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('members', w.userId); if (l) return l;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    const helper = c.body?.helperUserId;
    if (typeof helper !== 'string' || !/^[0-9a-f-]{36}$/i.test(helper)) return { status: 400, body: { error: 'invalid_input' } };
    return svc.nameHelper(pool, { actorId: w.userId, vaultId: c.params.vaultId, helperId: helper, now: nowDate() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/helper/remove', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('members', w.userId); if (l) return l;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    return svc.removeHelper(pool, { actorId: w.userId, vaultId: c.params.vaultId, now: nowDate() });
  });

  // ---- backing up: begin, chunks (resumable), commit -----------------------------------------------
  route('POST', '/v1/backup/vaults/:vaultId/uploads', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('begin', w.userId); if (l) return l;
    return svc.beginUpload(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      body: c.body, now: nowDate(), cfg: config() });
  });
  route('GET', '/v1/backup/vaults/:vaultId/uploads/:uploadId', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('reads', w.userId); if (l) return l;
    return svc.uploadStatus(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      uploadId: c.params.uploadId, now: nowDate() });
  });
  route('PUT', '/v1/backup/vaults/:vaultId/uploads/:uploadId/chunks/:index', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    return svc.putChunk(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      uploadId: c.params.uploadId, index: c.params.index, body: c.body, now: nowDate(), cfg: config() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/uploads/:uploadId/commit', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    return svc.commitUpload(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      uploadId: c.params.uploadId, now: nowDate() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/uploads/:uploadId/abort', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    return svc.abortUpload(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      uploadId: c.params.uploadId, now: nowDate() });
  });

  // ---- versions: list (the phone verifies the chain), set aside, bring back ------------------------
  route('GET', '/v1/backup/vaults/:vaultId/versions', async (c) => {
    const w = who(c, { device: false }); if (w.fail) return w.fail;
    const l = limited('reads', w.userId); if (l) return l;
    return svc.listVersions(pool, { userId: w.userId, vaultId: c.params.vaultId,
      afterSeq: c.query.get('after'), limit: c.query.get('limit') });
  });
  route('POST', '/v1/backup/vaults/:vaultId/versions/:seq/delete', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    return svc.deleteVersion(pool, { userId: w.userId, vaultId: c.params.vaultId, seq: c.params.seq, now: nowDate() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/versions/:seq/undelete', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    return svc.undeleteVersion(pool, { userId: w.userId, vaultId: c.params.vaultId, seq: c.params.seq });
  });

  // ---- restoring onto a new phone ---------------------------------------------------------------------
  route('POST', '/v1/backup/vaults/:vaultId/restores/challenge', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('challenge', w.userId); if (l) return l;
    return svc.restoreChallenge(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      now: nowDate(), cfg: config() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/restores', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('request', w.userId); if (l) return l;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    return svc.requestRestore(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      challengeId: c.body?.challengeId, signature: c.body?.signature, now: nowDate(), cfg: config() });
  });
  route('GET', '/v1/backup/vaults/:vaultId/restores', async (c) => {
    const w = who(c, { device: false }); if (w.fail) return w.fail;
    const l = limited('reads', w.userId); if (l) return l;
    return svc.listRestores(pool, { userId: w.userId, vaultId: c.params.vaultId, now: nowDate() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/restores/:restoreId/approve', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const pin = await withPin(w.userId, c.body?.pin); if (pin) return pin;
    return svc.approveRestore(pool, { userId: w.userId, vaultId: c.params.vaultId, restoreId: c.params.restoreId,
      now: nowDate(), cfg: config() });
  });
  // Cancelling asks for no PIN and no waiting: it can only ever STOP something. Anyone who belongs to the
  // vault (a paused grown-up and the helper included) may, from any phone.
  route('POST', '/v1/backup/vaults/:vaultId/restores/:restoreId/cancel', async (c) => {
    const w = who(c, { device: false }); if (w.fail) return w.fail;
    return svc.cancelRestore(pool, { userId: w.userId, vaultId: c.params.vaultId, restoreId: c.params.restoreId,
      now: nowDate(), cfg: config() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/restores/:restoreId/token', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('token', w.userId); if (l) return l;
    return svc.issueRestoreToken(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      restoreId: c.params.restoreId, now: nowDate(), cfg: config() });
  });
  // The token travels in a header, never in a URL (URLs are logged).
  route('GET', '/v1/backup/vaults/:vaultId/restores/:restoreId/versions/:seq/chunks/:index', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    const l = limited('download', w.userId); if (l) return l;
    return svc.downloadChunk(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      restoreId: c.params.restoreId, seq: c.params.seq, index: c.params.index, token: c.headers['x-olive-restore-token'], now: nowDate(), cfg: config() });
  });
  route('POST', '/v1/backup/vaults/:vaultId/restores/:restoreId/complete', async (c) => {
    const w = who(c); if (w.fail) return w.fail;
    return svc.completeRestore(pool, { userId: w.userId, deviceId: w.deviceId, vaultId: c.params.vaultId,
      restoreId: c.params.restoreId, token: c.headers['x-olive-restore-token'], now: nowDate(), cfg: config() });
  });
}
