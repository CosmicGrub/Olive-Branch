import pg from "pg";
import { newChallenge, verifyPin } from "../../auth/src/auth.ts";
import { sha256Hex } from "../../ledger/src/sha256.ts";
function createPool(connectionString) {
  return new pg.Pool({ connectionString });
}
async function withSession(pool, principal, fn) {
  if (principal.roleName === "child" && !principal.childId) {
    throw new Error("withSession: child principal missing childId");
  }
  if (principal.roleName !== "child" && principal.roleName !== "system" && !principal.userId) {
    throw new Error(`withSession: ${principal.roleName} principal missing userId`);
  }
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(`SELECT set_config('app.role', $1, true)`, [principal.roleName]);
    await client.query(`SELECT set_config('app.child_id', $1, true)`, [principal.childId ?? ""]);
    await client.query(`SELECT set_config('app.user_id', $1, true)`, [principal.userId ?? ""]);
    const q = async (sql, params = []) => {
      const res = await client.query(sql, params);
      return res.rows;
    };
    const result = await fn(q);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {
    });
    throw e;
  } finally {
    client.release();
  }
}
function withSystemSession(pool, fn) {
  return withSession(pool, { roleName: "system", userId: null, childId: null }, fn);
}
async function edgesFor(pool, userId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT g.child_id, g.user_id, g.role, g.scope, g.observer_only, g.restricted,
              lower(g.valid)::text AS valid_from, upper(g.valid)::text AS valid_to,
              g.expires_at::text AS expires_at, g.closed_at::text AS closed_at,
              cl.step AS ladder_step
         FROM guardianship g
         LEFT JOIN contact_ladder cl
           ON cl.guardianship_id = g.id AND cl.effective @> now()
        WHERE g.user_id = $1`,
      [userId]
    );
    return rows.map((r) => ({
      childId: r.child_id,
      userId: r.user_id,
      role: r.role,
      scope: r.scope ?? {},
      observerOnly: r.observer_only,
      restricted: r.restricted,
      validFrom: r.valid_from,
      validTo: r.valid_to,
      expiresAt: r.expires_at,
      closedAt: r.closed_at,
      ladderStep: r.ladder_step
    }));
  });
}
async function activeCustodyOrderFor(pool, childId, nowLocalDate) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT pattern, order_tz,
              anchor_local_date::text AS anchor_local_date,
              to_char(exchange_time, 'HH24:MI') AS exchange_time,
              holiday_rules,
              effective_from::text AS effective_from,
              effective_to::text AS effective_to
         FROM custody_order
        WHERE child_id = $1
          AND effective_from <= $2::date
          AND (effective_to IS NULL OR effective_to >= $2::date)
        LIMIT 1`,
      [childId, nowLocalDate]
    );
    if (!rows.length) return null;
    const r = rows[0];
    return {
      pattern: r.pattern,
      orderTz: r.order_tz,
      anchorLocalDate: r.anchor_local_date,
      exchangeTime: r.exchange_time,
      holidays: r.holiday_rules ?? [],
      effectiveFrom: r.effective_from,
      effectiveTo: r.effective_to
    };
  });
}
async function guardiansOfChild(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT DISTINCT user_id FROM effective_guardianship WHERE child_id = $1`,
      [childId]
    );
    return rows.map((r) => ({ userId: r.user_id }));
  });
}
async function pinCredentialFor(pool, userId) {
  return withSession(pool, { roleName: "guardian", userId, childId: null }, async (q) => {
    const rows = await q(
      `SELECT pin_hash, failed_attempts, locked_until FROM pin_credential WHERE user_id = $1`,
      [userId]
    );
    if (!rows.length) return null;
    const r = rows[0];
    return { pinHash: r.pin_hash, failedAttempts: r.failed_attempts, lockedUntil: r.locked_until };
  });
}
async function setPinCredential(pool, userId, pinHash) {
  await withSession(pool, { roleName: "guardian", userId, childId: null }, async (q) => {
    await q(
      `INSERT INTO pin_credential (user_id, pin_hash, failed_attempts, locked_until, updated_at)
       VALUES ($1, $2, 0, NULL, now())
       ON CONFLICT (user_id) DO UPDATE
         SET pin_hash = EXCLUDED.pin_hash, failed_attempts = 0,
             locked_until = NULL, updated_at = now()`,
      [userId, pinHash]
    );
  });
}
const PIN_MAX_ATTEMPTS = 5;
const PIN_LOCKOUT_MS = 15 * 60 * 1e3;
async function recordPinAttempt(pool, userId, success) {
  return withSession(pool, { roleName: "guardian", userId, childId: null }, async (q) => {
    if (success) {
      const rows2 = await q(
        `UPDATE pin_credential
            SET failed_attempts = 0, locked_until = NULL, updated_at = now()
          WHERE user_id = $1
          RETURNING locked_until`,
        [userId]
      );
      return { lockedUntil: rows2[0]?.locked_until ?? null };
    }
    const rows = await q(
      `UPDATE pin_credential
          SET failed_attempts = CASE WHEN failed_attempts + 1 >= $2 THEN 0
                                      ELSE failed_attempts + 1 END,
              locked_until = CASE WHEN failed_attempts + 1 >= $2
                                   THEN now() + ($3 || ' milliseconds')::interval
                                   ELSE locked_until END,
              updated_at = now()
        WHERE user_id = $1
        RETURNING locked_until`,
      [userId, PIN_MAX_ATTEMPTS, PIN_LOCKOUT_MS]
    );
    return { lockedUntil: rows[0]?.locked_until ?? null };
  });
}
async function attemptPinFor(pool, userId, candidatePin) {
  return withSession(pool, { roleName: "guardian", userId, childId: null }, async (q) => {
    const rows = await q(
      `SELECT pin_hash, failed_attempts, locked_until
         FROM pin_credential WHERE user_id = $1 FOR UPDATE`,
      [userId]
    );
    if (!rows.length) return { matched: false, hasCredential: false, locked: false };
    const r = rows[0];
    if (r.locked_until && r.locked_until.getTime() > Date.now()) {
      return { matched: false, hasCredential: true, locked: true };
    }
    const ok = verifyPin(candidatePin, r.pin_hash);
    if (ok) {
      await q(
        `UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL, updated_at = now()
          WHERE user_id = $1`,
        [userId]
      );
    } else {
      await q(
        `UPDATE pin_credential
            SET failed_attempts = CASE WHEN failed_attempts + 1 >= $2 THEN 0
                                        ELSE failed_attempts + 1 END,
                locked_until = CASE WHEN failed_attempts + 1 >= $2
                                     THEN now() + ($3 || ' milliseconds')::interval
                                     ELSE locked_until END,
                updated_at = now()
          WHERE user_id = $1`,
        [userId, PIN_MAX_ATTEMPTS, PIN_LOCKOUT_MS]
      );
    }
    return { matched: ok, hasCredential: true, locked: false };
  });
}
const CHALLENGE_TTL_MS = 5 * 60 * 1e3;
async function createChallenge(pool, userId, purpose) {
  const challenge = newChallenge();
  await withSystemSession(pool, async (q) => {
    await q(
      `INSERT INTO auth_challenge (user_id, challenge, purpose) VALUES ($1, $2, $3)`,
      [userId, challenge, purpose]
    );
  });
  return challenge;
}
async function consumeChallenge(pool, userId, purpose, challenge) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `UPDATE auth_challenge
          SET consumed_at = now()
        WHERE user_id = $1 AND purpose = $2 AND challenge = $3
          AND consumed_at IS NULL
          AND issued_at > now() - ($4 || ' milliseconds')::interval
        RETURNING id`,
      [userId, purpose, challenge, CHALLENGE_TTL_MS]
    );
    return rows.length === 1;
  });
}
async function storeWebauthnCredential(pool, userId, credentialId, publicKeyPem) {
  await withSession(pool, { roleName: "guardian", userId, childId: null }, async (q) => {
    await q(
      `INSERT INTO webauthn_credential (user_id, credential_id, public_key_pem)
       VALUES ($1, $2, $3)`,
      [userId, credentialId, publicKeyPem]
    );
  });
}
async function webauthnCredentialsForUser(pool, userId) {
  return withSession(pool, { roleName: "guardian", userId, childId: null }, async (q) => {
    const rows = await q(
      `SELECT credential_id, public_key_pem, sign_count, user_id
         FROM webauthn_credential WHERE user_id = $1`,
      [userId]
    );
    return rows.map((r) => ({
      credentialId: r.credential_id,
      publicKeyPem: r.public_key_pem,
      signCount: Number(r.sign_count),
      userId: r.user_id
    }));
  });
}
async function webauthnCredentialById(pool, credentialId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT credential_id, public_key_pem, sign_count, user_id
         FROM webauthn_credential WHERE credential_id = $1`,
      [credentialId]
    );
    if (!rows.length) return null;
    const r = rows[0];
    return {
      credentialId: r.credential_id,
      publicKeyPem: r.public_key_pem,
      signCount: Number(r.sign_count),
      userId: r.user_id
    };
  });
}
async function updateWebauthnSignCount(pool, credentialId, newSignCount) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `UPDATE webauthn_credential
          SET sign_count = $2
        WHERE credential_id = $1 AND ($2 = 0 OR sign_count < $2)
        RETURNING sign_count`,
      [credentialId, newSignCount]
    );
    return rows.length === 1;
  });
}
async function setAvailabilityWindows(pool, guardianId, windows) {
  await withSession(
    pool,
    { roleName: "guardian", userId: guardianId, childId: null },
    async (q) => {
      await q(`DELETE FROM guardian_availability_window WHERE guardian_id = $1`, [guardianId]);
      for (const w of windows) {
        await q(
          `INSERT INTO guardian_availability_window
             (guardian_id, weekday, start_local, end_local, note)
           VALUES ($1, $2, $3, $4, $5)`,
          [guardianId, w.weekday, w.startLocal, w.endLocal, w.note ?? null]
        );
      }
    }
  );
}
async function availabilityFor(pool, childId) {
  const guardianIds = (await guardiansOfChild(pool, childId)).map((g) => g.userId);
  if (!guardianIds.length) return [];
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT w.guardian_id, w.weekday,
              to_char(w.start_local, 'HH24:MI') AS start_local,
              to_char(w.end_local,   'HH24:MI') AS end_local,
              w.note, u.display_name AS guardian_name
         FROM guardian_availability_window w
         JOIN app_user u ON u.id = w.guardian_id
        WHERE w.guardian_id = ANY($1::uuid[])
        ORDER BY w.guardian_id, w.weekday, w.start_local`,
      [guardianIds]
    );
    return rows.map((r) => ({
      guardianId: r.guardian_id,
      guardianName: r.guardian_name,
      weekday: r.weekday,
      startLocal: r.start_local,
      endLocal: r.end_local,
      note: r.note
    }));
  });
}
async function deactivateAccount(pool, userId, callerRoleName = "guardian") {
  if (!userId) throw new Error("deactivateAccount: userId required");
  if (callerRoleName === "child") {
    throw new Error("deactivateAccount: a child role cannot deactivate an account \u2014 children have no login of their own to delete (\xA711)");
  }
  return withSession(pool, { roleName: callerRoleName, userId, childId: null }, async (q) => {
    const existing = await q(
      `SELECT id, deactivated_at FROM app_user WHERE id = $1 FOR UPDATE`,
      [userId]
    );
    if (existing.length === 0) {
      throw Object.assign(
        new Error("deactivateAccount: no such app_user"),
        { code: "account_not_found" }
      );
    }
    if (existing[0].deactivated_at) {
      throw Object.assign(
        new Error("deactivateAccount: already deactivated"),
        { code: "already_deactivated" }
      );
    }
    const cancelled = await q(
      `DELETE FROM delivery_intent
        WHERE sender_id = $1 AND state NOT IN ('delivered', 'opened')
        RETURNING id`,
      [userId]
    );
    const pins = await q(
      `DELETE FROM pin_credential WHERE user_id = $1 RETURNING id`,
      [userId]
    );
    const passkeys = await q(
      `DELETE FROM webauthn_credential WHERE user_id = $1 RETURNING credential_id`,
      [userId]
    );
    const challenges = await q(
      `DELETE FROM webauthn_challenge WHERE user_id = $1 RETURNING challenge`,
      [userId]
    );
    const deactivated = await q(
      `UPDATE app_user SET deactivated_at = now()
        WHERE id = $1 AND deactivated_at IS NULL
        RETURNING id`,
      [userId]
    );
    if (deactivated.length !== 1) {
      throw new Error(`deactivateAccount: expected to deactivate exactly 1 app_user row, affected ${deactivated.length}`);
    }
    return {
      userId,
      cancelledDeliveryIntents: cancelled.length,
      removedPinCredentials: pins.length,
      removedWebauthnCredentials: passkeys.length,
      removedWebauthnChallenges: challenges.length
    };
  });
}
async function childCtxFor(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [childId]);
    if (!child.length) return null;
    const tzRows = await q(
      `SELECT tz, lower(valid)::text AS start, upper(valid)::text AS "end"
         FROM child_tz_interval WHERE child_id = $1 ORDER BY lower(valid)`,
      [childId]
    );
    const dpRows = await q(
      `SELECT kind, starts_local::text AS starts_local, ends_local::text AS ends_local,
              days_of_week, reachable
         FROM day_part
        WHERE child_id = $1 AND effective @> CURRENT_DATE`,
      [childId]
    );
    return {
      homeTz: child[0].home_tz,
      tzIntervals: tzRows.map((r) => ({ tz: r.tz, start: r.start, end: r.end })),
      dayParts: dpRows.map((r) => ({
        kind: r.kind,
        startsLocal: r.starts_local,
        endsLocal: r.ends_local,
        daysOfWeek: r.days_of_week,
        reachable: r.reachable
      }))
    };
  });
}
async function rawExportBundleFor(pool, principal, childId) {
  if (principal.roleName === "child") {
    throw new Error(
      "rawExportBundleFor: child-self export is not implemented (no age gate wired, and export_record.requested_by has no app_user row to name)"
    );
  }
  if (!principal.userId) {
    throw new Error("rawExportBundleFor: non-child principal missing userId");
  }
  const requesterId = principal.userId;
  return withSession(pool, principal, async (q) => {
    const live = await q(
      `SELECT 1 FROM guardianship
        WHERE child_id = $1 AND user_id = $2 AND role = 'guardian'
          AND closed_at IS NULL
          AND (expires_at IS NULL OR expires_at > now())
          AND restricted = false
          AND valid @> now()
        LIMIT 1`,
      [childId, requesterId]
    );
    if (!live.length) return { ok: false, reason: "not_a_live_guardian" };
    const childRows = await q(`SELECT display_name FROM child WHERE id = $1`, [childId]);
    const deliveredRows = await q(
      `SELECT di.id, di.payload_kind, di.sender_id, u.display_name AS sender_name,
              di.state, di.materialized_at::text,
              m.id AS artifact_id, m.kind AS artifact_kind, m.storage_key,
              m.duration_ms, m.caption_key, m.captured_at::text, m.captured_tz,
              m.era_tag, m.preserved
         FROM delivery_intent di
         JOIN app_user u ON u.id = di.sender_id
         LEFT JOIN media_artifact m ON m.id = di.payload_ref
        WHERE di.child_id = $1 AND di.state IN ('delivered', 'opened')
        ORDER BY di.materialized_at ASC NULLS LAST`,
      [childId]
    );
    const journalRows = await q(
      `SELECT id, body, media_ref, created_at::text
         FROM child_journal_entry WHERE child_id = $1 ORDER BY created_at ASC`,
      [childId]
    );
    const logRows = await q(
      `SELECT seq, author_id, at::text, body, prev_hash, hash
         FROM message_log WHERE child_id = $1 ORDER BY seq ASC`,
      [childId]
    );
    const bundle = {
      childId,
      childName: childRows[0]?.display_name ?? null,
      generatedAt: (/* @__PURE__ */ new Date()).toISOString(),
      requestedByUserId: requesterId,
      delivered: deliveredRows.map((r) => ({
        id: r.id,
        payloadKind: r.payload_kind,
        senderId: r.sender_id,
        senderName: r.sender_name ?? null,
        state: r.state,
        materializedAt: r.materialized_at ?? null,
        artifact: r.artifact_id ? {
          id: r.artifact_id,
          kind: r.artifact_kind,
          storageKey: r.storage_key,
          durationMs: r.duration_ms ?? null,
          captionKey: r.caption_key ?? null,
          capturedAt: r.captured_at,
          capturedTz: r.captured_tz,
          eraTag: r.era_tag ?? null,
          preserved: r.preserved
        } : null
      })),
      journalEntries: journalRows.map((r) => ({
        id: r.id,
        body: r.body ?? null,
        mediaRef: r.media_ref ?? null,
        createdAt: r.created_at
      })),
      messageLog: logRows.map((r) => ({
        seq: Number(r.seq),
        authorId: r.author_id,
        at: r.at,
        body: r.body,
        prevHash: r.prev_hash,
        hash: r.hash
      }))
    };
    const serialized = JSON.stringify(bundle);
    const bundleHash = sha256Hex(serialized);
    const inserted = await q(
      `INSERT INTO export_record (child_id, requested_by, kind, was_free, bundle_hash)
       VALUES ($1, $2, 'raw', true, $3) RETURNING id::text`,
      [childId, requesterId, bundleHash]
    );
    return { ok: true, bundle, serialized, recordId: inserted[0].id, bundleHash };
  });
}
async function persistCapturedMessage(pool, capture, opts = {}) {
  return withSystemSession(pool, async (q) => {
    const a = capture.artifact;
    const artifactRows = await q(
      `INSERT INTO media_artifact
         (child_id, author_id, kind, storage_key, duration_ms, caption_key,
          captured_at, captured_tz, era_tag, preserved, preserved_by,
          preserved_at, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7::timestamptz,$8,$9,$10,$11,
               $12::timestamptz,$13::timestamptz)
       RETURNING id`,
      [
        a.childId,
        a.authorId,
        a.kind,
        a.storageKey,
        a.durationMs,
        a.captionKey,
        a.capturedAt,
        a.capturedTz,
        a.eraTag,
        a.preserved,
        a.preservedBy,
        a.preservedAt,
        a.expiresAt
      ]
    );
    const artifactId = artifactRows[0].id;
    const i = capture.intent;
    let batchId = i.batchId;
    if (opts.newBatch) {
      const b = opts.newBatch;
      const batchRows = await q(
        `INSERT INTO intent_batch
           (child_id, sender_id, label, reason, cadence, daypart,
            starts_local, ends_local)
         VALUES ($1,$2,$3,$4,$5,$6,$7::date,$8::date)
         RETURNING id`,
        [
          i.childId,
          i.senderId,
          b.label,
          b.reason ?? null,
          b.cadence,
          i.targetDaypart,
          b.startsLocal,
          b.endsLocal
        ]
      );
      batchId = batchRows[0].id;
    }
    const intentRows = await q(
      `INSERT INTO delivery_intent
         (child_id, sender_id, payload_kind, payload_ref, policy,
          target_local_date, target_daypart, batch_id, batch_seq, state,
          expires_at)
       VALUES ($1,$2,$3,$4,$5::delivery_policy,$6::date,$7,$8,$9,$10,
               $11::timestamptz)
       RETURNING id`,
      [
        i.childId,
        i.senderId,
        i.payloadKind,
        artifactId,
        i.policy,
        i.targetLocalDate,
        i.targetDaypart,
        batchId,
        i.batchSeq,
        i.state,
        i.expiresAt
      ]
    );
    return { artifactId, intentId: intentRows[0].id, batchId };
  });
}
function dbPort(pool) {
  return {
    edgesFor: (userId) => edgesFor(pool, userId),
    withSession: (principal, fn) => withSession(pool, principal, fn)
  };
}
export {
  CHALLENGE_TTL_MS,
  PIN_LOCKOUT_MS,
  PIN_MAX_ATTEMPTS,
  activeCustodyOrderFor,
  attemptPinFor,
  availabilityFor,
  childCtxFor,
  consumeChallenge,
  createChallenge,
  createPool,
  dbPort,
  deactivateAccount,
  edgesFor,
  guardiansOfChild,
  persistCapturedMessage,
  pinCredentialFor,
  rawExportBundleFor,
  recordPinAttempt,
  setAvailabilityWindows,
  setPinCredential,
  storeWebauthnCredential,
  updateWebauthnSignCount,
  webauthnCredentialById,
  webauthnCredentialsForUser,
  withSession,
  withSystemSession
};
