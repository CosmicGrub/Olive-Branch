-- ============================================================================
--  OLIVE BRANCH — the guardian invitation/consent flow
--  MASTERFILE §11, §8.5. Closes half of the gap client/lib/invitation_screen.dart's
--  own header names: "the API surface names POST /v1/children/:id/guardianships,
--  but no such route exists in server/routes.mjs" — this migration is that
--  route's table.
-- ============================================================================
--
--  SCOPE, STATED HONESTLY: this closes invite create/read/accept-decision/
--  revoke — a real, tested lifecycle. It does NOT close the loop end to end,
--  because closing it would mean fabricating an account-creation security
--  model this codebase has never specified: guardian_setup.dart's own header
--  says its passkey registration step is "null in every build today" because
--  it requires an ALREADY-AUTHENTICATED guardian session to call
--  /v1/auth/webauthn/register/challenge — and nowhere in this repository does
--  a brand-new guardian (the first, or one accepting THIS invite) ever
--  acquire that first session. That is a real, separate, foundational gap —
--  "how does a passwordless account get created at all" — not something this
--  migration invents an answer to. accepted_at below records a real decision;
--  it does not, and must not, imply a guardianship row now exists.

BEGIN;

CREATE TABLE guardian_invite (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  invited_by    uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- The invited person has no app_user row yet (see header) — email is the
  -- only identifier that survives to the still-unbuilt account-creation step.
  invited_email citext NOT NULL,
  role          text NOT NULL CHECK (role IN
                  ('guardian','trusted_adult','step_parent','sitter','coordinator')),
  -- Her own word for them (Dad, Nana, ...) — same posture as observer.ts's
  -- Observer.label; never a hard-coded relationship term.
  label         text NOT NULL,
  scope         jsonb NOT NULL DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- 14 days: long enough that "check your email" surviving a weekend still
  -- works, short enough that a stale, forgotten invite does not sit livable
  -- forever. Unlike OBSERVER_GRANT_TTL_DAYS (180, a standing grant renewed by
  -- re-inviting) this is a one-time decision window, not a recurring grant.
  expires_at    timestamptz NOT NULL DEFAULT (now() + interval '14 days'),
  accepted_at   timestamptz,
  revoked_at    timestamptz,
  CONSTRAINT invite_not_both_accepted_and_revoked
    CHECK (NOT (accepted_at IS NOT NULL AND revoked_at IS NOT NULL))
);

CREATE INDEX guardian_invite_child_idx ON guardian_invite (child_id);
CREATE INDEX guardian_invite_invited_by_idx ON guardian_invite (invited_by);

-- ------------------------------------------------------------------- RLS ---
-- The inviting guardian sees and creates their own invites. The INVITED
-- party has no app_user row and therefore no session RLS can key off at
-- all — reading/accepting a specific invite by its own unguessable id runs
-- as 'system' inside the route handler (identityScopedByHandler, same
-- posture as kiosk-pin/verify in server/routes.mjs), with the id itself —
-- long, random, single-purpose — standing in for the credential a session
-- would otherwise provide. Never exposed via a listing query.
ALTER TABLE guardian_invite ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_invite FORCE  ROW LEVEL SECURITY;

CREATE POLICY guardian_invite_owner_rw ON guardian_invite
  FOR ALL
  USING (current_role_name() = 'system' OR invited_by = current_actor())
  WITH CHECK (current_role_name() = 'system' OR invited_by = current_actor());

-- ------------------------------------------------- health_check extension --
-- Same discipline 0013 already restated for export_record: the rls_unforced
-- list is CARRIED FORWARD IN FULL, not appended to, since CREATE OR REPLACE
-- VIEW replaces the whole definition.
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
     -- Carried forward from 0013, plus guardian_invite (this migration).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE guardian_invite IS
  'A pending invitation for a new guardian/adult to join a child''s family '
  'graph. Deliberately separate from guardianship (0001) — no guardianship '
  'row is created here, or anywhere yet: that step needs an app_user row '
  'for the invited party, and this codebase has no account-creation route '
  'for one. See this migration''s own header.';

COMMIT;
