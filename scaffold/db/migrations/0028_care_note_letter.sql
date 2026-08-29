-- ============================================================================
--  OLIVE BRANCH — care_note, letter
--
--  Real backend for the LAST TWO coordination-layer features closed this
--  round (handover log, expenses, medications/emergency-card, exchange came
--  first -- v0.49.52-0.49.55). Found by this project's own coordination-layer
--  audit (MASTERFILE §20.2b): care_note.dart (guardian.ts §12.5's port) and
--  letters_screen.dart (maturation.ts §21.4/§21.8's port) have real,
--  already-tested pure logic but no table, route, or pool.ts function
--  anywhere -- neither screen has ever made a network call.
--
--  care_note: same guardian-only `..._no_child` shape every other
--  coordination table in this migration series uses.
--
--  letter is the outlier in this whole codebase: it is CHILD-owned and
--  GUARDIAN-EXCLUDED, the inverse of every other table here. RLS mirrors
--  `journal_owner_only` (0001/0003) exactly -- `current_role_name() = 'child'
--  AND child_id = current_child()` -- so a guardian session cannot read a
--  single row, ever, at the database layer, not just the route layer.
--
--  The real "nobody can open it early, not even her" invariant
--  (packages/maturation/src/maturation.ts's own openLetter() doc comment) is
--  enforced structurally here too: `body` is a real column, but pool.ts's own
--  read function (lettersFor()) never selects it unless `opened_at IS NOT
--  NULL` -- the same "the guard lives in the query, not just app logic"
--  discipline exchange_arrival_event's missing location column already
--  established for P3. `opened_at` itself can only be set by
--  recordLetterOpened() (pool.ts), which computes the child's REAL current
--  age server-side from child.birth_date -- never trusted from the client,
--  same discipline every other child-local-time write in this file already
--  follows (medication_dose.local_date, exchange_arrival_event.scheduled_at).
--
--  One deliberate departure from maturation.ts's own `Letter.artifactId`
--  shape (a pointer into media_artifact, matching letters_screen.dart's own
--  file-header speculation about the "real" backend): media_artifact's
--  `retention_or_preserved`/`preservation_is_attributed` CHECK constraints
--  assume a GUARDIAN explicitly preserves something that would otherwise
--  expire (0001_phase0_init.sql's own header) -- a letter has no guardian
--  preserver and is never on a retention clock at all ("It gets kept
--  forever," letters_screen.dart's own copy). Forcing it through that model
--  would need `preserved_by` attributed to nobody real. `body text` directly
--  on this table is simpler and equally real for a screen with no separate
--  media/attachment concept.
--
--  Also closes a real, accumulated gap in this project's own `rls_unforced`
--  health-check (0005/0006/.../0023): `medication`/`medical_record`
--  (0026) and `exchange_bag_item`/`exchange_running_late_log`/
--  `exchange_arrival_event` (0027) were never added to that list, so the
--  health-check monitor has had a blind spot for every one of them since
--  they shipped. Closed here in the same pass that touches this view again,
--  rather than left for a fourth PR to rediscover.
-- ============================================================================

BEGIN;

CREATE TABLE care_note (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  from_user_id  uuid NOT NULL REFERENCES app_user(id),
  -- '[{"kind":"mood","note":"..."}]' -- guardian.ts's own CareItem[] shape,
  -- verbatim (care_note.dart's own _sent list only ever carries one item per
  -- note today, but the pure writeCareNote() takes a real list).
  items         jsonb NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- CARE_NOTE_TTL_DAYS (guardian.ts) = 7. Computed at write time, not derived
  -- at read time, so a later change to the constant never silently
  -- reinterprets an already-written note's own real expiry.
  expires_at    timestamptz NOT NULL
);
CREATE INDEX ON care_note (child_id, expires_at DESC);

ALTER TABLE care_note ENABLE ROW LEVEL SECURITY;
ALTER TABLE care_note FORCE  ROW LEVEL SECURITY;
CREATE POLICY care_note_no_child ON care_note
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

CREATE TABLE letter (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id        uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  -- Computed server-side at seal time from the child's real birth_date --
  -- never trusted from the client (see this file's own header).
  written_at_age  integer NOT NULL CHECK (written_at_age >= 0),
  -- A genuine user CHOICE ("open it when I turn ___"), not a computed fact --
  -- legitimately client-supplied, but validated server-side against the
  -- REAL written_at_age below, never a client-claimed one.
  open_at_age     integer NOT NULL,
  written_at      timestamptz NOT NULL DEFAULT now(),
  body            text NOT NULL,
  opened_at       timestamptz,
  -- MIN_SEAL_YEARS / MAX_SEAL_TO_AGE (maturation.ts) -- the exact bounds
  -- sealLetter()'s own pure port already checks client-side, backstopped
  -- here so a direct write can never bypass them either.
  CONSTRAINT letter_min_seal_years CHECK (open_at_age - written_at_age >= 1),
  CONSTRAINT letter_max_seal_to_age CHECK (open_at_age <= 25)
);
CREATE INDEX ON letter (child_id, written_at DESC);

ALTER TABLE letter ENABLE ROW LEVEL SECURITY;
ALTER TABLE letter FORCE  ROW LEVEL SECURITY;
-- The inverse of every `..._no_child` policy elsewhere in this schema --
-- see this file's own header. Mirrors journal_owner_only (0001/0003)
-- exactly: only the OWNING child's own session, never a guardian, ever.
CREATE POLICY letter_owner_only ON letter
  FOR ALL USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

-- -----------------------------------------------------------------------
-- health_check, extended again (0005 -> 0006 -> 0008 -> 0013 -> 0014 ->
-- 0017 -> 0018 -> 0023 -> here). care_note/letter join the rls_unforced
-- list for the first time; medication/medical_record/exchange_bag_item/
-- exchange_running_late_log/exchange_arrival_event join it late (see this
-- file's own header for why that was a real, disclosed gap, not new scope).
-- -----------------------------------------------------------------------
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
     -- Carried forward from 0023, plus care_note/letter (this migration)
     -- and medication/medical_record/exchange_bag_item/
     -- exchange_running_late_log/exchange_arrival_event (0026/0027 -- a
     -- real gap this migration also closes, see this file's own header).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference',
                        'call_log','media_artifact','intent_batch','delivery_intent',
                        'medication','medical_record','exchange_bag_item',
                        'exchange_running_late_log','exchange_arrival_event',
                        'care_note','letter')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
