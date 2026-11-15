-- ============================================================================
--  OLIVE BRANCH — 0052: a call records how it ended.
--
--  call_log.answered_at / ended_reason. A call used to end only as
--  "ended_at is set"; a ring that was never answered, or a session whose
--  clients crashed, left no trace of WHY. answered_at is stamped by the
--  server when the CHILD (the callee) first mints a join token, which is the
--  one moment the server genuinely sees an answer. ended_reason is a closed
--  set derived from that: answered (it was joined, then ended), cancelled
--  (the caller hung up before it was answered), declined (the child's
--  device ended it unanswered), stale (the sweep ended an abandoned
--  session). NULL while the call is live and for rows written before this
--  migration.
--
--  Both columns are nullable and are NOT backfilled: this file may run as the
--  table owner under FORCE ROW LEVEL SECURITY, where an UPDATE touching rows
--  would silently match none of them (the lesson of migration 0050's
--  backfill), and a reason cannot be reconstructed after the fact anyway.
--  Child safety: these are timestamps and a closed set of words about ONE
--  call, never a count, a streak or a score, and never shown to the child.
--
--  (The enrolment-code half of the push/calls lane's original migration was
--  dropped when the lanes were reconciled: invite-only sign-up is migration
--  0050's signup_allowance, so there is exactly one first-family mechanism.)
-- ============================================================================
BEGIN;

ALTER TABLE call_log ADD COLUMN answered_at timestamptz;
ALTER TABLE call_log
  ADD COLUMN ended_reason text
  CONSTRAINT call_log_ended_reason_check
    CHECK (ended_reason IS NULL
           OR ended_reason IN ('answered','cancelled','declined','stale'));

-- the stale sweep scans only live calls
CREATE INDEX call_log_live_idx ON call_log (started_at) WHERE ended_at IS NULL;

COMMIT;
