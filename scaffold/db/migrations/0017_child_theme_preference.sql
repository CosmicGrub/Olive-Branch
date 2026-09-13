-- ============================================================================
--  OLIVE BRANCH — child_theme_preference
--  MASTERFILE §8.1, docs/superpowers/specs/2026-08-21-intuitivism-visual-
--  foundation-design.md ("sub-project 1: visual foundation").
--
--  The theme catalog itself (client/lib/theme.dart's ThemePalette x
--  ThemeBrightness -> ColorScheme.fromSeed()) is pure client-side logic with
--  nothing to persist on its own. This migration is the one real gap that
--  logic cannot close alone: "backend-synced so the theme is consistent
--  across both physical devices (Fold5/tablet) regardless of which one the
--  child is holding" needs a row SOMEWHERE a guardian's device can write and
--  a child's device can read, the same shape every other cross-device
--  preference in this schema already takes.
--
--  A NEW TABLE, not two new columns on `child` itself, despite `child` being
--  a real candidate (0001_phase0_init.sql). Checked first, deliberately:
--  `child` has NEVER had row-level security enabled at any point in this
--  schema's history (grepped every migration; the table is not among
--  0001/0003/0007's own RLS-enabled set, and health_check's own
--  `rls_unforced` audit list -- carried forward in full across 0013/0014 --
--  has never named it either). Enabling RLS on `child` for the first time,
--  here, as a side effect of two preference columns, would be exactly the
--  kind of undeclared, unaudited widening of an existing table's contract
--  MASTERFILE §0 warns against -- every current reader of `child` (the
--  schedule engine, the delivery sweep, health_check itself) would need a
--  fresh audit this migration is not scoped to do. A small, new, narrowly-
--  RLS'd table -- exactly guardian_availability_window's (0010) own
--  precedent -- closes the real gap without touching that blast radius.
--
--  One row per child (PRIMARY KEY child_id, upsert on write), both
--  preference columns NULLABLE — an unset row (or no row at all) is the
--  REAL, common case (a family that has never opened the picker) and must
--  read back as a clean, honest absence, never a fabricated default row.
--  routes.mjs's GET handler and client/lib/theme.dart's `AppTheme.fromWire`
--  both already collapse a null/missing value to `classic`/`light` — the
--  fail-closed fallback lives THERE, not as a NOT NULL DEFAULT here, so a
--  family that has never chosen a theme is honestly distinguishable (in the
--  data) from one that explicitly chose `classic`/`light`.
-- ============================================================================

BEGIN;

CREATE TABLE child_theme_preference (
  child_id         uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,
  theme_palette    text CHECK (theme_palette IN
                     ('classic','calmModern','warmGrounded','softPlayful','deepCozy','brightBold')),
  theme_brightness text CHECK (theme_brightness IN ('light','dark')),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  -- Matches client/lib/theme.dart's AppTheme -- either both set (a real,
  -- complete guardian choice) or both null (never chosen). A palette with no
  -- brightness (or vice versa) is not a state this schema represents, so a
  -- half-written preference is a bug to reject at INSERT/UPDATE time, not a
  -- shape server/routes.mjs's reader has to special-case.
  CONSTRAINT theme_preference_complete_or_absent CHECK (
    (theme_palette IS NULL) = (theme_brightness IS NULL)
  )
);

-- ---------------------------------------------------------------------------
-- RLS. Both bypass paths db/DEPLOYMENT.md warns about are closed the same
-- way every other real table in this schema closes them: ENABLE + FORCE, no
-- exceptions for the table owner.
ALTER TABLE child_theme_preference ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_theme_preference FORCE  ROW LEVEL SECURITY;

-- 1) A guardian with a LIVE edge to this child may read AND write this row —
--    FOR ALL, one USING (which existing rows are visible/writable) and one
--    WITH CHECK (what an INSERT/UPDATE is allowed to leave behind), both
--    keyed on actor_has_edge() (0003_session_context.sql) rather than a raw
--    effective_guardianship join: it is this schema's own single definition
--    of "does the current session's actor really, currently, hold access to
--    this child" (excludes restricted edges and a ladder_step of 'none' too,
--    stricter than a bare EXISTS join would be), already written and
--    already used by exportable_artifacts() — reused here rather than
--    re-deriving the same check a second way.
--
--    Deliberately does NOT distinguish observer-only guardians the way
--    ROLE_CAPS/§17.3 does at the app layer (family-graph/src/authorize.ts's
--    'settings' action, in the WRITES list, denies an observer_readonly
--    guardian even a READ of this route) — this table's RLS is the
--    CODEBASE'S established coarser "second lock" (current_role_name() =
--    'guardian' really does mean "any adult session", the same reasoning
--    guardian_availability_window's own policy comment gives), with the
--    finer-grained scope distinction enforced one layer up, at the route.
CREATE POLICY child_theme_guardian_edge ON child_theme_preference
  FOR ALL USING (
    current_role_name() = 'guardian'
    AND current_actor() IS NOT NULL
    AND actor_has_edge(child_id)
  ) WITH CHECK (
    current_role_name() = 'guardian'
    AND current_actor() IS NOT NULL
    AND actor_has_edge(child_id)
  );

-- 2) The child herself reads her own row — same shape custody_order's own
--    child-own policy (0007) already uses. She never gets a WRITE policy:
--    this is guardian-only by design (the design spec's own "resolved,
--    confirmed directly" line), so the absence of a child WITH CHECK here is
--    deliberate, not an oversight — an INSERT/UPDATE attempted under a
--    'child' role session simply matches no policy at all and is rejected.
CREATE POLICY child_theme_child_read ON child_theme_preference
  FOR SELECT USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

-- 3) System-role read, for server/routes.mjs's GET handler running
--    packages/db/src/pool.ts's themeFor() as `system` — mirrors
--    activeCustodyOrderFor()/availabilityFor()'s own reasoning: the route
--    handler's real A3 childId-from-path + can('settings', ...) check
--    already gated this call before it runs, so granting the trusted
--    backend role read access here only lets that one already-authorized
--    call finish; it is not a client-reachable widening. setChildTheme()
--    (the WRITE path) deliberately does NOT run as `system` — it opens its
--    own session as the real calling guardian instead, precisely so policy
--    1's actor_has_edge() check is the thing actually enforcing "a guardian
--    with a live edge can write", not just a comment claiming it (the same
--    "second lock" reasoning setAvailabilityWindows() already applies).
CREATE POLICY child_theme_system_read ON child_theme_preference
  FOR SELECT USING (current_role_name() = 'system');

-- ------------------------------------------------- health_check extension --
-- Same discipline 0013/0014 already restated: the rls_unforced list is
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
     -- Carried forward from 0014, plus child_theme_preference (this migration).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE child_theme_preference IS
  'The active guardian-chosen AppTheme (client/lib/theme.dart) for a child''s '
  'family, one row per child, both columns null until a guardian first Applies '
  'one. Guardian-write (live edge required)/child-read, RLS-enforced. Read by '
  'both physical devices a family uses (main_live.dart''s session bootstrap) '
  'so the theme is consistent regardless of which device the child is '
  'holding — app-wide, not per-child, despite being keyed by child_id (the '
  'only real identity this schema roots a family around).';

COMMIT;
