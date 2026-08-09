-- ============================================================================
--  OLIVE BRANCH — child_games_access
--  MASTERFILE §5.18 (session context), §5.17 (first lock / second lock),
--  house convention: no settings affordance ever on a child-facing surface;
--  a lock/unlock CONTROL lives only on the guardian side, the child side may
--  only ever passively show whether games are on or off.
--
--  Games are dormant (locked) by default for every child, unlockable only by
--  that child's own guardian. This migration adds the one table that makes
--  that real and server-enforced -- games.mjs/games2.mjs/games3.mjs and every
--  existing game screen are untouched; this is purely an access gate wrapped
--  around them.
--
--  Why a dedicated table and not a bare `child.games_enabled` column (the
--  shape floated when this was scoped): Postgres RLS is table-scoped, not
--  column-scoped, and `child` itself carries NO row-level security today
--  (grep the migrations -- it never appears in an ENABLE/FORCE list). Bolting
--  a column onto `child` would mean either leaving it unprotected (no second
--  lock at all, contradicting the whole point of this migration) or RLS-
--  enabling `child` wholesale, which would need its OWN full policy set for
--  every existing role and column, an unrelated and much larger change. A
--  small dedicated table, RLS'd exactly like 0007's custody_order, gets the
--  real guarantee with a minimal, auditable surface.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0003_session_context.sql's actor_has_edge() deliberately admits ANY live
-- edge type (guardian, sitter, trusted_adult, ...) -- right for a read-only
-- surface like raw export, wrong here. Games access is gated exactly the way
-- family-graph/src/authorize.ts gates the `settings` action: ROLE_CAPS lists
-- `settings` for role 'guardian' ONLY, nothing else. This function is the
-- DB-side mirror of that same restriction -- the second lock checking the
-- same thing the first lock (can()) checks, not a laxer reinvention of it.
--
-- Deliberately mirrors can()'s own exclusions where they apply to a
-- non-contact action like `settings`: effective_guardianship already drops
-- closed/expired/outside-validity edges (can()'s edge_closed/edge_expired/
-- outside_validity), and `restricted = false` here matches can()'s
-- unconditional restricted check. Deliberately OMITTED: the ladder_step
-- exclusion actor_has_edge() applies -- can() only enforces ladder_step for
-- CONTACT actions ('call','message'), and 'settings' is not one, so mirroring
-- that exclusion here would make the second lock stricter than the first for
-- no reason grounded in the actual authorization model.
CREATE OR REPLACE FUNCTION actor_is_guardian_of(p_child uuid) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM effective_guardianship e
     WHERE e.child_id = p_child
       AND e.user_id  = current_actor()
       AND e.role     = 'guardian'
       AND e.restricted = false
  );
$$ LANGUAGE sql STABLE;

CREATE TABLE child_games_access (
  child_id      uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,

  -- Dormant by default for EVERY child -- the literal requirement, not an
  -- app-layer convention that a missing row could silently disagree with.
  games_enabled boolean NOT NULL DEFAULT false,

  -- Audit trail: which guardian last flipped this, and when. Nullable only
  -- because a defensive direct-SQL fixture (tests, a future backfill) may
  -- legitimately have no acting guardian to attribute; every real write
  -- through setGamesEnabledFor() (packages/db/src/pool.ts) always sets it.
  updated_by    uuid REFERENCES app_user(id),
  updated_at    timestamptz NOT NULL DEFAULT now()

  -- No EXCLUDE/overlap constraint: unlike custody_order's date ranges, a
  -- plain per-child boolean has no overlapping-interval invariant to guard.
  -- Forcing one here would protect nothing a PRIMARY KEY doesn't already.
);

-- ---------------------------------------------------------------------------
-- RLS. Two narrow policies, nothing else -- unlike 0007's custody_order
-- (which deliberately admits "anyone who isn't the child," relying on the
-- app layer for the rest), this table's whole point is that the DATABASE
-- itself, independent of the app layer, refuses a guardian with no live edge
-- and refuses everyone who isn't the child or her own guardian. No
-- "not_child_scope" catch-all here.
ALTER TABLE child_games_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_games_access FORCE  ROW LEVEL SECURITY;

-- Child: read her own row, and ONLY read it. FOR SELECT, deliberately not
-- FOR ALL -- a FOR ALL policy with no WITH CHECK falls back to reusing its
-- USING clause as the WITH CHECK, which would let a child session write her
-- own row. That must never be possible here (house convention: no settings
-- affordance ever on a child-facing surface); FOR SELECT makes it
-- structurally impossible rather than incidentally untested.
CREATE POLICY child_games_access_child_read ON child_games_access
  FOR SELECT USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

-- Guardian: read AND write, but only for a child she holds a real, live
-- 'guardian'-role edge to. WITH CHECK is written out explicitly (identical to
-- USING) rather than left to default, so both directions -- "which rows can
-- I see" and "what may I write" -- require the same live edge; a guardian
-- whose edge closes mid-transaction cannot rely on a laxer default check to
-- smuggle a write through.
CREATE POLICY child_games_access_guardian ON child_games_access
  FOR ALL USING (
    current_role_name() = 'guardian'
    AND actor_is_guardian_of(child_id)
  )
  WITH CHECK (
    current_role_name() = 'guardian'
    AND actor_is_guardian_of(child_id)
  );

-- No other policy exists. Every other role (trusted_adult, step_parent,
-- sitter, coordinator, foster_parent, caseworker, therapist, system, or no
-- role at all) is denied entirely, by omission: FORCE ROW LEVEL SECURITY with
-- no matching permissive policy is a hard deny, not a fall-through.

COMMIT;
