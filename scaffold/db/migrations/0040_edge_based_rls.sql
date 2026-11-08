-- ============================================================================
--  OLIVE BRANCH — cross-family isolation at the database (audit S-B4)
--
--  Until now the most sensitive tables (message_log = the court evidence,
--  expense, export_record, medical_record, medication, medication_dose,
--  exchange_*, care_note, custody_order's adult branch) were protected by
--  `current_role_name() IS DISTINCT FROM 'child'` alone. That keeps a CHILD
--  out; it does nothing to keep family A's guardian out of family B's rows,
--  so tenant isolation rested entirely on can() plus each handler remembering
--  its own `WHERE child_id = $n`. S-B5 (a dose recorded against another
--  family's medication) was a live example of that failing.
--
--  This migration moves the second lock into the database:
--
--   1. adult_edge policies — an adult session (any non-child human role) may
--      touch a row only if actor_has_edge(child_id) (0003: a LIVE, unrestricted
--      guardianship edge). `system` keeps its blanket access: the scheduler,
--      the pool's identity lookups and the export builders run as system and
--      authorize through can() first, exactly as before.
--   2. child and guardianship get ENABLE + FORCE RLS. A guardian reads her OWN
--      edges and every edge of a child she currently guards (so a co-guardian's
--      edge, and a former guardian's closed edge in the same family, stay
--      readable — the export and the exchange screens need that — but another
--      family's edges do not). A child reads her own row and her own edges.
--      Only `system` writes either table.
--   3. app_user_read_all (USING (true): every session could read every user's
--      email and phone) is replaced by "yourself, or anyone who holds an edge
--      you can see"; app_user_insert_open (WITH CHECK (true)) is limited to
--      `system`, the only role that ever creates an account
--      (bootstrapGuardianInvite, seed-dev).
--
--  RECURSION: a policy on guardianship cannot subquery guardianship (Postgres
--  raises "infinite recursion detected in policy"). actor_child_ids() reads the
--  caller's live edges with a function-level `SET app.edge_lookup = 'on'`, and
--  the co-guardian branch of the guardianship policy short-circuits to false
--  while that setting is on, so the function sees only the caller's own rows
--  (the own-row branch) and the recursion bottoms out. The setting is a plain
--  GUC, forgeable by anything that can already run arbitrary SQL — but so is
--  app.role itself; this layer exists to contain a forgotten WHERE, not an
--  injection (S-B11's DML-only runtime role is the answer to that).
--
--  The backup role (BYPASSRLS, 0022) and the health_check view are unaffected.
-- ============================================================================

BEGIN;

-- ---- helpers ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION actor_is_adult() RETURNS boolean AS $$
  SELECT current_role_name() IN ('guardian','trusted_adult','step_parent','sitter',
                                 'coordinator','foster_parent','caseworker','therapist')
     AND current_actor() IS NOT NULL;
$$ LANGUAGE sql STABLE;

-- "an adult session with a live edge to this child" — the one predicate every
-- adult_edge policy below shares.
CREATE OR REPLACE FUNCTION actor_is_adult_with_edge(p_child uuid) RETURNS boolean AS $$
  SELECT actor_is_adult() AND actor_has_edge(p_child);
$$ LANGUAGE sql STABLE;

-- The children the current actor LIVE-guards (restricted/ladder 'none' edges
-- are left in on purpose: this is "whose family am I in", used only to widen
-- READ visibility of names and edges, never to authorize a write).
CREATE OR REPLACE FUNCTION actor_child_ids() RETURNS SETOF uuid AS $$
  SELECT g.child_id FROM effective_guardianship g WHERE g.user_id = current_actor();
$$ LANGUAGE sql STABLE SET app.edge_lookup = 'on';

-- ---- guardianship + child --------------------------------------------------
ALTER TABLE guardianship ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardianship FORCE  ROW LEVEL SECURITY;

CREATE POLICY guardianship_system_all ON guardianship
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');
CREATE POLICY guardianship_own_read ON guardianship
  FOR SELECT USING (current_actor() IS NOT NULL AND user_id = current_actor());
CREATE POLICY guardianship_child_read ON guardianship
  FOR SELECT USING (current_role_name() = 'child' AND child_id = current_child());
CREATE POLICY guardianship_family_read ON guardianship
  FOR SELECT USING (
    CASE WHEN current_setting('app.edge_lookup', true) = 'on' THEN false
         ELSE current_actor() IS NOT NULL AND child_id IN (SELECT actor_child_ids())
    END);

ALTER TABLE child ENABLE ROW LEVEL SECURITY;
ALTER TABLE child FORCE  ROW LEVEL SECURITY;

CREATE POLICY child_system_all ON child
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');
CREATE POLICY child_self_read ON child
  FOR SELECT USING (current_role_name() = 'child' AND id = current_child());
CREATE POLICY child_adult_edge_read ON child
  FOR SELECT USING (actor_is_adult_with_edge(id));

-- ---- app_user --------------------------------------------------------------
DROP POLICY app_user_read_all ON app_user;
DROP POLICY app_user_insert_open ON app_user;

CREATE POLICY app_user_system_all ON app_user
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');
CREATE POLICY app_user_self_read ON app_user
  FOR SELECT USING (current_actor() IS NOT NULL AND id = current_actor());
-- Anyone holding an edge the caller can already see (her own, a co-guardian's,
-- a former guardian's in the same family; for a child, her guardians').
CREATE POLICY app_user_visible_edge_read ON app_user
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM guardianship g WHERE g.user_id = app_user.id));
-- (app_user_self_update from 0011 is kept: UPDATE USING system OR id = actor.)

-- ---- adult_edge policies for the family-private tables ---------------------
-- Each: drop the "not a child" policy, add adult-with-edge + system.
-- custody_order keeps its existing child-branch policy (custody_order_child_own).
DROP POLICY log_no_child                   ON message_log;
DROP POLICY expense_no_child               ON expense;
DROP POLICY export_record_no_child         ON export_record;
DROP POLICY medical_record_no_child        ON medical_record;
DROP POLICY medication_no_child            ON medication;
DROP POLICY medication_dose_no_child       ON medication_dose;
DROP POLICY exchange_bag_item_no_child     ON exchange_bag_item;
DROP POLICY exchange_running_late_log_no_child ON exchange_running_late_log;
DROP POLICY exchange_arrival_event_no_child    ON exchange_arrival_event;
DROP POLICY care_note_no_child             ON care_note;
DROP POLICY custody_order_not_child_scope  ON custody_order;
DROP POLICY medical_record_history_read   ON medical_record_history;
DROP POLICY medical_record_history_insert ON medical_record_history;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'message_log','expense','export_record','medical_record','medication',
    'medication_dose','exchange_bag_item','exchange_running_late_log',
    'exchange_arrival_event','care_note','custody_order']
  LOOP
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR ALL USING (actor_is_adult_with_edge(child_id))',
      t || '_adult_edge', t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR ALL USING (current_role_name() = ''system'') '
      'WITH CHECK (current_role_name() = ''system'')',
      t || '_system_all', t);
  END LOOP;
END $$;

-- medical_record_history is read/insert only (append-only trigger, 0036).
CREATE POLICY medical_record_history_adult_edge_read ON medical_record_history
  FOR SELECT USING (actor_is_adult_with_edge(child_id));
CREATE POLICY medical_record_history_adult_edge_insert ON medical_record_history
  FOR INSERT WITH CHECK (actor_is_adult_with_edge(child_id));
CREATE POLICY medical_record_history_system_all ON medical_record_history
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMIT;
