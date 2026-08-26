import pg from "pg";
import { DateTime } from "luxon";
import { newChallenge, verifyPin } from "../../auth/src/auth.ts";
import { can } from "../../family-graph/src/authorize.ts";
import {
  verifyChain,
  certify,
  authorizeExport,
  append
} from "../../ledger/src/ledger.ts";
import { sha256Hex } from "../../ledger/src/sha256.ts";
import {
  handover
} from "../../archive/src/archive.ts";
function createPool(connectionString) {
  const pool = new pg.Pool({ connectionString });
  pool.on("error", (err) => {
    console.error("pg pool: idle client error (pool recovers on next query)", err);
  });
  return pool;
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
              effective_to::text AS effective_to,
              side_a_guardian_id, side_b_guardian_id
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
      effectiveTo: r.effective_to,
      // db/migrations/0024_custody_order_side_guardians.sql — NULL on every
      // legacy row (honest "unmapped", never guessed). See Order's own
      // field comment (schedule.ts) for the full reasoning.
      sideAGuardianId: r.side_a_guardian_id,
      sideBGuardianId: r.side_b_guardian_id
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
async function parentGuardiansOfChild(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT DISTINCT eg.user_id, u.display_name
         FROM effective_guardianship eg
         JOIN app_user u ON u.id = eg.user_id
        WHERE eg.child_id = $1 AND eg.role = 'guardian'`,
      [childId]
    );
    return rows.map((r) => ({ userId: r.user_id, name: r.display_name }));
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
    const [row] = await q(
      `SELECT deactivated_at FROM app_user WHERE id = $1 FOR UPDATE`,
      [userId]
    );
    if (row?.deactivated_at) {
      throw Object.assign(
        new Error("setPinCredential: account is deactivated"),
        { code: "account_deactivated" }
      );
    }
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
    const [row] = await q(
      `SELECT deactivated_at FROM app_user WHERE id = $1 FOR UPDATE`,
      [userId]
    );
    if (row?.deactivated_at) {
      throw Object.assign(
        new Error("storeWebauthnCredential: account is deactivated"),
        { code: "account_deactivated" }
      );
    }
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
async function themeFor(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT theme_palette, theme_brightness
         FROM child_theme_preference
        WHERE child_id = $1 AND theme_palette IS NOT NULL`,
      [childId]
    );
    if (!rows.length) return null;
    const r = rows[0];
    return { themePalette: r.theme_palette, themeBrightness: r.theme_brightness };
  });
}
async function setChildTheme(pool, guardianId, childId, theme) {
  await withSession(
    pool,
    { roleName: "guardian", userId: guardianId, childId: null },
    async (q) => {
      await q(
        `INSERT INTO child_theme_preference (child_id, theme_palette, theme_brightness, updated_at)
         VALUES ($1, $2, $3, now())
         ON CONFLICT (child_id) DO UPDATE
           SET theme_palette = EXCLUDED.theme_palette,
               theme_brightness = EXCLUDED.theme_brightness,
               updated_at = now()`,
        [childId, theme.themePalette, theme.themeBrightness]
      );
    }
  );
}
async function recordCallStart(pool, input) {
  await withSystemSession(pool, async (q) => {
    await q(
      `INSERT INTO call_log
         (id, child_id, started_by, participant_ids, room_name, ladder_step, recorded, rang)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        input.id,
        input.childId,
        input.startedBy,
        input.participantIds,
        input.roomName,
        input.ladderStep,
        input.recorded,
        input.rang
      ]
    );
  });
}
async function recordCallEnd(pool, childId, sessionId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `UPDATE call_log SET ended_at = now()
        WHERE id = $1 AND child_id = $2 AND ended_at IS NULL
        RETURNING id`,
      [sessionId, childId]
    );
    return rows.length > 0;
  });
}
async function deactivateAccount(pool, userId, callerRoleName = "guardian") {
  if (!userId) throw new Error("deactivateAccount: userId required");
  if (callerRoleName === "child") {
    throw new Error("deactivateAccount: a child role cannot deactivate an account \u2014 children have no login of their own to delete (\xA711)");
  }
  return withSession(pool, { roleName: "system", userId, childId: null }, async (q) => {
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
      `DELETE FROM pin_credential WHERE user_id = $1 RETURNING user_id`,
      [userId]
    );
    const passkeys = await q(
      `DELETE FROM webauthn_credential WHERE user_id = $1 RETURNING credential_id`,
      [userId]
    );
    const challenges = await q(
      `DELETE FROM auth_challenge WHERE user_id = $1 RETURNING challenge`,
      [userId]
    );
    const deviceTokens = await q(
      `DELETE FROM device_token WHERE owner_user_id = $1 RETURNING id`,
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
      removedWebauthnChallenges: challenges.length,
      removedDeviceTokens: deviceTokens.length
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
async function loadCallLog(q, childId) {
  const rows = await q(
    `SELECT cl.id, cl.started_by, u.display_name AS started_by_name,
            cl.participant_ids, cl.ladder_step, cl.recorded, cl.rang,
            cl.started_at::text, cl.ended_at::text
       FROM call_log cl
       JOIN app_user u ON u.id = cl.started_by
      WHERE cl.child_id = $1
      ORDER BY cl.started_at ASC`,
    [childId]
  );
  return rows.map((r) => ({
    id: r.id,
    startedBy: r.started_by,
    startedByName: r.started_by_name ?? null,
    participantIds: r.participant_ids,
    ladderStep: r.ladder_step,
    recorded: r.recorded,
    rang: r.rang,
    startedAt: r.started_at,
    endedAt: r.ended_at ?? null
  }));
}
async function assembleRawExportBundle(q, childId, requester, journalRows) {
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
  const logRows = await q(
    `SELECT seq, author_id, at::text, body, prev_hash, hash
       FROM message_log WHERE child_id = $1 ORDER BY seq ASC`,
    [childId]
  );
  const callLogRows = await loadCallLog(q, childId);
  const bundle = {
    childId,
    childName: childRows[0]?.display_name ?? null,
    generatedAt: (/* @__PURE__ */ new Date()).toISOString(),
    requestedByUserId: "userId" in requester ? requester.userId : null,
    requestedByChildId: "childId" in requester ? requester.childId : null,
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
    })),
    callLog: callLogRows
  };
  const serialized = JSON.stringify(bundle);
  const bundleHash = sha256Hex(serialized);
  return { bundle, serialized, bundleHash };
}
async function rawExportBundleFor(pool, principal, childId) {
  if (principal.roleName === "child") {
    throw new Error(
      "rawExportBundleFor: child-self export is not implemented here (see takeAndGo() for the real, majority-gated child export path)"
    );
  }
  if (!principal.userId) {
    throw new Error("rawExportBundleFor: non-child principal missing userId");
  }
  const requesterId = principal.userId;
  const edges = await edgesFor(pool, requesterId);
  const rbac = can("export.raw", edges, childId, /* @__PURE__ */ new Date());
  if (!rbac.allow) return { ok: false, reason: rbac.reason };
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
    const journalRows = await q(
      `SELECT id, body, media_ref, created_at::text
         FROM child_journal_entry WHERE child_id = $1 ORDER BY created_at ASC`,
      [childId]
    );
    const { bundle, serialized, bundleHash } = await assembleRawExportBundle(q, childId, { userId: requesterId }, journalRows);
    const inserted = await q(
      `INSERT INTO export_record (child_id, requested_by, kind, was_free, bundle_hash)
       VALUES ($1, $2, 'raw', true, $3) RETURNING id::text`,
      [childId, requesterId, bundleHash]
    );
    return { ok: true, bundle, serialized, recordId: inserted[0].id, bundleHash };
  });
}
async function takeAndGo(pool, childId, now = /* @__PURE__ */ new Date()) {
  if (!childId) throw new Error("takeAndGo: childId required");
  const journalRows = await withSession(
    pool,
    { roleName: "child", userId: null, childId },
    (q) => q(
      `SELECT id, body, media_ref, created_at::text
                 FROM child_journal_entry WHERE child_id = $1 ORDER BY created_at ASC`,
      [childId]
    )
  );
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT id, birth_date::text, majority_age, handed_over_at::text, deceased_at::text
         FROM child WHERE id = $1 FOR UPDATE`,
      [childId]
    );
    if (!rows.length) {
      throw Object.assign(new Error("takeAndGo: no such child"), { code: "child_not_found" });
    }
    const c = rows[0];
    const artifactRows = await q(
      `SELECT id, kind, storage_key AS "storageKey", captured_at::text AS "capturedAt",
              captured_tz AS "capturedTz", preserved, era_tag AS "eraTag", author_id AS "authorId"
         FROM media_artifact WHERE child_id = $1 AND preserved = true`,
      [childId]
    );
    const artifacts = artifactRows.map((r) => ({
      id: r.id,
      childId,
      kind: r.kind,
      storageKey: r.storageKey,
      capturedAt: r.capturedAt,
      capturedTz: r.capturedTz,
      preserved: r.preserved,
      eraTag: r.eraTag,
      authorId: r.authorId
    }));
    const child = {
      id: c.id,
      birthDate: c.birth_date,
      majorityAge: c.majority_age,
      handedOverAt: c.handed_over_at,
      deceasedAt: c.deceased_at
    };
    const h = handover(child, artifacts, journalRows.length, DateTime.fromJSDate(now));
    if (!h.ok) return { ok: false, reason: h.reason };
    const { bundle, serialized, bundleHash } = await assembleRawExportBundle(q, childId, { childId }, journalRows);
    const inserted = await q(
      `INSERT INTO export_record (child_id, requested_by_child_id, kind, was_free, bundle_hash)
       VALUES ($1, $2, 'raw', true, $3) RETURNING id::text`,
      [childId, childId, bundleHash]
    );
    const closed = await q(
      `UPDATE guardianship SET closed_at = $2, closed_reason = 'majority'
        WHERE child_id = $1 AND closed_at IS NULL
        RETURNING id`,
      [childId, now.toISOString()]
    );
    const updated = await q(
      `UPDATE child SET handed_over_at = $2 WHERE id = $1 AND handed_over_at IS NULL
        RETURNING id`,
      [childId, now.toISOString()]
    );
    if (updated.length !== 1) {
      throw new Error(`takeAndGo: expected to hand over exactly 1 child row, affected ${updated.length}`);
    }
    return { ok: true, result: {
      childId,
      // `now.toISOString()` directly, not a round trip through Postgres's
      // own `::text` cast — matching every other client-facing timestamp
      // this file produces (rawExportBundleFor()'s `generatedAt`,
      // certifiedExportBundleFor()'s `attestation.at`), never Postgres's own
      // `timestamptz::text` format (space-separated, no 'T'), which nothing
      // else in this codebase hands to a client and no client here parses.
      handedOverAt: now.toISOString(),
      guardianshipsClosed: closed.length,
      artifactsTransferred: h.result.transferred.artifacts,
      journalEntriesTransferred: h.result.transferred.journalEntries,
      exportRecordId: inserted[0].id,
      bundle,
      serialized,
      bundleHash
    } };
  });
}
async function persistCapturedMessage(pool, capture, opts = {}) {
  return withSystemSession(pool, async (q) => {
    const a = capture.artifact;
    const artifactRows = await q(
      `INSERT INTO media_artifact
         (child_id, author_id, author_child_id, kind, storage_key, duration_ms,
          caption_key, captured_at, captured_tz, era_tag, preserved, preserved_by,
          preserved_at, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8::timestamptz,$9,$10,$11,$12,
               $13::timestamptz,$14::timestamptz)
       RETURNING id`,
      [
        a.childId,
        a.authorId,
        a.authorChildId,
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
      if (!i.senderId) {
        throw new Error(
          "persistCapturedMessage: opts.newBatch requires an app_user sender (intent_batch.sender_id is NOT NULL) \u2014 a child-originated capture (senderChildId set) cannot start a batch."
        );
      }
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
         (child_id, sender_id, sender_child_id, payload_kind, payload_ref,
          policy, target_local_date, target_daypart, batch_id, batch_seq,
          state, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6::delivery_policy,$7::date,$8,$9,$10,$11,
               $12::timestamptz)
       RETURNING id`,
      [
        i.childId,
        i.senderId,
        i.senderChildId,
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
async function mediaArtifactFor(pool, childId, artifactId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT storage_key, kind FROM media_artifact WHERE id = $1 AND child_id = $2`,
      [artifactId, childId]
    );
    if (!rows.length) return null;
    return { storageKey: rows[0].storage_key, kind: rows[0].kind };
  });
}
async function registerDeviceToken(pool, principal, platform, token, channel) {
  if (principal.roleName === "system") {
    throw new Error("registerDeviceToken: system role cannot own a device");
  }
  const isChild = principal.roleName === "child";
  const ownerUserId = isChild ? null : principal.userId;
  const ownerChildId = isChild ? principal.childId : null;
  if (!isChild) {
    const [row] = await withSystemSession(
      pool,
      (q) => q(`SELECT deactivated_at FROM app_user WHERE id = $1`, [ownerUserId])
    );
    if (row?.deactivated_at) {
      throw Object.assign(
        new Error("registerDeviceToken: account is deactivated"),
        { code: "account_deactivated" }
      );
    }
  }
  const upsert = () => withSession(pool, principal, async (q) => {
    const rows = await q(
      `INSERT INTO device_token (owner_user_id, owner_child_id, platform, token, channel, last_seen_at)
       VALUES ($1, $2, $3, $4, $5, now())
       ON CONFLICT (token) DO UPDATE
         SET owner_user_id  = EXCLUDED.owner_user_id,
             owner_child_id = EXCLUDED.owner_child_id,
             platform       = EXCLUDED.platform,
             -- COALESCE, not a bare overwrite: a re-registration call that
             -- doesn't know the channel (channel arg omitted -> NULL here)
             -- must never clobber an already-known value from an earlier
             -- call that did. Every current call site is deterministic per
             -- device (push_channel.dart always passes the same value for
             -- the same platform), so this is a no-op today \u2014 it's future
             -- defense for the day a real native-detection caller exists
             -- and might not always resolve one.
             channel        = COALESCE(EXCLUDED.channel, device_token.channel),
             last_seen_at   = now()
       RETURNING id`,
      [ownerUserId, ownerChildId, platform, token, channel ?? null]
    );
    return rows[0].id;
  });
  try {
    return await upsert();
  } catch (e) {
    const isRlsDenial = e?.code === "42501" && String(e?.message ?? "").includes("row-level security policy");
    if (!isRlsDenial) throw e;
    await withSystemSession(pool, (q) => q(`DELETE FROM device_token WHERE token = $1`, [token]));
    return upsert();
  }
}
async function unregisterDeviceToken(pool, principal, token) {
  return withSession(pool, principal, async (q) => {
    const rows = await q(`DELETE FROM device_token WHERE token = $1 RETURNING id`, [token]);
    return rows.length > 0;
  });
}
async function deviceTokensFor(pool, owner) {
  return withSystemSession(pool, async (q) => {
    const rows = "userId" in owner ? await q(
      `SELECT id, platform, token, channel FROM device_token WHERE owner_user_id = $1`,
      [owner.userId]
    ) : await q(
      `SELECT id, platform, token, channel FROM device_token WHERE owner_child_id = $1`,
      [owner.childId]
    );
    return rows.map((r) => ({ id: r.id, platform: r.platform, token: r.token, channel: r.channel ?? null }));
  });
}
async function removeDeviceTokenSystem(pool, id) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(`DELETE FROM device_token WHERE id = $1 RETURNING id`, [id]);
    return rows.length > 0;
  });
}
async function loadMessageChain(q, childId) {
  const rows = await q(
    `SELECT seq, author_id,
            to_char(at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS at,
            body, prev_hash, hash
       FROM message_log WHERE child_id = $1 ORDER BY seq ASC`,
    [childId]
  );
  return rows.map((r) => ({
    seq: Number(r.seq),
    childId,
    authorId: r.author_id,
    at: r.at,
    body: r.body,
    prevHash: r.prev_hash,
    hash: r.hash
  }));
}
async function appendHandoverNote(pool, actorRole, actorUserId, childId, body) {
  return withSession(pool, { roleName: actorRole, userId: actorUserId, childId: null }, async (q) => {
    await q(`SELECT pg_advisory_xact_lock(hashtext($1)::bigint)`, [`handover-notes:${childId}`]);
    const tip = await q(
      `SELECT seq, hash FROM message_log WHERE child_id = $1 ORDER BY seq DESC LIMIT 1`,
      [childId]
    );
    const tipChain = tip.length ? [{
      seq: Number(tip[0].seq),
      childId,
      authorId: "",
      at: "",
      body: "",
      prevHash: "",
      hash: tip[0].hash
    }] : [];
    const at = (/* @__PURE__ */ new Date()).toISOString();
    const entry = append(tipChain, { childId, authorId: actorUserId, at, body });
    await q(
      `INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash)
       VALUES ($1, $2, $3, $4::timestamptz, $5, $6, $7)`,
      [childId, entry.seq, actorUserId, at, body, entry.prevHash, entry.hash]
    );
    return entry;
  });
}
async function handoverNotesFor(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT ml.seq, ml.author_id, u.display_name AS author_name,
              to_char(ml.at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS at,
              ml.body
         FROM message_log ml JOIN app_user u ON u.id = ml.author_id
        WHERE ml.child_id = $1 ORDER BY ml.seq ASC`,
      [childId]
    );
    return rows.map((r) => ({
      seq: Number(r.seq),
      authorId: r.author_id,
      authorName: r.author_name,
      at: r.at,
      body: r.body
    }));
  });
}
const EXPENSE_ROW_COLUMNS = `
  id, child_id, paid_by, description, amount_cents, category,
  to_char(incurred_on, 'YYYY-MM-DD') AS incurred_on,
  receipt_key, split_rule, status,
  to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at
`;
function rowToExpense(r, paidByName = null) {
  return {
    id: r.id,
    childId: r.child_id,
    paidById: r.paid_by,
    paidByName,
    description: r.description,
    amountCents: Number(r.amount_cents),
    category: r.category,
    incurredOn: r.incurred_on,
    receiptKey: r.receipt_key,
    splitRule: r.split_rule,
    status: r.status,
    createdAt: r.created_at
  };
}
async function proposeExpense(pool, actorRole, actorUserId, childId, input) {
  return withSession(pool, { roleName: actorRole, userId: actorUserId, childId: null }, async (q) => {
    const rows = await q(
      `INSERT INTO expense (child_id, paid_by, description, amount_cents, category, incurred_on, receipt_key, split_rule)
       VALUES ($1, $2, $3, $4, $5, $6::date, $7, $8::jsonb)
       RETURNING ${EXPENSE_ROW_COLUMNS}`,
      [
        childId,
        actorUserId,
        input.description,
        input.amountCents,
        input.category,
        input.incurredOn,
        input.receiptKey ?? null,
        JSON.stringify({ payerSharePercent: input.payerSharePercent })
      ]
    );
    return rowToExpense(rows[0]);
  });
}
async function expensesFor(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT e.id, e.child_id, e.paid_by, u.display_name AS paid_by_name,
              e.description, e.amount_cents, e.category,
              to_char(e.incurred_on, 'YYYY-MM-DD') AS incurred_on,
              e.receipt_key, e.split_rule, e.status,
              to_char(e.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at
         FROM expense e JOIN app_user u ON u.id = e.paid_by
        WHERE e.child_id = $1 ORDER BY e.created_at DESC`,
      [childId]
    );
    return rows.map((r) => rowToExpense(r, r.paid_by_name));
  });
}
const EXPENSE_RESOLUTIONS = {
  accept: "accepted",
  dispute: "disputed",
  reimburse: "reimbursed"
};
async function resolveExpense(pool, actorRole, actorUserId, childId, expenseId, action) {
  const status = EXPENSE_RESOLUTIONS[action];
  if (!status) throw Object.assign(
    new Error(`unknown expense resolution: ${action}`),
    { code: "unknown_resolution" }
  );
  return withSession(pool, { roleName: actorRole, userId: actorUserId, childId: null }, async (q) => {
    const rows = await q(
      `UPDATE expense SET status = $1 WHERE id = $2 AND child_id = $3
       RETURNING ${EXPENSE_ROW_COLUMNS}`,
      [status, expenseId, childId]
    );
    return rows.length ? rowToExpense(rows[0]) : null;
  });
}
async function medicationsFor(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT id, name, dose, slots, is_prn, min_gap_hours
         FROM medication WHERE child_id = $1 AND active ORDER BY created_at ASC`,
      [childId]
    );
    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      dose: r.dose,
      slots: r.slots,
      isPrn: r.is_prn,
      minGapHours: r.min_gap_hours === null ? null : Number(r.min_gap_hours)
    }));
  });
}
async function dosesForDate(pool, childId, localDate) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT d.id, d.medication_id, to_char(d.local_date, 'YYYY-MM-DD') AS local_date,
              d.slot, to_char(d.administered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS administered_at,
              d.by_user_id, u.display_name AS by_user_name, d.status
         FROM medication_dose d JOIN app_user u ON u.id = d.by_user_id
        WHERE d.child_id = $1 AND d.local_date = $2::date
        ORDER BY d.administered_at ASC`,
      [childId, localDate]
    );
    return rows.map((r) => ({
      id: r.id,
      medicationId: r.medication_id,
      localDate: r.local_date,
      slot: r.slot,
      administeredAt: r.administered_at,
      byUserId: r.by_user_id,
      byUserName: r.by_user_name,
      status: r.status
    }));
  });
}
async function recordDose(pool, actorRole, actorUserId, childId, medicationId, localDate, slot, status) {
  return withSession(pool, { roleName: actorRole, userId: actorUserId, childId: null }, async (q) => {
    const rows = await q(
      `INSERT INTO medication_dose
         (medication_id, child_id, local_date, slot, administered_at, by_user_id, status)
       VALUES ($1, $2, $3::date, $4, now(), $5, $6)
       ON CONFLICT (medication_id, local_date, slot) WHERE status = 'given' DO NOTHING
       RETURNING id, medication_id,
                 to_char(local_date, 'YYYY-MM-DD') AS local_date, slot,
                 to_char(administered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS administered_at,
                 by_user_id, status`,
      [medicationId, childId, localDate, slot, actorUserId, status]
    );
    if (rows.length) {
      const r = rows[0];
      return { ok: true, dose: {
        id: r.id,
        medicationId: r.medication_id,
        localDate: r.local_date,
        slot: r.slot,
        administeredAt: r.administered_at,
        byUserId: r.by_user_id,
        byUserName: "",
        status: r.status
      } };
    }
    const clash = await q(
      `SELECT d.by_user_id, u.display_name AS by_user_name,
              to_char(d.administered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS administered_at
         FROM medication_dose d JOIN app_user u ON u.id = d.by_user_id
        WHERE d.medication_id = $1 AND d.local_date = $2::date AND d.slot = $3 AND d.status = 'given'
        LIMIT 1`,
      [medicationId, localDate, slot]
    );
    return {
      ok: false,
      blockedBy: clash[0]?.by_user_name ?? "another guardian",
      blockedAtIso: clash[0]?.administered_at ?? ""
    };
  });
}
async function medicalRecordFor(pool, childId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(
      `SELECT blood_type, allergies, conditions, pediatrician_name, pediatrician_practice,
              pediatrician_phone, insurance_provider, insurance_member_id
         FROM medical_record WHERE child_id = $1`,
      [childId]
    );
    const guardianRows = await q(
      `SELECT g.user_id, u.display_name, u.phone_e164
         FROM guardianship g JOIN app_user u ON u.id = g.user_id
        WHERE g.child_id = $1 AND g.role = 'guardian' AND g.closed_at IS NULL
              AND g.valid @> now()
        ORDER BY u.display_name ASC`,
      [childId]
    );
    const medications = await medicationsFor(pool, childId);
    const r = rows[0];
    return {
      bloodType: r?.blood_type ?? null,
      allergies: r?.allergies ?? [],
      conditions: r?.conditions ?? [],
      pediatricianName: r?.pediatrician_name ?? null,
      pediatricianPractice: r?.pediatrician_practice ?? null,
      pediatricianPhone: r?.pediatrician_phone ?? null,
      insuranceProvider: r?.insurance_provider ?? null,
      insuranceMemberId: r?.insurance_member_id ?? null,
      guardians: guardianRows.map((g) => ({ userId: g.user_id, name: g.display_name, phone: g.phone_e164 })),
      medications
    };
  });
}
async function setMedicalRecord(pool, actorRole, actorUserId, childId, fields) {
  await withSession(pool, { roleName: actorRole, userId: actorUserId, childId: null }, async (q) => {
    await q(
      `INSERT INTO medical_record
         (child_id, blood_type, allergies, conditions, pediatrician_name, pediatrician_practice,
          pediatrician_phone, insurance_provider, insurance_member_id, updated_at, updated_by)
       VALUES ($1, $2, $3::jsonb, $4::jsonb, $5, $6, $7, $8, $9, now(), $10)
       ON CONFLICT (child_id) DO UPDATE SET
         blood_type = EXCLUDED.blood_type, allergies = EXCLUDED.allergies,
         conditions = EXCLUDED.conditions, pediatrician_name = EXCLUDED.pediatrician_name,
         pediatrician_practice = EXCLUDED.pediatrician_practice,
         pediatrician_phone = EXCLUDED.pediatrician_phone,
         insurance_provider = EXCLUDED.insurance_provider,
         insurance_member_id = EXCLUDED.insurance_member_id,
         updated_at = now(), updated_by = EXCLUDED.updated_by`,
      [
        childId,
        fields.bloodType ?? null,
        JSON.stringify(fields.allergies ?? []),
        JSON.stringify(fields.conditions ?? []),
        fields.pediatricianName ?? null,
        fields.pediatricianPractice ?? null,
        fields.pediatricianPhone ?? null,
        fields.insuranceProvider ?? null,
        fields.insuranceMemberId ?? null,
        actorUserId
      ]
    );
  });
}
async function certifiedExportBundleFor(pool, requestedBy, childId, now = /* @__PURE__ */ new Date()) {
  const edges = await edgesFor(pool, requestedBy);
  const rbac = can("export.certified", edges, childId, now, void 0, { court: true });
  if (!rbac.allow) return { ok: false, reason: rbac.reason };
  return withSystemSession(pool, async (q) => {
    const tierRows = await q(
      `SELECT court_tier FROM app_user WHERE id = $1 FOR UPDATE`,
      [requestedBy]
    );
    const courtTier = tierRows[0]?.court_tier ?? false;
    const countRows = await q(
      `SELECT count(*)::int AS n FROM export_record
        WHERE requested_by = $1 AND kind = 'certified'
          AND created_at > now() - interval '12 months'`,
      [requestedBy]
    );
    const certifiedInLast12Months = countRows[0]?.n ?? 0;
    const auth = authorizeExport({
      kind: "certified",
      childId,
      requestedBy,
      courtTier,
      certifiedInLast12Months
    });
    if (!auth.ok) return { ok: false, reason: auth.reason };
    const chain = await loadMessageChain(q, childId);
    const verification = verifyChain(chain);
    if (!verification.ok) {
      return { ok: false, reason: "chain_broken", faults: verification.faults };
    }
    const callLog = await loadCallLog(q, childId);
    const attestation = certify(chain, childId, now.toISOString());
    const bundleHash = sha256Hex(JSON.stringify({ chain, attestation, callLog }));
    const inserted = await q(
      `INSERT INTO export_record (child_id, requested_by, kind, was_free, head_hash, bundle_hash)
       VALUES ($1, $2, 'certified', $3, $4, $5)
       RETURNING id`,
      [childId, requestedBy, auth.free, attestation.headHash, bundleHash]
    );
    return {
      ok: true,
      free: auth.free,
      chain,
      attestation,
      callLog,
      bundleHash,
      exportRecordId: inserted[0].id
    };
  });
}
const INVITABLE_ROLES = [
  "guardian",
  "trusted_adult",
  "step_parent",
  "sitter",
  "coordinator"
];
function rowToInvite(r) {
  return {
    id: r.id,
    childId: r.child_id,
    invitedBy: r.invited_by,
    invitedEmail: r.invited_email,
    role: r.role,
    label: r.label,
    createdAt: r.created_at,
    expiresAt: r.expires_at,
    acceptedAt: r.accepted_at,
    revokedAt: r.revoked_at
  };
}
async function createGuardianInvite(pool, invitedBy, childId, role, label, invitedEmail) {
  if (!INVITABLE_ROLES.includes(role)) {
    return { ok: false, reason: "invalid_role" };
  }
  return withSession(pool, { roleName: "guardian", userId: invitedBy, childId: null }, async (q) => {
    const rows = await q(
      `INSERT INTO guardian_invite (child_id, invited_by, invited_email, role, label)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [childId, invitedBy, invitedEmail, role, label]
    );
    return { ok: true, invite: rowToInvite(rows[0]) };
  });
}
async function getGuardianInvite(pool, inviteId) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1`, [inviteId]);
    return rows.length ? rowToInvite(rows[0]) : null;
  });
}
async function acceptGuardianInvite(pool, inviteId, now) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1 FOR UPDATE`, [inviteId]);
    if (!rows.length) return { ok: false, reason: "not_found" };
    const row = rows[0];
    if (row.revoked_at) return { ok: false, reason: "revoked" };
    if (row.accepted_at) return { ok: false, reason: "already_accepted" };
    if (new Date(row.expires_at) <= now) return { ok: false, reason: "expired" };
    const updated = await q(
      `UPDATE guardian_invite SET accepted_at = $2 WHERE id = $1 RETURNING *`,
      [inviteId, now.toISOString()]
    );
    return { ok: true, invite: rowToInvite(updated[0]) };
  });
}
async function revokeGuardianInvite(pool, inviteId, byUserId, now) {
  return withSession(pool, { roleName: "guardian", userId: byUserId, childId: null }, async (q) => {
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1 FOR UPDATE`, [inviteId]);
    if (!rows.length) return { ok: false, reason: "not_found" };
    if (rows[0].accepted_at) return { ok: false, reason: "already_accepted" };
    if (!rows[0].revoked_at) {
      await q(`UPDATE guardian_invite SET revoked_at = $2 WHERE id = $1`, [inviteId, now.toISOString()]);
    }
    return { ok: true };
  });
}
async function bootstrapGuardianInvite(pool, inviteId, displayName, now) {
  return withSystemSession(pool, async (q) => {
    const rows = await q(`SELECT * FROM guardian_invite WHERE id = $1 FOR UPDATE`, [inviteId]);
    if (!rows.length) return { ok: false, reason: "not_found" };
    const row = rows[0];
    if (row.revoked_at) return { ok: false, reason: "revoked" };
    if (!row.accepted_at) return { ok: false, reason: "not_accepted" };
    if (new Date(row.expires_at) <= now) return { ok: false, reason: "expired" };
    if (row.bootstrapped_at) return { ok: false, reason: "already_bootstrapped" };
    const existing = await q(`SELECT id FROM app_user WHERE email = $1`, [row.invited_email]);
    if (existing.length) return { ok: false, reason: "email_already_registered" };
    const child = await q(`SELECT home_tz FROM child WHERE id = $1`, [row.child_id]);
    let userId;
    try {
      const inserted = await q(
        `INSERT INTO app_user (email, display_name, home_tz)
         VALUES ($1, $2, $3) RETURNING id`,
        [row.invited_email, displayName, child[0].home_tz]
      );
      userId = inserted[0].id;
    } catch (e) {
      if (e?.code === "23505") return { ok: false, reason: "email_already_registered" };
      throw e;
    }
    await q(
      `UPDATE guardian_invite SET bootstrapped_at = $2, bootstrap_user_id = $3 WHERE id = $1`,
      [inviteId, now.toISOString(), userId]
    );
    return { ok: true, userId, childId: row.child_id };
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
  EXPENSE_RESOLUTIONS,
  INVITABLE_ROLES,
  PIN_LOCKOUT_MS,
  PIN_MAX_ATTEMPTS,
  acceptGuardianInvite,
  activeCustodyOrderFor,
  appendHandoverNote,
  attemptPinFor,
  availabilityFor,
  bootstrapGuardianInvite,
  certifiedExportBundleFor,
  childCtxFor,
  consumeChallenge,
  createChallenge,
  createGuardianInvite,
  createPool,
  dbPort,
  deactivateAccount,
  deviceTokensFor,
  dosesForDate,
  edgesFor,
  expensesFor,
  getGuardianInvite,
  guardiansOfChild,
  handoverNotesFor,
  mediaArtifactFor,
  medicalRecordFor,
  medicationsFor,
  parentGuardiansOfChild,
  persistCapturedMessage,
  pinCredentialFor,
  proposeExpense,
  rawExportBundleFor,
  recordCallEnd,
  recordCallStart,
  recordDose,
  recordPinAttempt,
  registerDeviceToken,
  removeDeviceTokenSystem,
  resolveExpense,
  revokeGuardianInvite,
  setAvailabilityWindows,
  setChildTheme,
  setMedicalRecord,
  setPinCredential,
  storeWebauthnCredential,
  takeAndGo,
  themeFor,
  unregisterDeviceToken,
  updateWebauthnSignCount,
  webauthnCredentialById,
  webauthnCredentialsForUser,
  withSession,
  withSystemSession
};
