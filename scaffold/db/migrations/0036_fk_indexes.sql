-- ============================================================================
--  OLIVE BRANCH — fk_indexes (audit P-17)
--
--  Six foreign-key lookups that had no index to land on. Postgres does NOT create an
--  index for the referencing side of a foreign key, and each of these columns
--  is both (a) filtered on by real application queries and (b) the column
--  Postgres itself scans on every DELETE/UPDATE of the referenced row to
--  enforce ON DELETE CASCADE / the FK check -- so account deletion
--  (app_user) and child deletion (child) were sequential scans of every
--  table below, once per row removed.
--
--    guardianship.user_id        edgesFor() -- `WHERE g.user_id = $1` -- runs
--                                on EVERY authorized request (api.ts), and
--                                UNIQUE (child_id, user_id) only helps a
--                                child_id-first lookup, not this one.
--    call_log.child_id           per-child call history / deletion cascade
--    medication_dose.child_id    per-child dose log / deletion cascade (the
--                                existing index leads with medication_id)
--    media_artifact.author_id    author lookups / app_user FK check (nullable
--                                column; the existing indexes lead child_id /
--                                expires_at)
--    intent_batch.child_id       per-child batch listing / deletion cascade
--    export_record.child_id      per-child export history / deletion cascade
--                                (existing indexes lead requested_by)
--
--  Plus one for the purge this same pass adds (scheduler job
--  `purge-challenges`): auth_challenge had an index on (user_id, purpose,
--  consumed_at) for consumeChallenge()'s lookup but nothing on issued_at, so
--  deleting expired rows would have scanned the whole table.
--
--  Nothing but indexes: no table, column, constraint, grant, policy or RLS
--  setting is touched, so who may read or write any row is exactly what it was.
--  IF NOT EXISTS keeps it safe to re-run against a database a human already
--  patched by hand during an incident.
-- ============================================================================

BEGIN;

CREATE INDEX IF NOT EXISTS guardianship_user_id_idx       ON guardianship (user_id);
CREATE INDEX IF NOT EXISTS call_log_child_id_idx          ON call_log (child_id);
CREATE INDEX IF NOT EXISTS medication_dose_child_id_idx   ON medication_dose (child_id);
CREATE INDEX IF NOT EXISTS media_artifact_author_id_idx   ON media_artifact (author_id);
CREATE INDEX IF NOT EXISTS intent_batch_child_id_idx      ON intent_batch (child_id);
CREATE INDEX IF NOT EXISTS export_record_child_id_idx     ON export_record (child_id);
CREATE INDEX IF NOT EXISTS auth_challenge_issued_at_idx   ON auth_challenge (issued_at);

COMMIT;
