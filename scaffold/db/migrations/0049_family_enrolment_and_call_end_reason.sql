-- ============================================================================
--  OLIVE BRANCH — 0049: a first real family can exist, and a call records how
--  it ended.
--
--  Two independent, additive changes, shipped together because both close a
--  gap in the "server enables the live app" chain:
--
--  1. family_enrolment_code. Until now the ONLY runtime INSERTs into app_user /
--     child / guardianship were the dev seed (server/seed-dev.mjs) and the
--     guardian-invite bootstrap (which needs an existing child). With
--     DEV_LOGIN refused under NODE_ENV=production there was no way for a
--     production server to acquire its first family at all. An OPERATOR (the
--     person who runs the server) mints a single-use enrolment code from the
--     command line (tools/enrol-family.mjs); a family redeems it once via
--     POST /v1/families and gets its guardian, child and guardianship edge in
--     ONE transaction, plus a paired-device credential so
--     /v1/auth/session/refresh works at once.
--
--     Only the SHA-256 of the code is stored (the code is 100 random bits, so a
--     fast hash is correct, the same reasoning as paired_device.credential_hash
--     in 0038). The table is system-only under FORCE RLS: no guardian or child
--     session can read, list or write it, and neither can the least-privilege
--     runtime role outside a system session.
--
--  2. call_log.answered_at / ended_reason. A call used to end only as
--     "ended_at is set"; a ring that was never answered, or a session whose
--     clients crashed, left no trace of WHY. answered_at is stamped by the
--     server when the CHILD (the callee) first mints a join token, which is the
--     one moment the server genuinely sees an answer. ended_reason is a closed
--     set derived from that: answered (it was joined, then ended), cancelled
--     (the caller hung up before it was answered), declined (the child's
--     device ended it unanswered), stale (the sweep ended an abandoned
--     session). NULL while the call is live and for rows written before this
--     migration.
-- ============================================================================
BEGIN;

CREATE TABLE family_enrolment_code (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  code_hash        text NOT NULL UNIQUE CHECK (code_hash ~ '^[0-9a-f]{64}$'),
  -- operator's own note ("Smith family"); never shown to anyone but the operator
  label            text NOT NULL DEFAULT '' CHECK (char_length(label) <= 80),
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  revoked_at       timestamptz,
  redeemed_at      timestamptz,
  redeemed_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
  CONSTRAINT enrolment_not_both_redeemed_and_revoked
    CHECK (NOT (redeemed_at IS NOT NULL AND revoked_at IS NOT NULL))
);

ALTER TABLE family_enrolment_code ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_enrolment_code FORCE  ROW LEVEL SECURITY;

CREATE POLICY family_enrolment_code_system_all ON family_enrolment_code
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

ALTER TABLE call_log ADD COLUMN answered_at timestamptz;
ALTER TABLE call_log
  ADD COLUMN ended_reason text
  CONSTRAINT call_log_ended_reason_check
    CHECK (ended_reason IS NULL
           OR ended_reason IN ('answered','cancelled','declined','stale'));

-- the stale sweep scans only live calls
CREATE INDEX call_log_live_idx ON call_log (started_at) WHERE ended_at IS NULL;

COMMIT;
