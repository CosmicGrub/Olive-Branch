-- ============================================================================
--  OLIVE BRANCH -- encrypted family backup: the SERVER half (nothing is lost)
--
--  A grown-up's phone is lost, broken or wiped. The family's records, drawings,
--  scores, memories and messages must not go with it. The phone seals a backup
--  on the device BEFORE it leaves (the key is never on the server); this file
--  is where the server keeps the sealed result. The server only ever holds
--  opaque ciphertext plus the small amount of metadata listed in MASTERFILE
--  7.22 ("what the server can see"). It cannot read a backup, cannot tell what
--  is in one, and cannot quietly swap, drop or roll one back without the phone
--  noticing (every version is hash-chained and signed by the phone).
--
--  Tables (all ENABLE + FORCE row level security; see the policy notes):
--
--    backup_vault            one per family. The public half of the family's
--                            recovery key (so a restore can be tied to the
--                            paper key), the quota and the retention policy.
--    backup_vault_member     which grown-up accounts may use the vault, and
--                            whether another parent has PAUSED their reach.
--    backup_vault_helper     at most ONE trusted helper per vault (a single
--                            parent names one). A helper can only confirm or
--                            cancel a recovery; nothing else reads or writes.
--    backup_upload           one resumable, chunked upload (weak links).
--    backup_chunk            the ciphertext, in pieces. Immutable once written.
--    backup_version          a committed backup: sequence number, sizes, the
--                            ciphertext hash, the hash-chain link and the
--                            phone's own signature. Never deleted: a removed
--                            or aged-out version becomes a TOMBSTONE and its
--                            bytes are kept for a recovery window.
--    backup_restore_challenge a one-time challenge the new phone must sign
--                            with the family's recovery key to start a restore.
--    backup_restore_request  a restore waiting for its waiting period, another
--                            parent's (or the helper's) yes, and anyone's
--                            cancel; then a one-time download token.
--    backup_vault_event      the plain-words notice feed every grown-up's
--                            device reads (content-free, server-templated).
--
--  Authority split (the same one pairing and invites already use): the first
--  lock is the ROUTE (server/family_backup_routes.mjs: guardian session,
--  device session, a live guardianship edge to join, the grown-up's own PIN for
--  the sensitive acts). The second lock is here: a guardian session can touch
--  the data tables only as an ACTIVE member of that vault, so a forgotten WHERE
--  in application code cannot read or write another family's backup. Writes to
--  the access-control tables (vault, member, helper) and to the restore state
--  machine are `system`-only: they happen inside one transaction behind the
--  route's checks, and the guardian role cannot forge them with SQL of its own.
--
--  Append-only integrity: triggers refuse any change to a committed version's
--  identity, size, hashes, chain link or signature; refuse every DELETE of a
--  version; refuse any change to a stored chunk or any chunk added to an upload
--  that is no longer open; and refuse deleting a chunk unless the bytes are
--  past their recovery window (or the upload never completed). So a bug, a
--  hostile session or a careless operator cannot overwrite or erase a backup.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- vault -----
CREATE TABLE backup_vault (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_by         uuid REFERENCES app_user(id) ON DELETE SET NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  -- Ed25519 public key derived on the phone from the family's recovery key.
  -- PUBLIC by construction (the phones also hold it to seal backups); it lets
  -- the server check that a restore request really comes from someone holding
  -- the paper key. The secret half never reaches the server.
  recovery_verifier  bytea NOT NULL CHECK (octet_length(recovery_verifier) = 32),
  -- bytes the family may store (live + recoverable + open uploads)
  quota_bytes        bigint NOT NULL CHECK (quota_bytes > 0),
  -- newest N live versions are kept; older ones become tombstones
  keep_versions      integer NOT NULL DEFAULT 10 CHECK (keep_versions BETWEEN 3 AND 100),
  -- how long a tombstoned version's bytes are kept before they may be purged
  recovery_window_days integer NOT NULL DEFAULT 180 CHECK (recovery_window_days BETWEEN 30 AND 730)
);

CREATE TABLE backup_vault_member (
  vault_id    uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  state       text NOT NULL DEFAULT 'active' CHECK (state IN ('active', 'paused')),
  joined_at   timestamptz NOT NULL DEFAULT now(),
  paused_at   timestamptz,
  paused_by   uuid REFERENCES app_user(id) ON DELETE SET NULL,
  PRIMARY KEY (vault_id, user_id),
  CONSTRAINT backup_member_pause_whole CHECK ((state = 'paused') = (paused_at IS NOT NULL))
);
CREATE INDEX backup_vault_member_user_idx ON backup_vault_member (user_id);

CREATE TABLE backup_vault_helper (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  vault_id    uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  named_by    uuid REFERENCES app_user(id) ON DELETE SET NULL,
  named_at    timestamptz NOT NULL DEFAULT now(),
  removed_at  timestamptz,
  removed_by  uuid REFERENCES app_user(id) ON DELETE SET NULL
);
-- at most ONE live helper per vault
CREATE UNIQUE INDEX backup_vault_helper_one_live_idx ON backup_vault_helper (vault_id) WHERE removed_at IS NULL;
CREATE INDEX backup_vault_helper_user_idx ON backup_vault_helper (user_id) WHERE removed_at IS NULL;

-- --------------------------------------------------------------- upload -----
CREATE TABLE backup_upload (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  vault_id      uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  user_id       uuid REFERENCES app_user(id) ON DELETE SET NULL,
  device_id     uuid REFERENCES paired_device(id) ON DELETE SET NULL,
  -- the phone's own id for this attempt: begin() is idempotent on it, so a
  -- lost response never leaves a second half-upload behind
  client_ref    text NOT NULL CHECK (char_length(client_ref) BETWEEN 8 AND 64),
  base_seq      bigint NOT NULL CHECK (base_seq >= 0),
  seq           bigint NOT NULL CHECK (seq >= 1),
  size_bytes    bigint NOT NULL CHECK (size_bytes > 0),
  chunk_size    integer NOT NULL CHECK (chunk_size BETWEEN 1024 AND 4194304),
  chunk_count   integer NOT NULL CHECK (chunk_count >= 1),
  blob_sha256   bytea NOT NULL CHECK (octet_length(blob_sha256) = 32),
  prev_chain_hash bytea NOT NULL CHECK (octet_length(prev_chain_hash) = 32),
  chain_hash    bytea NOT NULL CHECK (octet_length(chain_hash) = 32),
  manifest      bytea NOT NULL CHECK (octet_length(manifest) BETWEEN 1 AND 4096),
  signature     bytea NOT NULL CHECK (octet_length(signature) BETWEEN 16 AND 512),
  state         text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'committed', 'aborted', 'expired')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  committed_at  timestamptz,
  CONSTRAINT backup_upload_expiry CHECK (expires_at > created_at),
  CONSTRAINT backup_upload_committed_whole CHECK ((state = 'committed') = (committed_at IS NOT NULL)),
  UNIQUE (vault_id, device_id, client_ref)
);
CREATE INDEX backup_upload_vault_idx ON backup_upload (vault_id, state);

CREATE TABLE backup_chunk (
  upload_id   uuid NOT NULL REFERENCES backup_upload(id) ON DELETE CASCADE,
  idx         integer NOT NULL CHECK (idx >= 0),
  -- denormalised so quota is one indexed sum and RLS needs no join
  vault_id    uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  size_bytes  integer NOT NULL CHECK (size_bytes BETWEEN 1 AND 4194304),
  sha256      bytea NOT NULL CHECK (octet_length(sha256) = 32),
  data        bytea NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (upload_id, idx),
  CONSTRAINT backup_chunk_size_matches CHECK (octet_length(data) = size_bytes)
);
CREATE INDEX backup_chunk_vault_idx ON backup_chunk (vault_id);

-- -------------------------------------------------------------- version -----
CREATE TABLE backup_version (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  vault_id         uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  seq              bigint NOT NULL CHECK (seq >= 1),
  upload_id        uuid NOT NULL UNIQUE REFERENCES backup_upload(id),
  prev_chain_hash  bytea NOT NULL CHECK (octet_length(prev_chain_hash) = 32),
  chain_hash       bytea NOT NULL CHECK (octet_length(chain_hash) = 32),
  blob_sha256      bytea NOT NULL CHECK (octet_length(blob_sha256) = 32),
  size_bytes       bigint NOT NULL CHECK (size_bytes > 0),
  chunk_size       integer NOT NULL,
  chunk_count      integer NOT NULL,
  manifest         bytea NOT NULL,
  signature        bytea NOT NULL,
  device_id        uuid REFERENCES paired_device(id) ON DELETE SET NULL,
  uploaded_by      uuid REFERENCES app_user(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  -- tombstone: the version is hidden from the "live" list but its bytes stay
  state            text NOT NULL DEFAULT 'live' CHECK (state IN ('live', 'tombstone')),
  tombstone_reason text CHECK (tombstone_reason IN ('retention', 'deleted')),
  tombstoned_at    timestamptz,
  tombstoned_by    uuid REFERENCES app_user(id) ON DELETE SET NULL,
  purge_after      timestamptz,
  purged_at        timestamptz,
  UNIQUE (vault_id, seq),
  CONSTRAINT backup_version_tombstone_whole CHECK (
    (state = 'tombstone') = (tombstoned_at IS NOT NULL AND tombstone_reason IS NOT NULL AND purge_after IS NOT NULL)),
  CONSTRAINT backup_version_purged_is_tombstone CHECK (purged_at IS NULL OR state = 'tombstone')
);
CREATE INDEX backup_version_vault_idx ON backup_version (vault_id, seq DESC);

-- -------------------------------------------------------------- restore -----
CREATE TABLE backup_restore_challenge (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  vault_id    uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  device_id   uuid NOT NULL REFERENCES paired_device(id) ON DELETE CASCADE,
  nonce       bytea NOT NULL CHECK (octet_length(nonce) = 32),
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  CONSTRAINT backup_challenge_expiry CHECK (expires_at > created_at)
);
CREATE INDEX backup_restore_challenge_vault_idx ON backup_restore_challenge (vault_id, created_at);

CREATE TABLE backup_restore_request (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  vault_id          uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  requested_by      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  device_id         uuid NOT NULL REFERENCES paired_device(id) ON DELETE CASCADE,
  created_at        timestamptz NOT NULL DEFAULT now(),
  -- the waiting period. Chosen when the request is made and never shortened:
  -- 48 hours when another parent or the helper can say yes, 72 hours when
  -- nobody can; never below the 24-hour floor.
  wait_hours        integer NOT NULL CHECK (wait_hours >= 24),
  not_before        timestamptz NOT NULL,
  approval_required boolean NOT NULL,
  approved_by       uuid REFERENCES app_user(id) ON DELETE SET NULL,
  approved_at       timestamptz,
  approver_kind     text CHECK (approver_kind IN ('member', 'helper')),
  -- the request itself lapses if nobody finishes it
  expires_at        timestamptz NOT NULL,
  state             text NOT NULL DEFAULT 'pending'
                    CHECK (state IN ('pending', 'cancelled', 'completed', 'expired')),
  cancelled_by      uuid REFERENCES app_user(id) ON DELETE SET NULL,
  cancelled_at      timestamptz,
  completed_at      timestamptz,
  -- one-time download token (only its SHA-256 is stored)
  token_hash        text CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  token_issued_at   timestamptz,
  token_expires_at  timestamptz,
  token_issue_count integer NOT NULL DEFAULT 0 CHECK (token_issue_count >= 0),
  token_failures    integer NOT NULL DEFAULT 0 CHECK (token_failures >= 0),
  CONSTRAINT backup_restore_expiry CHECK (expires_at > not_before AND not_before >= created_at),
  CONSTRAINT backup_restore_approval_whole CHECK ((approved_at IS NULL) = (approver_kind IS NULL)),
  CONSTRAINT backup_restore_cancel_whole CHECK ((state = 'cancelled') = (cancelled_at IS NOT NULL))
);
-- at most ONE open restore per vault (a second request must wait or be cancelled)
CREATE UNIQUE INDEX backup_restore_one_open_idx ON backup_restore_request (vault_id) WHERE state = 'pending';
CREATE INDEX backup_restore_vault_idx ON backup_restore_request (vault_id, created_at DESC);

-- --------------------------------------------------------------- notices -----
CREATE TABLE backup_vault_event (
  seq        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vault_id   uuid NOT NULL REFERENCES backup_vault(id) ON DELETE CASCADE,
  -- 'restore' events are also shown to the helper; 'vault' events to grown-ups only
  scope      text NOT NULL CHECK (scope IN ('vault', 'restore')),
  kind       text NOT NULL CHECK (kind IN (
               'vault_created', 'member_joined', 'member_paused', 'member_resumed',
               'helper_named', 'helper_removed', 'version_deleted', 'version_restored',
               'restore_requested', 'restore_approved', 'restore_cancelled',
               'restore_token_issued', 'restore_completed', 'restore_expired')),
  actor_user uuid REFERENCES app_user(id) ON DELETE SET NULL,
  restore_id uuid,
  -- chosen by the server from a fixed per-kind template; never from request input
  summary    text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 160),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX backup_vault_event_vault_idx ON backup_vault_event (vault_id, seq DESC);

-- ----------------------------------------------------------- RLS helpers -----
-- "an active grown-up member of this vault right now". The member table's own
-- policy shows a session only ITS OWN rows, so these subqueries cannot recurse.
CREATE OR REPLACE FUNCTION backup_is_active_member(p_vault uuid) RETURNS boolean AS $$
  SELECT current_role_name() = 'guardian'
     AND current_actor() IS NOT NULL
     AND EXISTS (SELECT 1 FROM backup_vault_member m
                  WHERE m.vault_id = p_vault AND m.user_id = current_actor() AND m.state = 'active');
$$ LANGUAGE sql STABLE;

-- a member of any standing (a PAUSED parent keeps the right to see notices and to cancel)
CREATE OR REPLACE FUNCTION backup_is_any_member(p_vault uuid) RETURNS boolean AS $$
  SELECT current_role_name() = 'guardian'
     AND current_actor() IS NOT NULL
     AND EXISTS (SELECT 1 FROM backup_vault_member m
                  WHERE m.vault_id = p_vault AND m.user_id = current_actor());
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION backup_is_helper(p_vault uuid) RETURNS boolean AS $$
  SELECT current_role_name() = 'guardian'
     AND current_actor() IS NOT NULL
     AND EXISTS (SELECT 1 FROM backup_vault_helper h
                  WHERE h.vault_id = p_vault AND h.user_id = current_actor() AND h.removed_at IS NULL);
$$ LANGUAGE sql STABLE;

-- ----------------------------------------------------------------- RLS -------
ALTER TABLE backup_vault            ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_vault            FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_vault_member     ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_vault_member     FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_vault_helper     ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_vault_helper     FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_upload           ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_upload           FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_chunk            ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_chunk            FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_version          ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_version          FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_restore_challenge ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_restore_challenge FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_restore_request  ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_restore_request  FORCE  ROW LEVEL SECURITY;
ALTER TABLE backup_vault_event      ENABLE ROW LEVEL SECURITY;
ALTER TABLE backup_vault_event      FORCE  ROW LEVEL SECURITY;

-- vault: a member (any standing) reads it; only `system` writes it
CREATE POLICY backup_vault_member_read ON backup_vault FOR SELECT
  USING (current_role_name() = 'system' OR backup_is_any_member(id));
CREATE POLICY backup_vault_system_write ON backup_vault FOR ALL
  USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');

-- member: a session sees its OWN rows only (no recursion); only `system` writes
CREATE POLICY backup_member_own_read ON backup_vault_member FOR SELECT
  USING (current_role_name() = 'system'
         OR (current_role_name() = 'guardian' AND user_id = current_actor()));
CREATE POLICY backup_member_system_write ON backup_vault_member FOR ALL
  USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');

-- helper: the helper sees its own row; only `system` writes
CREATE POLICY backup_helper_own_read ON backup_vault_helper FOR SELECT
  USING (current_role_name() = 'system'
         OR (current_role_name() = 'guardian' AND user_id = current_actor()));
CREATE POLICY backup_helper_system_write ON backup_vault_helper FOR ALL
  USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');

-- upload: an ACTIVE member reads, starts and updates uploads of THEIR vault
CREATE POLICY backup_upload_member_rw ON backup_upload FOR ALL
  USING (current_role_name() = 'system' OR backup_is_active_member(vault_id))
  WITH CHECK (current_role_name() = 'system'
              OR (backup_is_active_member(vault_id) AND user_id = current_actor()));

-- chunk: an active member reads and adds; nobody but `system` deletes (and the
-- trigger below still refuses unless the bytes are expendable)
CREATE POLICY backup_chunk_member_read ON backup_chunk FOR SELECT
  USING (current_role_name() = 'system' OR backup_is_active_member(vault_id));
CREATE POLICY backup_chunk_member_insert ON backup_chunk FOR INSERT
  WITH CHECK (current_role_name() = 'system' OR backup_is_active_member(vault_id));
CREATE POLICY backup_chunk_system_delete ON backup_chunk FOR DELETE
  USING (current_role_name() = 'system');

-- version: an active member reads, adds (as themselves) and tombstones; never deletes
CREATE POLICY backup_version_member_read ON backup_version FOR SELECT
  USING (current_role_name() = 'system' OR backup_is_active_member(vault_id));
CREATE POLICY backup_version_member_insert ON backup_version FOR INSERT
  WITH CHECK (current_role_name() = 'system'
              OR (backup_is_active_member(vault_id) AND uploaded_by = current_actor()));
CREATE POLICY backup_version_member_update ON backup_version FOR UPDATE
  USING (current_role_name() = 'system' OR backup_is_active_member(vault_id))
  WITH CHECK (current_role_name() = 'system' OR backup_is_active_member(vault_id));

-- restore: challenge is system-only; the request is READABLE by any member
-- (a paused parent still sees a restore and may cancel it) and by the helper,
-- and written only by `system` behind the route's checks
CREATE POLICY backup_challenge_system ON backup_restore_challenge FOR ALL
  USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');
CREATE POLICY backup_restore_read ON backup_restore_request FOR SELECT
  USING (current_role_name() = 'system' OR backup_is_any_member(vault_id) OR backup_is_helper(vault_id));
CREATE POLICY backup_restore_system_write ON backup_restore_request FOR ALL
  USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');

-- notices: a member (any standing) reads all; the helper reads restore notices;
-- an active member may add a notice as themselves; `system` writes any
CREATE POLICY backup_event_read ON backup_vault_event FOR SELECT
  USING (current_role_name() = 'system'
         OR backup_is_any_member(vault_id)
         OR (scope = 'restore' AND backup_is_helper(vault_id)));
CREATE POLICY backup_event_insert ON backup_vault_event FOR INSERT
  WITH CHECK (current_role_name() = 'system'
              OR (backup_is_active_member(vault_id) AND actor_user = current_actor()));

-- ------------------------------------------------------------- integrity -----
-- A committed version is evidence of what the phone sealed. Its identity, size,
-- hashes, chain link, manifest and signature never change; only the tombstone
-- columns move, and a purged version is final.
CREATE OR REPLACE FUNCTION backup_version_guard() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'backup_version rows are never deleted (tombstone them instead)';
  END IF;
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.vault_id IS DISTINCT FROM OLD.vault_id
     OR NEW.seq IS DISTINCT FROM OLD.seq OR NEW.upload_id IS DISTINCT FROM OLD.upload_id
     OR NEW.prev_chain_hash IS DISTINCT FROM OLD.prev_chain_hash
     OR NEW.chain_hash IS DISTINCT FROM OLD.chain_hash
     OR NEW.blob_sha256 IS DISTINCT FROM OLD.blob_sha256
     OR NEW.size_bytes IS DISTINCT FROM OLD.size_bytes
     OR NEW.chunk_size IS DISTINCT FROM OLD.chunk_size
     OR NEW.chunk_count IS DISTINCT FROM OLD.chunk_count
     OR NEW.manifest IS DISTINCT FROM OLD.manifest
     OR NEW.signature IS DISTINCT FROM OLD.signature
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'a committed backup version is immutable (only its tombstone state may change)';
  END IF;
  IF OLD.purged_at IS NOT NULL THEN
    RAISE EXCEPTION 'a purged backup version is final';
  END IF;
  IF NEW.purged_at IS NOT NULL AND (OLD.state <> 'tombstone' OR OLD.purge_after > now()) THEN
    RAISE EXCEPTION 'a backup version can only be purged after its recovery window';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER backup_version_guard_upd BEFORE UPDATE ON backup_version
  FOR EACH ROW EXECUTE FUNCTION backup_version_guard();
CREATE TRIGGER backup_version_guard_del BEFORE DELETE ON backup_version
  FOR EACH ROW EXECUTE FUNCTION backup_version_guard();

-- Chunks are write-once, and only into an upload that is still open.
CREATE OR REPLACE FUNCTION backup_chunk_guard() RETURNS trigger AS $$
DECLARE u_state text; v_purged timestamptz; v_found boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT state INTO u_state FROM backup_upload WHERE id = NEW.upload_id;
    IF u_state IS DISTINCT FROM 'open' THEN
      RAISE EXCEPTION 'chunks can only be added to an open upload';
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'a stored backup chunk is immutable';
  ELSE -- DELETE
    SELECT state INTO u_state FROM backup_upload WHERE id = OLD.upload_id;
    IF u_state IN ('aborted', 'expired') THEN RETURN OLD; END IF;
    SELECT true, v.purged_at INTO v_found, v_purged FROM backup_version v WHERE v.upload_id = OLD.upload_id;
    IF v_found AND v_purged IS NOT NULL THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'backup bytes cannot be deleted before their recovery window has passed';
  END IF;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER backup_chunk_guard_ins BEFORE INSERT ON backup_chunk
  FOR EACH ROW EXECUTE FUNCTION backup_chunk_guard();
CREATE TRIGGER backup_chunk_guard_upd BEFORE UPDATE ON backup_chunk
  FOR EACH ROW EXECUTE FUNCTION backup_chunk_guard();
CREATE TRIGGER backup_chunk_guard_del BEFORE DELETE ON backup_chunk
  FOR EACH ROW EXECUTE FUNCTION backup_chunk_guard();

-- An upload's declared shape (size, hashes, chain link, signature) is fixed at
-- begin(); only its state moves, and only forward. A committed upload is final.
CREATE OR REPLACE FUNCTION backup_upload_guard() RETURNS trigger AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.vault_id IS DISTINCT FROM OLD.vault_id
     OR NEW.seq IS DISTINCT FROM OLD.seq OR NEW.base_seq IS DISTINCT FROM OLD.base_seq
     OR NEW.size_bytes IS DISTINCT FROM OLD.size_bytes
     OR NEW.chunk_size IS DISTINCT FROM OLD.chunk_size
     OR NEW.chunk_count IS DISTINCT FROM OLD.chunk_count
     OR NEW.blob_sha256 IS DISTINCT FROM OLD.blob_sha256
     OR NEW.prev_chain_hash IS DISTINCT FROM OLD.prev_chain_hash
     OR NEW.chain_hash IS DISTINCT FROM OLD.chain_hash
     OR NEW.manifest IS DISTINCT FROM OLD.manifest
     OR NEW.signature IS DISTINCT FROM OLD.signature
     OR NEW.client_ref IS DISTINCT FROM OLD.client_ref
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'an upload''s declared shape is fixed once it begins';
  END IF;
  IF OLD.state <> 'open' AND NEW.state IS DISTINCT FROM OLD.state THEN
    RAISE EXCEPTION 'a finished upload cannot change state';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER backup_upload_guard_upd BEFORE UPDATE ON backup_upload
  FOR EACH ROW EXECUTE FUNCTION backup_upload_guard();

-- The notice feed is append-only for everyone. The ONE allowed change is the
-- database's own "forget who did it" when a grown-up's account is erased
-- (actor_user ON DELETE SET NULL): that updates nothing but the actor, to NULL.
-- A row only goes when the whole vault is gone (never while it holds versions).
CREATE OR REPLACE FUNCTION backup_event_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.actor_user IS NULL AND NEW.seq = OLD.seq AND NEW.vault_id = OLD.vault_id
       AND NEW.scope = OLD.scope AND NEW.kind = OLD.kind AND NEW.summary = OLD.summary
       AND NEW.created_at = OLD.created_at AND NEW.restore_id IS NOT DISTINCT FROM OLD.restore_id THEN
      RETURN NEW;
    END IF;
  ELSIF NOT EXISTS (SELECT 1 FROM backup_vault WHERE id = OLD.vault_id) THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'the backup notice feed is append-only';
END $$ LANGUAGE plpgsql;
CREATE TRIGGER backup_event_no_change BEFORE UPDATE OR DELETE ON backup_vault_event
  FOR EACH ROW EXECUTE FUNCTION backup_event_append_only();

COMMENT ON TABLE backup_vault IS
  'One per family (0054). Holds only the PUBLIC half of the recovery key, the quota and the retention policy. No secret, no name, no content.';
COMMENT ON TABLE backup_chunk IS
  'Opaque ciphertext pieces (0054). The server never holds a key that opens them.';
COMMENT ON TABLE backup_version IS
  'A committed, hash-chained, phone-signed backup (0054). Never deleted: tombstoned, bytes kept for a recovery window.';

COMMIT;
