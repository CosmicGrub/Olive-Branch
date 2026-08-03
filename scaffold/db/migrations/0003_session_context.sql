-- ============================================================================
--  OLIVE BRANCH — session context hardening + authorization helpers
--  MASTERFILE §5.1, §8.1, prohibitions P6 / P7.  See db/DEPLOYMENT.md.
-- ============================================================================

BEGIN;

-- ------------------------------------------------------- session accessors --
-- Wrapping GUC reads in functions instead of inlining them in policies buys
-- three things: one place to harden, a testable unit, and immunity to the
-- empty-string hazard below.

-- HAZARD, fixed here. `current_setting('app.child_id', true)::uuid` returns
-- NULL when the GUC is UNSET, but RAISES on an EMPTY STRING:
--     ERROR: invalid input syntax for type uuid: ""
-- A connection pool that sets both GUCs unconditionally — the normal pattern —
-- therefore turns every journal read into a 500 rather than an empty result.
-- Fail-crash instead of fail-closed. NULLIF collapses both cases to NULL.
CREATE OR REPLACE FUNCTION current_child() RETURNS uuid AS $$
  SELECT NULLIF(current_setting('app.child_id', true), '')::uuid;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION current_role_name() RETURNS text AS $$
  SELECT NULLIF(current_setting('app.role', true), '');
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION current_actor() RETURNS uuid AS $$
  SELECT NULLIF(current_setting('app.user_id', true), '')::uuid;
$$ LANGUAGE sql STABLE;

-- ------------------------------------------------------------ P7, hardened --
DROP POLICY IF EXISTS journal_owner_only ON child_journal_entry;
CREATE POLICY journal_owner_only ON child_journal_entry
  FOR ALL USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

-- ------------------------------------------------------ effective edges -----
-- One definition of "this edge grants access right now", used everywhere.
-- Four independent ways an edge stops counting, each of which has been a real
-- bug in someone's system:
--   closed_at    — parent died, order changed, access revoked
--   expires_at   — sitter token lapsed
--   valid        — order not yet in force, or already ended
--   restricted   — protective order
CREATE OR REPLACE VIEW effective_guardianship AS
SELECT g.*,
       (SELECT cl.step
          FROM contact_ladder cl
         WHERE cl.guardianship_id = g.id
           AND cl.effective @> now()
         ORDER BY lower(cl.effective) DESC
         LIMIT 1) AS ladder_step
  FROM guardianship g
 WHERE g.closed_at IS NULL
   AND (g.expires_at IS NULL OR g.expires_at > now())
   AND g.valid @> now();

-- Does the CURRENT session's actor hold a live edge to this child?
-- Deliberately does NOT traverse sibling_link: being guardian of one sibling
-- must never confer access to another. That traversal is the obvious lateral
-- privilege-escalation path in a family graph.
CREATE OR REPLACE FUNCTION actor_has_edge(p_child uuid) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM effective_guardianship e
     WHERE e.child_id = p_child
       AND e.user_id  = current_actor()
       AND e.restricted = false
       AND COALESCE(e.ladder_step, 'open') <> 'none'
  );
$$ LANGUAGE sql STABLE;

-- ------------------------------------------------------------ P6, enforced --
-- The expense table lands in Phase 3, but the guard ships now so it cannot be
-- forgotten when the table arrives. §12.1 reasoning.
CREATE OR REPLACE FUNCTION assert_no_child_financial_access() RETURNS void AS $$
BEGIN
  IF current_role_name() = 'child' THEN
    RAISE EXCEPTION 'P6: financial surfaces are not visible to a child role';
  END IF;
END $$ LANGUAGE plpgsql STABLE;

-- ------------------------------------------------- archive scoping (§2.11) --
-- Raw export is always available to a live guardian, on every tier, including
-- after cancellation. Principle §2.11 — the archive is never held hostage.
CREATE OR REPLACE FUNCTION exportable_artifacts(p_child uuid)
RETURNS SETOF media_artifact AS $$
  SELECT m.* FROM media_artifact m
   WHERE m.child_id = p_child
     AND actor_has_edge(p_child);
$$ LANGUAGE sql STABLE;

COMMIT;
