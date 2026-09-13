-- ============================================================================
--  OLIVE BRANCH — guardian_availability_window
--  MASTERFILE §9 (MARKUP screen 'availability', since 0.29.0 — "when he can
--  actually be reached, honestly rendered"), §5.17/§5.18 (session context,
--  the second lock), db/DEPLOYMENT.md (RLS bypass paths).
--
--  Closes the guardian_more.dart gap: HubSection 'Not yet built', the
--  Availability HubTile, previously calling _notBuiltYet with nothing behind
--  it. This is a DIFFERENT feature from §21.3's "she publishes her own
--  availability" (the age-15 ladder rung, child-authored, inverting who is
--  the subject of the schedule) — that one is unbuilt, future, and untouched
--  here. This table is the guardian-to-guardian one: each guardian's own
--  weekly reachability windows, so a co-parent can see "when he can actually
--  be reached" without asking.
-- ============================================================================

BEGIN;

-- weekday: 0=Sunday .. 6=Saturday, matching this codebase's existing
-- convention (packages/delivery-engine/src/materialize.ts's own
-- `DateTime...weekday % 7  // Sun=0`, reused verbatim rather than inventing a
-- second one) — NOT Luxon's native 1=Monday..7=Sunday ISO weekday.
--
-- Multiple rows per (guardian_id, weekday) are allowed on purpose — "his
-- reachability windows" is plural in the task this migration closes (e.g. a
-- morning window and a separate evening window on the same day). Nothing
-- here excludes overlapping windows for the same guardian/day; that would be
-- a UI nuisance, not a data-integrity violation the way custody_order's
-- date-range double-booking is, so no gist EXCLUDE constraint is added for
-- it — a deliberate scope choice, not an oversight.
CREATE TABLE guardian_availability_window (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  guardian_id  uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  weekday      smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_local  time NOT NULL,
  end_local    time NOT NULL,
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT availability_window_ordered CHECK (end_local > start_local)
);

CREATE INDEX ON guardian_availability_window (guardian_id, weekday);

-- ---------------------------------------------------------------------------
-- RLS. Both bypass paths db/DEPLOYMENT.md warns about are closed the same
-- way every other table in this codebase closes them: ENABLE + FORCE, no
-- exceptions for the table owner.
ALTER TABLE guardian_availability_window ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_availability_window FORCE  ROW LEVEL SECURITY;

-- 1) A guardian may read AND write only her own rows. FOR ALL covers
--    SELECT/INSERT/UPDATE/DELETE with one USING clause (governing which
--    existing rows are visible/deletable/updatable) and one WITH CHECK
--    clause (governing what an INSERT/UPDATE is allowed to leave behind) —
--    both pinned to current_actor(), the GUC withSession() sets from the
--    verified principal, never from request input (§5.18).
--
--    At the DB layer this codebase's session role is only ever
--    'child' | 'guardian' | 'system' (see auth.mjs/index.mjs — the finer
--    guardianship.role values like 'sitter'/'coordinator' are an edge
--    attribute the family-graph authorizer reads, not a session GUC), so
--    current_role_name() = 'guardian' really does mean "any adult session",
--    same as custody_order's own "not child" policies rely on.
CREATE POLICY guardian_availability_own ON guardian_availability_window
  FOR ALL USING (
    current_role_name() = 'guardian'
    AND current_actor() IS NOT NULL
    AND guardian_id = current_actor()
  ) WITH CHECK (
    current_role_name() = 'guardian'
    AND current_actor() IS NOT NULL
    AND guardian_id = current_actor()
  );

-- 2) "Any live guardian ... can READ another guardian's rows" — scoped to a
--    guardian who actually SHARES a child with the row's guardian, mirroring
--    how guardianship/edgesFor already establishes who shares a child
--    (packages/db/src/pool.ts's edgesFor/guardiansOfChild). effective_guardianship
--    (0003_session_context.sql) is this codebase's one definition of "this
--    edge grants access right now" — reused here rather than re-deriving
--    closed_at/expires_at/valid logic a second time.
CREATE POLICY guardian_availability_co_guardian_read ON guardian_availability_window
  FOR SELECT USING (
    current_role_name() = 'guardian'
    AND current_actor() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM effective_guardianship mine
        JOIN effective_guardianship theirs ON theirs.child_id = mine.child_id
       WHERE mine.user_id = current_actor()
         AND theirs.user_id = guardian_availability_window.guardian_id
    )
  );

-- 3) "... or the child of a shared child" — a child session may read a
--    guardian's windows when that guardian actually holds a live edge to
--    HER (i.e. he is one of her guardians). Same effective_guardianship
--    definition of "live" as policy 2, and the same shape custody_order's
--    own child-own policy already uses (current_child() from the GUC, never
--    from the query).
CREATE POLICY guardian_availability_child_read ON guardian_availability_window
  FOR SELECT USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM effective_guardianship eg
       WHERE eg.child_id = current_child()
         AND eg.user_id = guardian_availability_window.guardian_id
    )
  );

-- 4) System-role read, for packages/db/src/pool.ts's availabilityFor() —
--    mirrors custody_order's own reasoning for activeCustodyOrderFor()
--    running under withSystemSession: the route handler
--    (GET /v1/children/:childId/availability, action 'calendar.view')
--    already ran the real A3 childId-from-path authorization check before
--    this query executes, so granting the trusted backend role read access
--    here does not widen who can reach the data through the actual API —
--    it only lets the one already-authorized call finish. Nothing derived
--    from request input ever sets app.role to 'system'; only
--    withSystemSession() does (packages/db/src/pool.ts), so this is not a
--    client-reachable bypass.
CREATE POLICY guardian_availability_system_read ON guardian_availability_window
  FOR SELECT USING (current_role_name() = 'system');

COMMIT;
