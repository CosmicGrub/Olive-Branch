-- ============================================================================
--  OLIVE BRANCH — 0058: a call can be started by the child.
--
--  Until now only a grown-up could start a call, so call_log.started_by was
--  an app_user id and NOT NULL. A child has no app_user row (her identity is
--  her child id), so "she calls an approved grown-up" had nowhere to be
--  recorded. This adds started_by_child and relaxes started_by to nullable,
--  with a CHECK that exactly one of the two says who started the call:
--    - a grown-up started it  -> started_by = that app_user, started_by_child = false
--    - the child started it   -> started_by IS NULL, started_by_child = true
--  participant_ids is unchanged (the child id plus the grown-up who may join).
--
--  Existing rows keep started_by and get started_by_child = false by the
--  column default, so the CHECK holds for every old row without a backfill
--  (an UPDATE under FORCE ROW LEVEL SECURITY could silently match nothing).
--  Still metadata only: no content, no location, never shown to the child.
-- ============================================================================
BEGIN;

ALTER TABLE call_log ALTER COLUMN started_by DROP NOT NULL;
ALTER TABLE call_log ADD COLUMN started_by_child boolean NOT NULL DEFAULT false;
ALTER TABLE call_log ADD CONSTRAINT call_log_initiator_check
  CHECK ((started_by IS NOT NULL) <> started_by_child);

-- the pending-call poll scans only live, unanswered calls of one child
CREATE INDEX call_log_pending_idx ON call_log (child_id, started_at)
  WHERE ended_at IS NULL AND answered_at IS NULL;

COMMIT;
