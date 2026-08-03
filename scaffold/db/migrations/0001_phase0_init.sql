-- ============================================================================
--  OLIVE BRANCH — Phase 0 migration
--  Spec: MASTERFILE v0.4.0 §5
--
--  Three groups of columns ship here AHEAD of the features that consume them,
--  because each is cheap now and a migration-with-backfill later:
--    1. media_artifact.preserved   → Year Book, Phase 3        (§12.1)
--    2. sibling_link               → group calls, Phase 2      (§5.14)
--    3. guardianship.closed_at     → succession, Phase 4       (§18.1)
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------- identity --

CREATE TABLE app_user (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email         citext UNIQUE,                    -- NULL for child profiles
  display_name  text NOT NULL,
  home_tz       text NOT NULL,
  channel       text NOT NULL DEFAULT 'app' CHECK (channel IN ('app','sms')),
  phone_e164    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sms_needs_phone CHECK (channel <> 'sms' OR phone_e164 IS NOT NULL)
);

CREATE TABLE child (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  display_name   text NOT NULL,
  birth_date     date NOT NULL,
  home_tz        text NOT NULL,                   -- fallback only, never the answer
  privacy_tier   text NOT NULL DEFAULT 'transparent'
                 CHECK (privacy_tier IN ('transparent','graduated','autonomous')),
  majority_age   smallint NOT NULL DEFAULT 18,
  handed_over_at timestamptz,                     -- §9.8.4, irreversible
  deceased_at    timestamptz                      -- §18.3, halts all automation
);

CREATE TABLE household (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  label       text NOT NULL,
  tz          text NOT NULL,
  postal_code text
);

-- Guardianship is an EDGE. It CLOSES, it does not delete: a deceased parent's
-- history must survive the end of their access.  §18.1
CREATE TABLE guardianship (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  role          text NOT NULL CHECK (role IN
                  ('guardian','trusted_adult','step_parent','sitter','coordinator',
                   'foster_parent','caseworker','therapist')),
  scope         jsonb NOT NULL DEFAULT '{}',
  observer_only boolean NOT NULL DEFAULT false,   -- §17.3 reluctant-parent tier
  restricted    boolean NOT NULL DEFAULT false,   -- protective order
  order_ref     text,
  valid         tstzrange NOT NULL,
  expires_at    timestamptz,                      -- time-boxed sitter tokens
  closed_at     timestamptz,
  closed_reason text CHECK (closed_reason IN
                  ('death','court_order','revoked','expired','majority')),
  UNIQUE (child_id, user_id),
  CONSTRAINT closure_has_reason
    CHECK ((closed_at IS NULL) = (closed_reason IS NULL))
);

-- §5.15  Reunification is a ladder, not a boolean.
CREATE TABLE contact_ladder (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  guardianship_id uuid NOT NULL REFERENCES guardianship(id) ON DELETE CASCADE,
  step            text NOT NULL CHECK (step IN
                    ('none','supervised','monitored','time_limited','open')),
  advanced_by     uuid REFERENCES app_user(id),   -- coordinator/therapist/caseworker
  effective       tstzrange NOT NULL,
  order_ref       text,
  notes           text,
  EXCLUDE USING gist (guardianship_id WITH =, effective WITH &&)
);

-- §5.14  Relationship, not parentage.  Canonical ordering prevents duplicates.
CREATE TABLE sibling_link (
  child_a          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  child_b          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  kind             text NOT NULL CHECK (kind IN ('full','half','step','foster','kin')),
  contact_allowed  boolean NOT NULL DEFAULT true,
  travels_together boolean NOT NULL DEFAULT true,
  PRIMARY KEY (child_a, child_b),
  CONSTRAINT canonical_order CHECK (child_a < child_b)
);

-- ---------------------------------------------------------------- temporal --

-- Timezone is a TIMELINE, not a column.  Overlaps are a data bug.
CREATE TABLE child_tz_interval (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id   uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  tz         text NOT NULL,
  valid      tstzrange NOT NULL,
  source     text NOT NULL CHECK (source IN ('custody','manual','device','travel')),
  confidence smallint NOT NULL DEFAULT 100,
  EXCLUDE USING gist (child_id WITH =, valid WITH &&)
);

-- starts_local / ends_local are WALL CLOCK `time`, deliberately.
-- Bedtime is 8:30 PM regardless of daylight saving. That is the entire point.
CREATE TABLE day_part (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  household_id uuid REFERENCES household(id),
  kind         text NOT NULL CHECK (kind IN
                 ('wake','before_school','school','after_school','activity',
                  'dinner','wind_down','bedtime','asleep','free')),
  starts_local time NOT NULL,
  ends_local   time NOT NULL,
  days_of_week smallint[] NOT NULL,
  reachable    boolean NOT NULL,
  effective    daterange NOT NULL
);
CREATE INDEX ON day_part (child_id, kind);

-- ----------------------------------------------------------- media/archive --

CREATE TABLE media_artifact (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  author_id     uuid REFERENCES app_user(id),
  kind          text NOT NULL CHECK (kind IN
                  ('video_msg','voice_note','drawing','homework','photo','call_clip')),
  storage_key   text NOT NULL,
  duration_ms   integer,
  caption_key   text,
  captured_at   timestamptz NOT NULL,
  captured_tz   text NOT NULL,
  era_tag       text,
  preserved     boolean NOT NULL DEFAULT false,
  preserved_by  uuid REFERENCES app_user(id),
  preserved_at  timestamptz,
  expires_at    timestamptz,
  -- The archive design in one line: an artifact is either on a retention clock
  -- or explicitly preserved by a named guardian. "Indefinite by accident" is
  -- unrepresentable.
  CONSTRAINT retention_or_preserved
    CHECK (preserved = true OR expires_at IS NOT NULL),
  CONSTRAINT preservation_is_attributed
    CHECK (preserved = false OR preserved_by IS NOT NULL)
);
CREATE INDEX ON media_artifact (child_id, captured_at DESC);
CREATE INDEX ON media_artifact (expires_at) WHERE preserved = false;

-- ------------------------------------------------------------ async engine --

CREATE TYPE delivery_policy AS ENUM (
  'immediate','at_instant','at_daypart','on_local_date','when_reachable','on_event'
);

CREATE TABLE intent_batch (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  sender_id    uuid NOT NULL REFERENCES app_user(id),
  label        text NOT NULL,
  reason       text CHECK (reason IN
                 ('deployment','medical','treatment','travel','custody_gap','other')),
  cadence      text NOT NULL CHECK (cadence IN ('daily','weekdays','weekly','custom')),
  daypart      text NOT NULL DEFAULT 'bedtime',
  starts_local date NOT NULL,
  ends_local   date NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT window_ordered CHECK (ends_local >= starts_local)
);

CREATE TABLE delivery_intent (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  sender_id         uuid NOT NULL REFERENCES app_user(id),
  payload_kind      text NOT NULL,
  payload_ref       uuid NOT NULL,
  policy            delivery_policy NOT NULL,

  target_instant    timestamptz,
  target_daypart    text,
  target_local_date date,
  target_event_id   uuid,

  batch_id          uuid REFERENCES intent_batch(id) ON DELETE CASCADE,
  batch_seq         integer,

  scheduled_at      timestamptz,        -- MATERIALIZED CACHE. Never trusted.
  materialized_tz   text,
  materialized_at   timestamptz,
  state             text NOT NULL DEFAULT 'pending' CHECK (state IN
                      ('pending','ready','delivered','opened','expired','revoked')),
  expires_at        timestamptz NOT NULL,   -- COPPA §10.1. Non-nullable on purpose.
  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Each policy requires its own target. Catches a whole class of bug at write
  -- time rather than at 3 a.m. in the materializer.
  CONSTRAINT policy_has_target CHECK (
    (policy = 'at_instant'     AND target_instant    IS NOT NULL) OR
    (policy = 'at_daypart'     AND target_daypart    IS NOT NULL) OR
    (policy = 'on_local_date'  AND target_local_date IS NOT NULL) OR
    (policy = 'on_event'       AND target_event_id   IS NOT NULL) OR
    (policy IN ('immediate','when_reachable'))
  )
);
CREATE INDEX ON delivery_intent (scheduled_at) WHERE state = 'pending';
CREATE INDEX ON delivery_intent (child_id, state);
CREATE INDEX ON delivery_intent (batch_id) WHERE batch_id IS NOT NULL;

-- --------------------------------------------------------------- agency ----

-- §5.12 / P7.  The owning child is the ONLY readable role. There is
-- deliberately no guardian policy, no escalation policy, no admin policy.
-- Adding one requires a CHANGELOG entry naming the requester. §0.
CREATE TABLE child_journal_entry (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id   uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  body       text,
  media_ref  uuid REFERENCES media_artifact(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE child_journal_entry ENABLE ROW LEVEL SECURITY;

-- CRITICAL. `ENABLE` alone is NOT enough: in Postgres the table OWNER bypasses
-- row-level security by default, and applications overwhelmingly connect as the
-- owner of their own schema. Without FORCE, this policy is decorative and P7 is
-- unenforced in the most common deployment. Verified by db/test/0001.
--
-- FORCE does not apply to SUPERUSERS or roles with BYPASSRLS. The application
-- role must therefore never be either. See db/DEPLOYMENT.md.
ALTER TABLE child_journal_entry FORCE ROW LEVEL SECURITY;

CREATE POLICY journal_owner_only ON child_journal_entry
  FOR ALL USING (
    current_setting('app.role', true) = 'child'
    AND child_id = current_setting('app.child_id', true)::uuid
  );

CREATE TABLE child_ping (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id   uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  to_user    uuid NOT NULL REFERENCES app_user(id),
  local_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON child_ping (child_id, to_user, local_date);

-- ------------------------------------------------------------ succession ---

-- §5.16  Recorded by the parent, about themselves, while living.
-- No other actor may create, alter, or override this row.
CREATE TABLE succession_directive (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  child_id        uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  banked_on_death text NOT NULL CHECK (banked_on_death IN
                    ('continue','stop','deliver_all')),
  successor_id    uuid REFERENCES app_user(id),
  message         text,
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, child_id)
);

COMMIT;
