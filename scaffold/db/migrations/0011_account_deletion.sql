-- ============================================================================
--  OLIVE BRANCH — account deletion (deactivation, not row deletion)
--  MASTERFILE §2.10, §2.11, §9.8, prohibition P8.
--  client/lib/deletion_screen.dart's own constants are the spec this
--  migration (and packages/db/src/pool.ts's deactivateAccount()) exist to
--  make real:
--
--  whatDeletionKeeps (verbatim) — survives regardless of tier or lapse:
--    - messages/videos already delivered to the child
--    - the parent-to-parent handover log (message_log, 0006_court_tier.sql —
--      untouched here: still append-only/hash-chained, no new policy or
--      trigger on it, nothing in this migration can reach it)
--    - the child's preserved archive (media_artifact / child_journal_entry)
--
--  whatDeletionRemoves (verbatim):
--    - the deleting guardian's login/session
--    - anything queued or banked but not yet delivered
--    - their future participation
--
--  The app_user ROW ITSELF is never deleted: message_log.author_id
--  (ON DELETE RESTRICT) and a delivered delivery_intent.sender_id (no
--  action) both reference it, so deleting the row would either be refused
--  by Postgres or silently orphan a delivered message's own authorship.
--  deactivated_at is the entire schema change; the rest is application
--  logic (packages/db/src/pool.ts's deactivateAccount()) plus the RLS below.
-- ============================================================================

BEGIN;

ALTER TABLE app_user ADD COLUMN deactivated_at timestamptz;

-- ---------------------------------------------------------------------------
-- RLS on app_user, added here for the first time — no earlier migration put
-- any policy on this table, so today ANY connected role can read or write
-- ANY row. Unlike every other RLS table in this codebase
-- (child_journal_entry, pin_credential, expense, message_log, custody_order,
-- all of which use ONE `FOR ALL` policy), a single FOR ALL policy is the
-- wrong shape here: app_user rows are read broadly by design (GET /v1/me,
-- the inbox's sender_name join, dev-login's own lookup) and that must keep
-- working, unchanged, for every role. Only the new WRITE this migration
-- exists to support — a guardian deactivating THEIR OWN row — needs
-- restricting, so three narrow, command-scoped policies replace the usual
-- one FOR ALL:
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_user FORCE  ROW LEVEL SECURITY;

CREATE POLICY app_user_read_all ON app_user
  FOR SELECT USING (true);

-- Account creation (onboarding, tools/migrate.mjs's dev seed,
-- server/seed-dev.mjs) is unchanged and out of scope for this migration —
-- nothing here restricts who may be inserted or by which role.
CREATE POLICY app_user_insert_open ON app_user
  FOR INSERT WITH CHECK (true);

-- The actual point. packages/db/src/pool.ts's deactivateAccount() UPDATEs
-- exactly one column (deactivated_at) on exactly one row, and it must be
-- the CALLER'S OWN row. current_actor() reads app.user_id, set by
-- withSession() (packages/db/src/pool.ts) from the VERIFIED principal
-- (0003_session_context.sql), never from request input — so even a bug that
-- passed the wrong userId into deactivateAccount() cannot reach another
-- guardian's row; Postgres itself refuses the UPDATE. 'system' is also
-- admitted, matching every other current_role_name() check in this codebase
-- (migrations/tooling/dev seeds that run through the pool rather than as
-- the postgres superuser).
CREATE POLICY app_user_self_update ON app_user
  FOR UPDATE USING (
    current_role_name() = 'system' OR id = current_actor()
  );

-- No DELETE policy exists here, deliberately: this row must never be
-- deleted (see header). With RLS enabled and FORCE set, the absence of a
-- DELETE policy means "DELETE FROM app_user" is refused by Postgres itself
-- for every non-superuser role — not merely "nobody happens to call it".

COMMIT;
