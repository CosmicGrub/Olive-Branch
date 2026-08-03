-- ============================================================================
--  OLIVE BRANCH — auth credentials, PIN storage, reaper support
--  MASTERFILE §7.1, §10.1. Closes the §20.2 storage/retention exposure.
-- ============================================================================

BEGIN;

-- ------------------------------------------------------------ credentials ----
-- Passkeys for adults. No shared secret is stored, so a database disclosure
-- does not yield anything that can authenticate.
CREATE TABLE webauthn_credential (
  credential_id  text PRIMARY KEY,          -- base64url
  user_id        uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  public_key_pem text NOT NULL,
  sign_count     bigint NOT NULL DEFAULT 0,
  aaguid         text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  last_used_at   timestamptz
);
CREATE INDEX ON webauthn_credential (user_id);

-- Challenges are single-use and short-lived. Persisted so a replay is caught
-- across processes, not merely within one.
CREATE TABLE webauthn_challenge (
  challenge   text PRIMARY KEY,
  user_id     uuid REFERENCES app_user(id) ON DELETE CASCADE,
  issued_at   timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz
);
CREATE INDEX ON webauthn_challenge (issued_at) WHERE consumed_at IS NULL;

-- ------------------------------------------------------------------- PINs ----
-- Child unlock PIN and guardian escalation PIN. scrypt with per-PIN salt; the
-- column holds the full parameterised string so cost can be raised later
-- without invalidating existing hashes.
CREATE TABLE pin_credential (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  kind         text NOT NULL CHECK (kind IN ('child_unlock','guardian_escalation')),
  child_id     uuid REFERENCES child(id) ON DELETE CASCADE,
  user_id      uuid REFERENCES app_user(id) ON DELETE CASCADE,
  pin_hash     text NOT NULL,
  failed_count smallint NOT NULL DEFAULT 0,
  cooldown_until timestamptz,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pin_has_exactly_one_subject CHECK (
    (kind = 'child_unlock'        AND child_id IS NOT NULL AND user_id IS NULL) OR
    (kind = 'guardian_escalation' AND user_id  IS NOT NULL AND child_id IS NULL)
  ),
  CONSTRAINT pin_hash_is_parameterised CHECK (pin_hash LIKE 'scrypt$%')
);
CREATE UNIQUE INDEX ON pin_credential (kind, child_id) WHERE child_id IS NOT NULL;
CREATE UNIQUE INDEX ON pin_credential (kind, user_id)  WHERE user_id  IS NOT NULL;

-- PIN material must never be readable by a child session, even its own hash.
ALTER TABLE pin_credential ENABLE ROW LEVEL SECURITY;
ALTER TABLE pin_credential FORCE  ROW LEVEL SECURITY;
CREATE POLICY pin_no_child_read ON pin_credential
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

-- --------------------------------------------------------------- tombstone ----
-- A blob whose delete failed. The artifact row is deliberately LEFT IN PLACE so
-- the media stays discoverable; this table drives retry. An undiscoverable blob
-- of a child's face is the failure mode the reaper exists to avoid.
CREATE TABLE reap_tombstone (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  artifact_id  uuid NOT NULL REFERENCES media_artifact(id) ON DELETE CASCADE,
  storage_key  text NOT NULL,
  error        text NOT NULL,
  attempts     smallint NOT NULL DEFAULT 1,
  first_seen   timestamptz NOT NULL DEFAULT now(),
  last_attempt timestamptz NOT NULL DEFAULT now(),
  UNIQUE (artifact_id)
);

-- Artifacts whose retention has lapsed. Preserved rows are excluded by the
-- predicate, not by the caller remembering to.
CREATE OR REPLACE FUNCTION artifacts_due_for_reaping(p_limit int DEFAULT 500)
RETURNS TABLE (artifact_id uuid, storage_key text, preserved boolean,
               expires_at timestamptz) AS $$
  SELECT m.id, m.storage_key, m.preserved, m.expires_at
    FROM media_artifact m
   WHERE m.preserved = false
     AND m.expires_at IS NOT NULL
     AND m.expires_at <= now()
     AND NOT EXISTS (SELECT 1 FROM reap_tombstone t WHERE t.artifact_id = m.id)
   ORDER BY m.expires_at
   LIMIT p_limit;
$$ LANGUAGE sql STABLE;

-- Monitoring. A tombstone older than a day is a retention breach in progress.
CREATE OR REPLACE VIEW retention_breach AS
SELECT t.artifact_id, t.storage_key, t.attempts, t.first_seen,
       now() - t.first_seen AS overdue_by
  FROM reap_tombstone t
 WHERE t.first_seen < now() - interval '1 day';

COMMIT;
