-- ============================================================================
--  OLIVE BRANCH — guardian_activity_override
--
--  MASTERFILE §21 (parental-controls arc), docs/superpowers/specs/2026-09-13-
--  parental-controls-pacing-design.md ("sub-project 2: visibility & pacing").
--  The third item in the onboarding/parental-controls arc, after sub-project 1
--  (guardian PIN, 0031/0032-adjacent work) and device pairing (0032) — both
--  already shipped.
--
--  Two real, disclosed gaps this closes, per the design spec's own Goal
--  section: (1) no guardian-writable table has EVER controlled what a child
--  can access — child_theme_preference (0017), the one existing guardian-
--  write/child-read table, is purely cosmetic; (2) newlyUnlocked()'s age-
--  threshold unlock exists only as a hardcoded, unadjustable `minAge` per
--  item, with no guardian-facing way to raise, lower, or pre-empt it.
--
--  ONE table, not two — visibility and pacing are both "a guardian's override
--  of one activity's default behavior for one child," so they share a row
--  shape (the design spec's own "Data model" section, verbatim).
--
--  `activity_key` is a plain namespaced string ('tile:storyteller',
--  'game:chess', 'joke:knock_knock', 'activity:colouring_page_3', ...), NOT a
--  foreign key into any catalogue — there is no unified catalogue table to
--  reference (games/jokes/activities each keep their own hardcoded TS/Dart
--  lists). This mirrors how guardian_game_favorite (0030) already stores a
--  bare `kind` string rather than inventing a cross-cutting catalogue table.
--  A key with no matching catalogue entry (a stale kind, a typo) is silently
--  inert, same discipline favouritesFor()'s own "stale kind" handling already
--  established — never an error, never fabricated content.
--
--  RLS mirrors child_theme_preference (0017) EXACTLY, not merely in spirit:
--  guardian FOR ALL via actor_has_edge() (0003_session_context.sql), child
--  SELECT-only via current_child(), ENABLE + FORCE on both, and — the
--  deliberate omission — NO child write policy at all (a child-session
--  INSERT/UPDATE matches no policy and is rejected outright, exactly 0017's
--  own "guardian-only by design" posture). Unlike 0017, this table has NO
--  system-role read policy: the design spec's own Routes section says
--  "No role branch needed in the handler — RLS alone decides what's visible
--  to which caller", which only holds if the GET route runs the query under
--  the REAL calling session's role/actor (guardian or child), not as
--  `system` — see packages/db/src/pool.ts's activityOverridesFor() for the
--  corresponding, deliberately-different-from-themeFor() session choice.
--
--  Two behavioral rules the design spec calls out explicitly (both enforced
--  at the client/route layer, not by a CHECK constraint here — see that
--  spec's own "Two behavioral rules" section for the full reasoning):
--    1. Never retroactive — hiding/pacing only ever affects what a child
--       hasn't yet seen; a presentation-layer, reload-time filter, not a
--       data-layer guarantee (the spec's own honestly-disclosed gap: it does
--       not stop a session she already has open).
--    2. Fully bidirectional, no ratchet — unlike the maturation ladder
--       (canGuardianRevoke(): false), every column here can move in either
--       direction, any number of times, by direct confirmation during
--       scoping.
-- ============================================================================

BEGIN;

CREATE TABLE guardian_activity_override (
  child_id         uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  activity_key     text NOT NULL,       -- e.g. 'tile:storyteller', 'game:chess', 'joke:knock_knock', 'activity:colouring_page_3'
  visible          boolean,             -- NULL = default (shown); explicit false = hidden. The only column tiles with no age concept (storyteller, homework, messages, ...) ever use.
  min_age_override integer,             -- NULL = use the catalogue's own default minAge. Only meaningful for game/joke/activity keys.
  revealed_at      timestamptz,         -- manual one-time reveal: once set, this item shows regardless of age from now on
  set_by           uuid NOT NULL REFERENCES app_user(id),
  set_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (child_id, activity_key)
);
CREATE INDEX guardian_activity_override_child_idx ON guardian_activity_override (child_id);

-- ---------------------------------------------------------------------------
-- RLS. Both bypass paths db/DEPLOYMENT.md warns about are closed the same
-- way every other real table in this schema closes them: ENABLE + FORCE, no
-- exceptions for the table owner.
ALTER TABLE guardian_activity_override ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_activity_override FORCE  ROW LEVEL SECURITY;

-- 1) A guardian with a LIVE edge to this child may read AND write this row —
--    FOR ALL, one USING (which existing rows are visible/writable) and one
--    WITH CHECK (what an INSERT/UPDATE is allowed to leave behind), both
--    keyed on actor_has_edge() — 0017's own child_theme_guardian_edge policy,
--    reused verbatim rather than re-deriving the same check a second way.
CREATE POLICY activity_override_guardian_edge ON guardian_activity_override
  FOR ALL USING (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND actor_has_edge(child_id)
  ) WITH CHECK (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND actor_has_edge(child_id)
  );

-- 2) The child herself reads her own row — same shape child_theme_
--    preference's own child-read policy (0017) already uses. She never gets
--    a WRITE policy: this is guardian-only by design (the design spec's own
--    §8.5.0-derived "every write here requires a live guardianship edge...
--    never a convenience-only gate" line), so the absence of a child WITH
--    CHECK here is deliberate, not an oversight — an INSERT/UPDATE attempted
--    under a 'child' role session simply matches no policy at all and is
--    rejected.
CREATE POLICY activity_override_child_read ON guardian_activity_override
  FOR SELECT USING (
    current_role_name() = 'child' AND current_child() IS NOT NULL AND child_id = current_child()
  );

-- ------------------------------------------------- health_check extension --
-- Same discipline every migration in this series restates: the
-- rls_unforced list is CARRIED FORWARD IN FULL (from 0032), plus
-- guardian_activity_override (this migration) —
-- packages/db/test/rls_coverage.test.mjs fails outright on a real Postgres
-- if it's missing.
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
     -- Carried forward from 0032, plus guardian_activity_override
     -- (this migration).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference',
                        'call_log','media_artifact','intent_batch','delivery_intent',
                        'medication','medical_record','medication_dose',
                        'exchange_bag_item',
                        'exchange_running_late_log','exchange_arrival_event',
                        'care_note','letter',
                        'guardian_game_favorite','child_game_picker_state',
                        'child_profile','device_pairing_code','paired_device',
                        'guardian_activity_override')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE guardian_activity_override IS
  'A guardian''s override of one activity''s default behavior for one child — '
  'visibility (hide/show a ChildHome tile, game, joke, or activity outright) '
  'and pacing (raise/lower the effective age gate, or manually reveal it now) '
  'share this one row shape. NULL columns mean "use the catalogue default"; '
  'visible=false always wins over any age/reveal state. Guardian-write (live '
  'edge required, actor_has_edge())/child-read (current_child()), RLS-'
  'enforced, RLS mirrors child_theme_preference (0017) exactly except for the '
  'deliberately absent system-role read policy — see this migration''s own '
  'header for why the GET route needs the real caller''s session, not '
  '`system`, to make RLS alone decide scope.';

COMMIT;
