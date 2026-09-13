-- ============================================================================
--  OLIVE BRANCH — guardian_game_favorite, child_game_picker_state
--
--  MASTERFILE §9.2, docs/superpowers/specs/2026-09-12-intuitivism-gamepicker
--  -recommended-design.md ("Intuitivism pass, sub-project 3a"). Real backend
--  for GamePickerScreen's new Recommended row: a guardian-curated favourites
--  list (packages/games/src/favorites.ts's star()/unstar()/favouritesFor(),
--  the identical shape jokes.ts's own favourites already use) plus a single
--  small piece of state for the AGE-UNLOCK signal (favorites.ts's
--  newlyUnlocked()). Two tables, not one, because the two signals have two
--  different WRITERS — see each table's own comment below.
--
--  guardian_game_favorite: guardian-write/child-read, the theme-preference
--  route's own shape (0017_child_theme_preference.sql) — but a DIFFERENT
--  shape at the DATA layer. Deliberately NO child_id column: a favourite is
--  the GUARDIAN'S OWN preference, not a per-child row, mirroring
--  guardian_availability_window's (0010) own guardian-id-only shape rather
--  than child_theme_preference's per-child one — packages/db/src/pool.ts's
--  gameFavoritesFor() resolves "this child's favourites" the identical way
--  availabilityFor() already resolves "this child's guardians' windows":
--  guardiansOfChild() + `guardian_id = ANY($1)`, reused verbatim rather than
--  re-deriving that join a second way. RLS is the SAME `..._no_child` shape
--  every other guardian-only coordination table in this schema already uses
--  (medication/care_note/etc., 0026/0028) rather than guardian_availability_
--  window's own finer-grained own-row/co-guardian-read split: nothing about
--  favouriting needs per-guardian row ownership (any live guardian curating
--  the same child's catalogue is equally authoritative — the same "any live
--  'guardian' role session" coarseness child_theme_preference's own write
--  policy already accepts), and the route's own `can('settings', ...)` gate
--  is what actually scopes "a live edge to THIS child" before this table is
--  ever touched, the identical division of labor 0026/0028's own headers
--  already describe ("RLS is the child-exclusion backstop here, not the
--  fine-grained scoping"). PRIMARY KEY (guardian_id, kind), not a surrogate
--  id: star()/unstar() are idempotent set operations, so "does this row
--  exist" is the only question this table is ever asked — a natural key
--  makes a double-favourite structurally impossible rather than merely
--  application-policed.
--
--  child_game_picker_state: the INVERSE owner — written by the CHILD's own
--  session on GamePickerScreen open (favorites.ts's newlyUnlocked() doc
--  comment: "it's her age, her screen visit — no guardian involvement
--  needed to record it, unlike favorites"), read by the same GET route that
--  resolves the Recommended row. `age_at_last_open` is a NEW ROW PER CHILD,
--  not two new columns on `child` itself, for the EXACT reason
--  0017_child_theme_preference.sql's own header already gives for making
--  that same choice: `child` has never had row-level security enabled at
--  any point in this schema's history, and bolting a child-writable column
--  onto it here would be exactly the kind of undeclared widening of an
--  existing table's contract MASTERFILE §0 warns against — every current
--  reader of `child` would need a fresh audit this migration is not scoped
--  to do. A small, new, narrowly-RLS'd table closes the real gap instead,
--  the identical precedent 0017 itself set. RLS mirrors journal_owner_only/
--  letter_owner_only (0001/0003/0028) for the child-write half — a child
--  session owns exactly her own row, no guardian policy at all, "the
--  inverse of every `..._no_child` policy elsewhere in this schema" the
--  same way 0028's own header describes `letter` — plus one system-role
--  read policy (child_theme_system_read's own precedent, 0017) for
--  gameFavoritesFor()'s combined read.
--
--  One nullable smallint, overwritten on every open, never a log: exactly
--  the "one integer, overwritten... never a log or history of opens" shape
--  the design spec's own Persistence section specifies.
-- ============================================================================

BEGIN;

CREATE TABLE guardian_game_favorite (
  guardian_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  kind        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (guardian_id, kind)
);

ALTER TABLE guardian_game_favorite ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_game_favorite FORCE  ROW LEVEL SECURITY;
CREATE POLICY guardian_game_favorite_no_child ON guardian_game_favorite
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

CREATE TABLE child_game_picker_state (
  child_id        uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,
  -- Her real age (EXTRACT(YEAR FROM age(...)) against child.birth_date),
  -- computed server-side at write time by pool.ts's recordGamePickerOpen()
  -- — never trusted from the client, the same discipline sealLetterRow()
  -- (0028) already applies to written_at_age. Nullable: no row at all is
  -- the honest, common "never opened this screen" state, matching
  -- favorites.ts's newlyUnlocked() own null-means-first-visit contract.
  age_at_last_open smallint,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE child_game_picker_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_game_picker_state FORCE  ROW LEVEL SECURITY;

-- The child owns her own row outright — no guardian policy exists here at
-- all, deliberately: mirrors letter_owner_only's own "inverse of every
-- `..._no_child` policy elsewhere" shape (0028), not child_theme_preference's
-- guardian-write/child-read split, because THIS half of the design is
-- child-authored by construction (the design spec's own "no guardian
-- involvement needed to record it, unlike favorites" line).
CREATE POLICY child_game_picker_state_owner_only ON child_game_picker_state
  FOR ALL USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

-- System-role read, for pool.ts's gameFavoritesFor() — mirrors
-- child_theme_system_read's own reasoning (0017) verbatim: the route
-- handler's real A3 childId-from-path + can('settings', ...) check already
-- gated this call before it runs, so granting the trusted backend role read
-- access here only lets that one already-authorized call finish.
CREATE POLICY child_game_picker_state_system_read ON child_game_picker_state
  FOR SELECT USING (current_role_name() = 'system');

-- ------------------------------------------------- health_check extension --
-- Same discipline every migration in this series restates: the
-- rls_unforced list is CARRIED FORWARD IN FULL (from 0029), plus the two
-- tables this migration gives real RLS, not appended-and-hope —
-- packages/db/test/rls_coverage.test.mjs fails outright on a real Postgres
-- if either is missing, the automated backstop 0029 itself added for
-- exactly this recurring mistake.
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
     -- Carried forward from 0029, plus guardian_game_favorite and
     -- child_game_picker_state (this migration).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference',
                        'call_log','media_artifact','intent_batch','delivery_intent',
                        'medication','medical_record','medication_dose',
                        'exchange_bag_item',
                        'exchange_running_late_log','exchange_arrival_event',
                        'care_note','letter',
                        'guardian_game_favorite','child_game_picker_state')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE guardian_game_favorite IS
  'A guardian''s own curated set of favourite game kinds, resolved for a '
  'given child via guardiansOfChild() + guardian_id = ANY(...), the same '
  'shape guardian_availability_window already uses. No child session ever '
  'reads or writes this table directly. RLS: `..._no_child`.';

COMMENT ON TABLE child_game_picker_state IS
  'One nullable age_at_last_open per child, overwritten (never logged) on '
  'every GamePickerScreen open by the CHILD''s own session, computed '
  'server-side from her real birth_date. Feeds favorites.ts''s '
  'newlyUnlocked() age-unlock signal. Guardian-excluded, child-owned RLS, '
  'the inverse of guardian_game_favorite above.';

COMMIT;
