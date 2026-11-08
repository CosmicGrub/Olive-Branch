-- ============================================================================
--  OLIVE BRANCH — parent_learn
--
--  Server side of the guardian-only Parent Learn suite
--  (packages/parent-learn/src/learn.ts; docs/superpowers/specs/2026-11-07-
--  parenting-styles-education-research.md; mockups parent-learn-suite-
--  mockups.html). Owner decisions 2026-11-07: the Learn tab is in; private
--  reflection, cultural framing, the two-home rules list and the message
--  check are each OPTIONAL, and every default is the most private choice.
--
--  THREE tables, all ENABLE + FORCE RLS:
--
--  1) guardian_learn_settings — one row per guardian. An ABSENT row means
--     "defaults" (session-only reflection, neutral framing, rules list off,
--     message check off); defaults are never stored, so a new guardian has
--     no row to leak. Only that guardian reads or writes it
--     (guardian_id = current_actor()).
--
--  2) guardian_reflection — the private two-slider day check (warmth,
--     expectations). Owner-only: NOT the co-guardian, NOT a child, NOT a
--     sitter/step-parent/coordinator (current_role_name() must be exactly
--     'guardian' AND guardian_id = current_actor()), and deliberately NO
--     system-role policy. It is not joined by any view or export.
--     THIS TABLE MUST NEVER BE ADDED TO ANY COURT EXPORT, raw export,
--     certified export or handover bundle — a stored reflection could become
--     evidence in a dispute, which is exactly what the feature's own rule L2
--     exists to prevent. One honest limit: tools/backup-db.sh runs as
--     backup_reader (BYPASSRLS, 0022), so an operational backup does contain
--     these rows; RLS cannot and does not hide them from it. Backups are
--     operator-held, not exposed to any app role.
--
--  3) guardian_house_rule — the optional two-home rules list. The scope is
--     the CHILD (this schema has no "family" table; a family is the set of
--     live guardians of one child — guardianship, 0001). The author writes
--     and deletes their own rows (FOR ALL, keyed on author_guardian_id =
--     current_actor() AND a live edge to the child); the OTHER live
--     guardians of the same child may SELECT them. Only the four core
--     categories exist; no style, no reflection, no setting can be stored
--     here (CHECK). Children and non-'guardian' roles never see it.
--
--  The server (packages/db/src/pool.ts) additionally refuses a reflection
--  write unless the guardian's stored settings say reflection = 'saved', and
--  a rules write unless rules_list = true; turning rules_list off deletes
--  the author's shared rows in the same transaction (a shared list must
--  never outlive its opt-in).
-- ============================================================================

BEGIN;

CREATE TABLE guardian_learn_settings (
  guardian_id   uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  reflection    text    NOT NULL DEFAULT 'session' CHECK (reflection IN ('off','session','saved')),
  framing       text    NOT NULL DEFAULT 'neutral' CHECK (framing IN ('neutral','culture-note','values-first')),
  rules_list    boolean NOT NULL DEFAULT false,
  message_check boolean NOT NULL DEFAULT false,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE guardian_reflection (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  guardian_id  uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  day          date NOT NULL,
  warmth       smallint NOT NULL CHECK (warmth BETWEEN 0 AND 100),
  expectations smallint NOT NULL CHECK (expectations BETWEEN 0 AND 100),
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (guardian_id, day)
);

CREATE TABLE guardian_house_rule (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id           uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  author_guardian_id uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  category           text NOT NULL CHECK (category IN ('bedtime','screens','homework','safety')),
  body               text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 200),
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX guardian_house_rule_child_idx ON guardian_house_rule (child_id);
CREATE INDEX guardian_house_rule_author_idx ON guardian_house_rule (author_guardian_id);

ALTER TABLE guardian_learn_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_learn_settings FORCE  ROW LEVEL SECURITY;
ALTER TABLE guardian_reflection     ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_reflection     FORCE  ROW LEVEL SECURITY;
ALTER TABLE guardian_house_rule     ENABLE ROW LEVEL SECURITY;
ALTER TABLE guardian_house_rule     FORCE  ROW LEVEL SECURITY;

CREATE POLICY learn_settings_owner ON guardian_learn_settings
  FOR ALL USING (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND guardian_id = current_actor()
  ) WITH CHECK (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND guardian_id = current_actor()
  );

CREATE POLICY reflection_owner ON guardian_reflection
  FOR ALL USING (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND guardian_id = current_actor()
  ) WITH CHECK (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND guardian_id = current_actor()
  );

CREATE POLICY house_rule_author ON guardian_house_rule
  FOR ALL USING (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL
    AND author_guardian_id = current_actor() AND actor_has_edge(child_id)
  ) WITH CHECK (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL
    AND author_guardian_id = current_actor() AND actor_has_edge(child_id)
  );

CREATE POLICY house_rule_coguardian_read ON guardian_house_rule
  FOR SELECT USING (
    current_role_name() = 'guardian' AND current_actor() IS NOT NULL AND actor_has_edge(child_id)
  );

-- ------------------------------------------------- health_check extension --
-- Same discipline every migration in this series restates: the rls_unforced
-- list is CARRIED FORWARD IN FULL (from 0033), plus the three tables above —
-- packages/db/test/rls_coverage.test.mjs fails outright on a real Postgres if
-- it is missing.
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
     -- Carried forward from 0033, plus the three Parent Learn tables
     -- (this migration).
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
                        'child_profile','device_pairing_code','paired_device',
                        'guardian_activity_override',
                        'guardian_learn_settings','guardian_reflection',
                        'guardian_house_rule')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE guardian_reflection IS
  'A guardian''s PRIVATE day reflection (warmth, expectations). Owner-only, no '
  'system policy, never exported — must never be added to any court/raw/'
  'certified export or any other table or view. Written only when the '
  'guardian''s own settings say reflection = saved.';

COMMENT ON TABLE guardian_house_rule IS
  'The optional two-home rules list: one guardian''s rule for one child in one '
  'of four core categories. Author-write, other live guardians of the same '
  'child may read. Scope is the child (a family is the set of live guardians '
  'of one child). Deleted when the author turns rules_list off.';

COMMIT;
