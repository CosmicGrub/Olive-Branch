-- ============================================================================
--  OLIVE BRANCH — call_log
--  MASTERFILE §5.19, §5.21, §14. Closes a real, confirmed gap: session-
--  runtime/src/security.ts's own RESIDUAL_RISKS table already claims call
--  metadata ("who called whom, when, for how long") is "Retained, because
--  §14 court export needs it" — but a full audit of every migration through
--  0017 found no call/call_log/call_history/call_session table anywhere.
--  message_log (0006) is text-message bodies only, with no duration/
--  participant/start-end columns. This is the first real backing for that
--  compliance claim.
--
--  Metadata only, by design — never content, never location (P3). The row
--  is keyed by the real session id server/routes.mjs's POST .../calls
--  already mints (session-runtime/src/rooms.ts's createSession(), a 32-char
--  hex string, not a uuid — stored verbatim as this table's own primary key
--  rather than generating a second, redundant identifier) so the call-start
--  route's INSERT and the call-end route's later UPDATE (see server/
--  routes.mjs) both address the exact same row.
--
--  Deliberately NOT append-only / hash-chained like message_log — a call's
--  real duration is only known once it ends, so this row is written once at
--  start and updated once at end. message_log's own immutability model
--  (P8, hash-chained, never updated) does not fit a duration-bearing record
--  and is not attempted here.
--
--  participant_ids is a uuid[] rather than a single started_by/answered_by
--  pair — the underlying session model (SessionRecord.authorizedUserIds,
--  already a list) is not inherently 1:1, and a future second-guardian-join
--  route (already scoped, not built here) should be able to append to this
--  same column without a further migration.
--
--  Viewer/retention-duration questions are explicitly NOT decided here —
--  MASTERFILE's own §16.2 #11 ("whether a therapist sees it") stays open;
--  this migration only makes the already-claimed retention real.
-- ============================================================================

BEGIN;

CREATE TABLE call_log (
  -- session-runtime's own createSession() id (randomBytes(16).toString(
  -- 'hex')) — not a uuid, stored as the real identifier both the call-start
  -- and call-end routes already share, rather than minting a second one.
  id               text PRIMARY KEY,
  child_id         uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  started_by       uuid NOT NULL REFERENCES app_user(id),
  -- Every guardian who was ever a party to this call (createdBy plus any
  -- future second-guardian join) — see this migration's own header on why
  -- this is a list, not a single column.
  participant_ids  uuid[] NOT NULL,
  room_name        text NOT NULL,
  -- Mirrors contact_ladder's own step CHECK values verbatim (0001) — this
  -- is the real per-edge ladder step the call was authorized under, not a
  -- separately-invented vocabulary.
  ladder_step      text NOT NULL CHECK (ladder_step IN
                     ('none','supervised','monitored','time_limited','open')),
  recorded         boolean NOT NULL DEFAULT false,
  -- Whether the callee's device(s) were successfully pushed a real
  -- call_incoming notification — packages/transport/src/notify.ts's own
  -- notifyDevices() result, not whether the call was actually answered
  -- (this table has no "answered" column yet; a real end-to-end answered/
  -- missed distinction needs the call-end route to know who joined, which
  -- the current self-hosted Jitsi stack has no server-side visibility
  -- into — a real, disclosed limitation, not invented around here).
  rang             boolean NOT NULL DEFAULT false,
  started_at       timestamptz NOT NULL DEFAULT now(),
  ended_at         timestamptz
);

-- ---------------------------------------------------------------------------
-- RLS. Both bypass paths db/DEPLOYMENT.md warns about are closed the same
-- way every other real table in this schema closes them: ENABLE + FORCE, no
-- exceptions for the table owner.
ALTER TABLE call_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE call_log FORCE  ROW LEVEL SECURITY;

-- 1) A guardian with a LIVE edge to this child may read this child's call
--    history — actor_has_edge() (0003_session_context.sql), this schema's
--    own single definition of "does the current session's actor really,
--    currently, hold access to this child", reused rather than re-derived.
--    Guardian-READ only, deliberately: nothing about who called whom needs
--    a client-writable path — every real write below runs as `system`,
--    from the call-start/call-end routes only.
CREATE POLICY call_log_guardian_read ON call_log
  FOR SELECT USING (
    current_role_name() = 'guardian'
    AND current_actor() IS NOT NULL
    AND actor_has_edge(child_id)
  );

-- 2) System-role read AND write, for server/routes.mjs's call-start (INSERT)
--    and call-end (UPDATE ended_at) handlers — mirrors child_theme_
--    preference's own system-role reasoning (0017): the route's own real
--    can('call', ...) check (call-start) or the child-scoped session check
--    (call-end) already gated this write before it runs, so granting the
--    trusted backend role access here only lets that one already-authorized
--    call finish; it is not a client-reachable widening. No child-role
--    policy exists at all — the child never reads or writes this table
--    directly, matching MASTERFILE's own still-open §16.2 #11 question
--    about who beyond a guardian and court export should ever see it.
CREATE POLICY call_log_system_all ON call_log
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

-- ------------------------------------------------- health_check extension --
-- Same discipline every prior migration restates: the rls_unforced list is
-- CARRIED FORWARD IN FULL, not appended to, since CREATE OR REPLACE VIEW
-- replaces the whole definition.
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
     -- Carried forward from 0017, plus call_log (this migration).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference',
                        'call_log')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE call_log IS
  'Real, persisted call metadata — who called whom, when, for how long. '
  'Metadata only: never call content, never location (P3). Written by '
  'server/routes.mjs''s call-start (INSERT) and call-end (UPDATE ended_at) '
  'routes as `system`, after each route''s own real authorization check '
  'already ran. Guardian-read (live edge required) only; the child has no '
  'policy on this table at all. Backs session-runtime/src/security.ts''s '
  'own RESIDUAL_RISKS claim that this data is retained for §14 court '
  'export — that claim had no implementation anywhere before this table.';

COMMIT;
