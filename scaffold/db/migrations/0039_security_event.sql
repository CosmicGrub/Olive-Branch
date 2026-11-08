-- ============================================================================
--  OLIVE BRANCH — security_event feed + medication_dose composite FK
--  (security audit round 2: S-B3, S-B5, S-B20)
--
--  security_event
--  --------------
--  A content-free, append-only record of the account-level changes that matter
--  to the OTHER guardian of a child: a passkey added or removed, a PIN
--  changed or locked out, a device paired, an export taken, an invite sent.
--  It is the "notification-ready feed" the audit asked for: nothing here
--  sends anything (the owner's offline-first direction parks push), it is
--  only the durable source a later notifier can read via `notified_at` and
--  the monotonic `seq` cursor.
--
--  One row PER CHILD the actor holds a live edge to, because the readers are
--  "every live guardian of that child". `summary` is chosen by the server
--  from a fixed per-kind template (never from request input), so the row can
--  never carry a message body, a PIN, an email or a device label.
--
--  Written only by the `system` role (pool.ts recordSecurityEvent), read by an
--  adult actor who holds a live edge to the child (actor_has_edge, 0003).
--  There is no UPDATE/DELETE policy for anyone but a narrow `notified_at`
--  stamp by `system`, and a trigger refuses every other change, so a
--  compromised session cannot erase the trail of its own break-in.
--
--  medication_dose composite FK
--  ----------------------------
--  medication_dose.child_id was a free-standing denormalised copy of
--  medication.child_id, which is how POST .../medications/:medicationId/doses
--  could record a dose of ANOTHER family's medication under the caller's own
--  child (S-B5). (medication_id, child_id) now has to match a real
--  medication row. Added NOT VALID and then validated best-effort: a database
--  that already holds a mismatching row keeps enforcing the constraint for
--  every new row and is told about the old ones in a NOTICE instead of
--  failing the whole migration.
-- ============================================================================

BEGIN;

CREATE TABLE security_event (
  seq          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  actor_id     uuid NOT NULL REFERENCES app_user(id),
  kind         text NOT NULL CHECK (kind IN (
                 'passkey_added', 'passkey_removed', 'pin_changed', 'pin_lockout',
                 'device_paired', 'export_taken', 'invite_created')),
  summary      text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 120),
  created_at   timestamptz NOT NULL DEFAULT now(),
  -- Reserved for a future notifier (push is parked): NULL = not yet announced.
  notified_at  timestamptz
);
CREATE INDEX security_event_child_idx ON security_event (child_id, seq DESC);
CREATE INDEX security_event_unnotified_idx ON security_event (seq) WHERE notified_at IS NULL;

ALTER TABLE security_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_event FORCE  ROW LEVEL SECURITY;

CREATE POLICY security_event_adult_read ON security_event
  FOR SELECT USING (
    current_role_name() IN ('guardian','step_parent','trusted_adult','foster_parent')
    AND current_actor() IS NOT NULL
    AND actor_has_edge(child_id)
  );
CREATE POLICY security_event_system_all ON security_event
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

CREATE FUNCTION security_event_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' AND pg_trigger_depth() >= 2 THEN
    RETURN OLD;  -- child_id ON DELETE CASCADE only
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.seq = OLD.seq AND NEW.child_id = OLD.child_id AND NEW.actor_id = OLD.actor_id
     AND NEW.kind = OLD.kind AND NEW.summary = OLD.summary AND NEW.created_at = OLD.created_at THEN
    RETURN NEW;  -- only notified_at may move
  END IF;
  RAISE EXCEPTION 'security_event is append-only (% refused)', TG_OP
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER security_event_no_change
  BEFORE UPDATE OR DELETE ON security_event
  FOR EACH ROW EXECUTE FUNCTION security_event_append_only();

COMMENT ON TABLE security_event IS
  'Content-free security feed (passkey/PIN/device/export/invite) readable by every live guardian of the child. '
  'Append-only; only notified_at may be stamped. Written by system only.';

-- ---- S-B5: a dose can only belong to a medication of the SAME child --------
ALTER TABLE medication ADD CONSTRAINT medication_id_child_key UNIQUE (id, child_id);
ALTER TABLE medication_dose
  ADD CONSTRAINT medication_dose_medication_child_fk
  FOREIGN KEY (medication_id, child_id) REFERENCES medication (id, child_id)
  ON DELETE CASCADE NOT VALID;
DO $$
BEGIN
  ALTER TABLE medication_dose VALIDATE CONSTRAINT medication_dose_medication_child_fk;
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'medication_dose has rows whose child_id does not match their medication; '
               'the composite FK is enforced for new rows only. Audit them by hand.';
END $$;

-- health_check's rls_unforced list is extended once, in 0041, for every table
-- this audit round adds (security_event, media_upload) or newly protects (child,
-- guardianship).

COMMIT;
