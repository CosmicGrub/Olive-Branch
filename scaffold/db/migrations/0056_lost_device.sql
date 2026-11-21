-- ============================================================================
--  OLIVE BRANCH -- a lost or stolen phone or tablet, handled in the open
--
--  Until now the only thing a grown-up could do about a lost phone was a hard,
--  permanent revoke (children's tablets) or a "Sign out" on the phone itself
--  (which a lost phone cannot do). Nothing was reversible, nothing told the
--  other grown-ups, and a found phone could never come back.
--
--  A device now has three standings:
--
--    active    the normal state.
--    paused    "marked as lost". Immediate. Its session and its refresh are
--              refused from that moment (the same server check that already
--              cuts off a revoked device), so it receives nothing new. NOTHING
--              is deleted anywhere: every record, message and picture stays
--              where it is. Reversible while the notice runs.
--    revoked   the existing permanent cut-off (revoked_at). A paused device
--              becomes revoked on its own when the 72 hour notice ends (the
--              owner has had three days to say "I have it"), or at once when
--              the owner (or, for a tablet, a grown-up) says "It is lost".
--
--  Who may do what is decided in pool.ts (the route is the first lock; this
--  schema is the second): a grown-up may mark their OWN other phone, or the
--  phone of another grown-up of the same family, or a child's tablet of the
--  same family, and only with their own PIN. Marking is idempotent: marking an
--  already-marked device never restarts its 72 hours. "I have it" must name
--  the incident it answers, so an old answer replayed after a second loss does
--  nothing. A device marked by its OWNER can only be resumed by its owner (a
--  second grown-up cannot undo the owner's own report), unless the phone the
--  owner reported FROM has itself been cut off since.
--
--  device_lost_event is the append-only, content-free history ("visible to
--  every grown-up", no names, no places). It is also what the rate limit reads
--  (three marks of one device in a day) so the pause cannot be turned into a
--  harassing loop.
--
--  reproof_required: a grown-up's phone that comes back from a pause must show
--  its owner's own PIN once before it gets a session again (screen L5). A
--  child's tablet has no PIN to show; the grown-up who said "I have it"
--  already showed theirs.
-- ============================================================================

BEGIN;

ALTER TABLE paired_device
  ADD COLUMN paused_at           timestamptz,
  ADD COLUMN lost_incident       uuid,
  ADD COLUMN lost_marked_by      uuid REFERENCES app_user(id) ON DELETE SET NULL,
  -- the device the mark was made FROM (null when the session had none). A device its owner marked can be resumed
  -- by a second grown-up only when this device is itself no longer active (a thief who knew the PIN marked the
  -- owner's other phone from the stolen one: the stolen one gets paused, and then the owner's real phone can be
  -- brought back by the other grown-up instead of staying stuck for three days).
  ADD COLUMN lost_marked_from    uuid REFERENCES paired_device(id) ON DELETE SET NULL,
  ADD COLUMN lost_revoke_due_at  timestamptz,
  ADD COLUMN reproof_required    boolean NOT NULL DEFAULT false,
  -- Erase-on-next-contact (a grown-up's phone only; never a child's tablet, whose private areas are hers). Ordered by
  -- the phone's OWNER with their own PIN after it was marked as lost; the phone is told the next time it reaches the
  -- server and says so when it is done. It erases the app's copy ON THAT PHONE; every record stays with the family.
  ADD COLUMN wipe_ordered_at     timestamptz,
  ADD COLUMN wipe_ordered_by     uuid REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN wiped_at            timestamptz;

-- An erase can only be ordered for a grown-up's phone, and it can only be reported done if it was ordered.
ALTER TABLE paired_device ADD CONSTRAINT paired_device_wipe_shape CHECK (
  (wipe_ordered_at IS NULL OR role = 'guardian')
  AND (wiped_at IS NULL OR wipe_ordered_at IS NOT NULL)
);

-- A pause is either fully described or absent; a revoked device is never also
-- an open pause.
ALTER TABLE paired_device ADD CONSTRAINT paired_device_pause_shape CHECK (
  (paused_at IS NULL AND lost_incident IS NULL AND lost_revoke_due_at IS NULL)
  OR (paused_at IS NOT NULL AND lost_incident IS NOT NULL AND lost_revoke_due_at IS NOT NULL
      AND lost_revoke_due_at > paused_at)
);

CREATE TABLE device_lost_event (
  seq         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_id   uuid NOT NULL REFERENCES paired_device(id) ON DELETE CASCADE,
  incident_id uuid NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('marked', 'found', 'confirmed', 'cut_off', 'wipe_ordered', 'wipe_cancelled', 'wiped')),
  actor_id    uuid REFERENCES app_user(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX device_lost_event_device_idx ON device_lost_event (device_id, seq DESC);

ALTER TABLE device_lost_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_lost_event FORCE  ROW LEVEL SECURITY;

-- Written by the system role only (the pool function that did the work).
CREATE POLICY device_lost_event_system_all ON device_lost_event
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

-- Read by whoever may already see the device row (the family's grown-ups).
CREATE POLICY device_lost_event_family_read ON device_lost_event
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM paired_device d WHERE d.id = device_lost_event.device_id)
  );

-- Append only: nothing here is ever edited, and only the device row's own
-- removal (ON DELETE CASCADE, a deleted account) may take rows away.
CREATE FUNCTION device_lost_event_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' AND pg_trigger_depth() >= 2 THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'device_lost_event is append-only (% refused)', TG_OP
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER device_lost_event_no_change
  BEFORE UPDATE OR DELETE ON device_lost_event
  FOR EACH ROW EXECUTE FUNCTION device_lost_event_append_only();

COMMENT ON TABLE device_lost_event IS
  'Append-only, content-free history of "marked as lost" / "I have it" / '
  '"It is lost" / cut off after the notice (0056). No names, no places.';

-- ---------------------------------------------------- security_event -------
-- Merged into whatever the constraint holds now (0053 and 0055 each add kinds), never swapped in as a fixed list.
DO $$
DECLARE
  def   text;
  kinds text[];
  add_kinds text[] := ARRAY['device_lost', 'device_found', 'device_lost_final', 'device_wipe_ordered', 'device_wiped'];
  k text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO def
    FROM pg_constraint c
   WHERE c.conname = 'security_event_kind_check' AND c.conrelid = 'security_event'::regclass;
  IF def IS NULL THEN
    RAISE EXCEPTION 'security_event_kind_check is missing; cannot add the lost-phone kinds';
  END IF;
  SELECT array_agg(m[1]) INTO kinds FROM regexp_matches(def, '''([a-z_]+)''', 'g') AS m;
  FOREACH k IN ARRAY add_kinds LOOP
    IF NOT (k = ANY (kinds)) THEN kinds := kinds || k; END IF;
  END LOOP;
  ALTER TABLE security_event DROP CONSTRAINT security_event_kind_check;
  EXECUTE 'ALTER TABLE security_event ADD CONSTRAINT security_event_kind_check CHECK (kind IN ('
    || (SELECT string_agg(quote_literal(x), ', ' ORDER BY x) FROM unnest(kinds) AS x) || '))';
END
$$;

COMMIT;
