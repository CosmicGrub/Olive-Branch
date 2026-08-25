-- ============================================================================
--  OLIVE BRANCH — real row-level security for media_artifact, intent_batch,
--  delivery_intent.
--
--  Closes the exact gap `packages/db/src/pool.ts`'s `persistCapturedMessage()`
--  doc comment has named since before this pass, verbatim: "media_artifact,
--  intent_batch, and delivery_intent carry NO row-level security at all...
--  Closing that safely means auditing every existing reader of these tables
--  ... against a new policy — its own migration and its own review, not a
--  side effect of adding one new write path." `0021_child_message_sender.sql`
--  independently disclosed the same gap and deliberately declined to close it
--  there for the identical reason. This is that dedicated migration and
--  review.
--
--  THE AUDIT (done before writing a single line of SQL here, not assumed):
--  a full sweep of every SQL statement in this repo touching these three
--  tables — every route, every scheduler job, every migration function/
--  trigger/view, every test fixture — categorized by which Postgres role/
--  session context each one actually runs under. Two facts from that sweep
--  drive every decision below:
--
--    1. Every real WRITE to all three tables runs under `withSystemSession`
--       (role 'system') — `persistCapturedMessage()`'s INSERT into
--       media_artifact/delivery_intent[/intent_batch, when opts.newBatch is
--       eventually wired up], `deactivateAccount()`'s cancellation DELETE,
--       `tools/scheduler.mjs`'s rematerialize UPDATEs and reap-media DELETE.
--       No route ever opens a caller-scoped session and writes to any of
--       these three tables directly.
--
--    2. Real caller-scoped (non-system) READS exist for exactly two of the
--       three tables, both through routes already gated by app.role/
--       app.child_id being set to the real caller's own identity:
--         - GET /v1/children/:childId/inbox (delivery_intent) — reachable by
--           the CHILD reading her own inbox, or any adult holding the
--           'message' capability (packages/family-graph/src/authorize.ts's
--           ROLE_CAPS: guardian, step_parent, trusted_adult, foster_parent —
--           sitter/coordinator/caseworker/therapist are NOT granted
--           'message' and never reach this query).
--         - GET /v1/children/:childId/export, kind=raw (delivery_intent +
--           media_artifact, via assembleRawExportBundle()) — a live guardian
--           only (can('export.raw', ...) grants no other role).
--       intent_batch has no real caller-scoped reader today (its own INSERT
--       path is dead code in the shipped server — see persistCapturedMessage
--       call site — and the batch_progress view that would read it back is
--       queried by nothing) but gets the identical policy shape below rather
--       than a weaker one, so the gap is not silently reintroduced the day
--       message-banking is finally wired to a route.
--
--  THE DESIGN CHOICE, and why it is NOT this schema's older, coarser
--  "current_role_name() IS DISTINCT FROM 'child'" pattern
--  (expense_no_child/custody_order_not_child_scope, 0006/0007): that shape
--  places NO restriction on which child's rows a guardian session can see —
--  the only thing stopping Guardian A from reading Guardian B's child's
--  messages/media would be whatever WHERE child_id = $1 the application SQL
--  happens to bind. mediaArtifactFor()'s own comment already names exactly
--  this risk for a narrower case ("a query that only filtered on id would
--  let any caller ... read a different child's artifact merely by guessing
--  its uuid"). This schema already has a stricter, precedented answer for
--  message-shaped/media-shaped tables — 0017_child_theme_preference.sql's
--  child_theme_guardian_edge and 0018_call_log.sql's call_log_guardian_read,
--  both `current_role_name() = 'guardian' AND actor_has_edge(child_id)` —
--  and 0018's own comment states the point directly: actor_has_edge() is
--  "the thing actually enforcing 'a guardian with a live edge can write',
--  not just a comment claiming it." The policies below use that same
--  actor_has_edge() backstop, generalized from the single 'guardian' role
--  0017/0018 hardcode (correct for THOSE two tables, which really are
--  guardian-only by product design — 0018's own header asks "who beyond a
--  guardian and court export should ever see it") to the FULL role set that
--  actually holds the 'message' capability for THESE two tables (guardian,
--  step_parent, trusted_adult, foster_parent) — copying 0017/0018's
--  guardian-only condition verbatim here would silently zero out every
--  step_parent/trusted_adult/foster_parent's real, working inbox read, a
--  functionality regression as real as the security gap this migration
--  closes. actor_has_edge() itself is role-agnostic (queries
--  effective_guardianship with no role filter of its own) — it already
--  excludes restricted=true and ladder_step='none' edges regardless of which
--  of the four roles holds them, and deliberately does not traverse
--  sibling_link (its own 0003 comment: "being guardian of one sibling must
--  never confer access to another").
--
--  What this migration deliberately does NOT attempt: replicating can()'s
--  full nuance (observerOnly downgrades, per-action scope flags) inside SQL.
--  RLS here is the same coarser "second lock" 0017/0018 already establish —
--  a real, independent database guarantee that a session can only ever see
--  rows for a child it holds SOME live, non-restricted edge to — not a
--  restatement of the finer-grained authorization api.ts's own can() already
--  performs before any query runs. Matches 0017's own stated posture
--  verbatim ("the finer-grained scope distinction enforced one layer up, at
--  the route").
-- ============================================================================
BEGIN;

ALTER TABLE media_artifact  ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_artifact  FORCE  ROW LEVEL SECURITY;
ALTER TABLE intent_batch    ENABLE ROW LEVEL SECURITY;
ALTER TABLE intent_batch    FORCE  ROW LEVEL SECURITY;
ALTER TABLE delivery_intent ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_intent FORCE  ROW LEVEL SECURITY;

-- ---------------------------------------------------------- media_artifact --
-- No child-own policy: the audit found zero call sites anywhere that open a
-- role='child' session directly against this table — mediaArtifactFor()'s
-- own child-facing read (GET .../messages/:artifactId/media) runs under
-- withSystemSession regardless of who the real HTTP caller is, same as every
-- other read/write here except the guardian's raw-export path. A child-own
-- carve-out would be real, unreachable dead weight, not defense-in-depth —
-- there is nothing for it to admit that the system policy below doesn't
-- already admit.
CREATE POLICY media_artifact_adult_edge ON media_artifact
  FOR ALL USING (
    current_role_name() IN ('guardian','step_parent','trusted_adult','foster_parent')
    AND current_actor() IS NOT NULL
    AND actor_has_edge(child_id)
  );

CREATE POLICY media_artifact_system_all ON media_artifact
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

-- ------------------------------------------------------------ intent_batch --
-- Same shape as media_artifact, proactively — not because a real caller
-- needs it today (none does; see header) but so the exact gap this
-- migration closes is not quietly reintroduced the day message-banking's
-- own INSERT path (persistCapturedMessage()'s opts.newBatch branch) finally
-- gets a real route to call it from.
CREATE POLICY intent_batch_adult_edge ON intent_batch
  FOR ALL USING (
    current_role_name() IN ('guardian','step_parent','trusted_adult','foster_parent')
    AND current_actor() IS NOT NULL
    AND actor_has_edge(child_id)
  );

CREATE POLICY intent_batch_system_all ON intent_batch
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

-- --------------------------------------------------------- delivery_intent --
-- The one table of the three that DOES need a child-own policy: a real
-- child-role session reads her own delivery_intent rows directly through
-- GET /v1/children/:childId/inbox (server/routes.mjs), which opens the
-- route's own outer, caller-scoped session (no skipOuterSession) rather than
-- routing through system — the same shape journal_owner_only/custody_order_
-- child_own already use elsewhere in this schema. api.ts's own A3 check
-- (principal.childId === childId, enforced before the handler runs) means a
-- real child session's current_child() always equals the row's child_id for
-- her own inbox — this policy makes that guarantee a database one too, not
-- only an application one.
CREATE POLICY delivery_intent_child_own ON delivery_intent
  FOR ALL USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

CREATE POLICY delivery_intent_adult_edge ON delivery_intent
  FOR ALL USING (
    current_role_name() IN ('guardian','step_parent','trusted_adult','foster_parent')
    AND current_actor() IS NOT NULL
    AND actor_has_edge(child_id)
  );

CREATE POLICY delivery_intent_system_all ON delivery_intent
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

-- Every raw, no-session pg.Client connection in this codebase (seed-dev.mjs,
-- health-alert.mjs, healthcheck.mjs — all connect as app_owner, the table
-- owner, with app.role/app.child_id/app.user_id never set) is admitted by
-- NONE of the three policies above (current_role_name() returns NULL when
-- the GUC was never set, and NULL never equals 'system'/'child'/any role
-- name in an IN-list) — this is DELIBERATE, not a functionality gap: FORCE
-- ROW LEVEL SECURITY on a table with no matching policy denies the table
-- owner too, exactly the guarantee 0022_backup_reader_role.sql's own header
-- documents FORCE existing for. tools/health-alert.mjs's own aggregate
-- reads (via the health_check view, which is itself unforced/definer-free
-- and reads these tables as whatever role connects to it) are the one real
-- exception worth naming: they already ran successfully with zero RLS on
-- these tables before this migration, and health_check's own view
-- definition executes with the SAME role as whatever connects to run the
-- query — so an operator's health-alert/healthcheck invocation must connect
-- as app_owner or a role holding BYPASSRLS (postgres superuser in
-- tools/verify.sh, or backup_reader, both already BYPASSRLS) for those
-- aggregate counts to keep working. This matches the pattern every other
-- FORCE-RLS table this schema already ships already imposes on the same two
-- scripts — not a new constraint this migration introduces.
--
-- Raw Postgres SUPERUSER connections (tools/verify.sh's own psql -U postgres
-- fixture/constraint suites, ADMIN_DATABASE_URL in every packages/db/test/
-- *.test.mjs file) bypass RLS unconditionally regardless of FORCE or policy
-- match — unaffected by this migration, same as for the 14 tables that
-- already carry FORCE ROW LEVEL SECURITY.
--
-- backup_reader (0022_backup_reader_role.sql) already holds BYPASSRLS and
-- was already granted SELECT on ALL TABLES IN SCHEMA public (a one-time,
-- schema-wide grant, not scoped to a fixed table list) — these three tables
-- already existed when that grant ran, so tools/backup-db.sh needs no
-- change here.

-- ------------------------------------------------- health_check extension --
-- Same discipline every prior migration restates: the rls_unforced list is
-- CARRIED FORWARD IN FULL (from 0018_call_log.sql, the current live
-- definition), not appended to, since CREATE OR REPLACE VIEW replaces the
-- whole definition. Three names added: media_artifact, intent_batch,
-- delivery_intent — the exact three this migration gives FORCE ROW LEVEL
-- SECURITY to. Landing the ALTER TABLE statements above without this would
-- leave the schema's own self-check monitor reporting the OLD 14-table list
-- as the complete RLS-forced set even after these three join it — stale,
-- not wrong, but the same class of drift this document exists to prevent.
CREATE OR REPLACE VIEW health_check AS
SELECT * FROM (
  SELECT 'retention_breach'::text AS check_name, 'critical'::text AS severity,
         count(*)::bigint AS observed, 0::bigint AS threshold,
         'Media past its retention window still exists in storage.'::text AS meaning
    FROM retention_breach
  UNION ALL
  SELECT 'orphan_risk','high',count(*),0,
         'A queued message points at media that expires before delivery.' FROM orphan_risk
  UNION ALL
  SELECT 'stalled_delivery','high',count(*),0,'The sweep is not running.'
    FROM delivery_intent WHERE state='ready' AND scheduled_at < now() - interval '1 hour'
  UNION ALL
  SELECT 'unmaterialized','high',count(*),0,'Rematerialization is not running.'
    FROM delivery_intent WHERE state='pending' AND scheduled_at IS NULL
      AND created_at < now() - interval '1 hour'
  UNION ALL
  SELECT 'retention_invariant_broken','critical',count(*),0,
         'Artifacts with no clock and no preservation. The §5.6 CHECK is gone.'
    FROM media_artifact WHERE preserved=false AND expires_at IS NULL
  UNION ALL
  SELECT 'closure_without_reason','high',count(*),0,
         'Guardianship edges closed with no recorded reason.'
    FROM guardianship WHERE closed_at IS NOT NULL AND closed_reason IS NULL
  UNION ALL
  SELECT 'rls_unforced','critical',count(*),0,
         'Tables that must enforce RLS but do not FORCE it.'
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public'
     -- Carried forward from 0018, plus media_artifact/intent_batch/
     -- delivery_intent (this migration).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference',
                        'call_log','media_artifact','intent_batch','delivery_intent')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
