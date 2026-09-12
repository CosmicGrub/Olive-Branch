-- ============================================================================
--  OLIVE BRANCH — child_profile
--
--  MASTERFILE §8.5, docs/superpowers/specs/2026-09-12-onboarding-identity-pin
--  -design.md ("Onboarding & Guardian Access — sub-project 1: identity
--  capture & required PIN setup"). Real backend for `onboarding_gender.dart`
--  (new), the FIRST route in the entire onboarding pipeline that any
--  first-run screen's tapped answer actually reaches — `onboarding_name.dart`
--  /`onboarding_age.dart`/`onboarding_who.dart` have been demo-replay only
--  (reached via `ChildMoreScreen`'s "Redo the welcome tour") since they were
--  built, and `onboarding_logic.dart`'s (Dart) / `onboarding.ts`'s (TS
--  engine) own `outcome()` has computed a real result object that no route in
--  `server/routes.mjs` has ever ingested, this whole time.
--
--  A NEW TABLE, not a new column on `child` — the IDENTICAL precedent
--  0017_child_theme_preference.sql and 0030_game_favorites.sql
--  (`child_game_picker_state`) already established, for the identical
--  reason both of those migrations' own headers already give: `child` has
--  NEVER had row-level security enabled at any point in this schema's
--  history, so a child-writable column bolted onto it here would be exactly
--  the kind of undeclared widening of an existing table's contract
--  MASTERFILE §0 warns against — every current reader of `child` would need
--  a fresh audit this migration is not scoped to do.
--
--  RLS mirrors `child_game_picker_state_owner_only` (0030) EXACTLY, not
--  `child_theme_preference`'s guardian-write/child-read split: this is a
--  CHILD-authored fact (her own tap, on her own screen, about herself), the
--  same "no guardian involvement needed to record it" shape
--  `child_game_picker_state`'s own header describes for the age-unlock
--  signal — a child session owns exactly her own row, and there is
--  DELIBERATELY no guardian policy on this table at all, matching this
--  migration's own design spec: "No guardian-facing read route in this
--  pass — nothing consumes this field yet, and a read surface for data
--  nothing uses would be scope creep this codebase's own YAGNI convention
--  already argues against elsewhere." Unlike `child_game_picker_state`, this
--  table also carries NO system-role read policy — nothing (not even a
--  trusted backend route) ever reads this column back in this pass, so
--  granting one would be an unused grant sitting on a real, regulated child-
--  data table, not a real access path anything actually takes. When a
--  future feature needs to read gender, that pass adds the policy it
--  actually needs, same as every other narrowly-scoped table in this
--  schema's history.
--
--  `gender` is nullable with a CHECK, not a NOT NULL enum with a "skipped"
--  member: NULL means "no row, or a row that was never really set" — this
--  migration's own writer (`setChildGender()`, packages/db/src/pool.ts)
--  never inserts a row for a Skip at all (client/lib/onboarding_gender.dart's
--  own contract: "a NULL gender after skip is never coerced into a
--  fabricated default" — the design spec's own line), so in practice a
--  skipped child has NO ROW here, not a row with a NULL gender. The CHECK
--  still guards the column against anything OTHER than the two real wire
--  values, honest-absence-vs-fabricated-default discipline this schema
--  already applies everywhere else (0017's own header is the clearest
--  statement of it). `set_at` is nullable for the same reason and is only
--  ever written alongside a real, non-null `gender`.
--
--  Regulatory note (not a mechanism built here, per the design spec's own
--  "Data model" section): MASTERFILE §10.1 treats this app's entire child-
--  data payload as regulated PI, and §10.2 requires a real dual-guardian
--  consent state machine for data-collection decisions generally — this
--  migration does not invent a bespoke consent flow specific to `gender`;
--  it is folded into whatever retention/consent handling already governs
--  `child`'s and its sibling per-child tables (`child_theme_preference`,
--  `child_game_picker_state`), unchanged by this migration.
-- ============================================================================

BEGIN;

CREATE TABLE child_profile (
  child_id  uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,
  gender    text CHECK (gender IN ('boy', 'girl')),  -- NULL = skipped, not "unknown"
  set_at    timestamptz
);

ALTER TABLE child_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_profile FORCE  ROW LEVEL SECURITY;

-- The child owns her own row outright — no guardian policy exists here at
-- all, deliberately: the IDENTICAL shape child_game_picker_state_owner_only
-- (0030) already uses, for the identical reason (a child-authored fact, "no
-- guardian involvement needed to record it"). No system-role read policy
-- either — see this migration's own header for why: nothing in this pass
-- reads this column back at all.
CREATE POLICY child_profile_owner_only ON child_profile
  FOR ALL USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

-- ------------------------------------------------- health_check extension --
-- Same discipline every migration in this series restates: the
-- rls_unforced list is CARRIED FORWARD IN FULL (from 0030), plus
-- child_profile (this migration) — packages/db/test/rls_coverage.test.mjs
-- fails outright on a real Postgres if it is missing, the automated
-- backstop 0029 itself added for exactly this recurring mistake.
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
     -- Carried forward from 0030, plus child_profile (this migration).
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
                        'child_profile')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE child_profile IS
  'A bare, unscored, non-comparative fact about the child (gender), written '
  'once by her own session via onboarding_gender.dart -- a real tap, never '
  'a forced choice. NULL/no-row is the honest "skipped" state, never '
  'coerced into a fabricated default. Child-owned RLS, no guardian policy '
  'of any kind, no system-role read -- nothing in this codebase reads this '
  'column back yet (see this migration''s own header).';

COMMIT;
