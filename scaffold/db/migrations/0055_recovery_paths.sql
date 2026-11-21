-- ============================================================================
--  OLIVE BRANCH -- recovery paths: losing a phone without losing anything
--
--  0053 gave an operator a way to hand a person a one-time code. This adds the
--  two ways a family gets itself back WITHOUT the operator, and keeps both of
--  them from becoming a way in for someone else:
--
--    two or more grown-ups   the grown-up on the new phone proves who they are,
--                            ANOTHER grown-up of the family says yes, and then
--                            the family waits 48 hours with a notice on every
--                            phone. Anyone can stop it at any time.
--    one grown-up            a printed recovery sheet made at set-up (a key
--                            held on paper, never stored readable), a 72 hour
--                            wait with a notice on every phone, and, if the
--                            grown-up named one, a trusted helper's yes. The
--                            helper can do exactly one thing: answer "yes, that
--                            is them" or "no" to a recovery of the account that
--                            named them. Nothing else.
--
--  Recovery signs the new phone in as the SAME account (same app_user row, so
--  the same family, children and history; no second account is created and
--  nothing is moved, copied or orphaned) and signs the older phones out. It
--  never deletes a row.
--
--  Tables (all three: ENABLE + FORCE row level security, system-only, the same
--  shape as account_recovery_code in 0053 and signup_allowance in 0050; the
--  routes decide who may ask, the database lets no session read or write them):
--
--    recovery_sheet     the printed recovery key of an account (only its
--                       SHA-256 is stored). One live sheet per account.
--                       confirmed_at = the person typed it back from the paper.
--    recovery_helper    the ONE trusted helper an account may name: a hashed
--                       single-use invite, then a hashed long-lived helper key.
--    recovery_request   one attempt to get an account back on a new phone,
--                       with its waiting period, its yes votes and its end.
--
--  Wrong guesses are counted on the recovery request itself (five and that
--  request is over), never on the account's own PIN lockout, so a stranger's
--  guesses can end THEIR attempt but can never lock the real owner out of
--  their own phone.
-- ============================================================================

BEGIN;

CREATE TABLE recovery_sheet (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- lowercase hex SHA-256 of the normalised 120-bit key (nothing low-entropy to enumerate offline)
  key_hash      text NOT NULL UNIQUE CHECK (key_hash ~ '^[0-9a-f]{64}$'),
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- the person typed the key back from the paper: "you kept it"
  confirmed_at  timestamptz,
  last_checked_at timestamptz,
  -- replaced by a newer sheet, or spent by a recovery (a used key is never used twice)
  retired_at    timestamptz,
  retired_reason text CHECK (retired_reason IN ('replaced', 'used')),
  CONSTRAINT recovery_sheet_retired_has_reason CHECK ((retired_at IS NULL) = (retired_reason IS NULL))
);
CREATE UNIQUE INDEX recovery_sheet_one_live_idx ON recovery_sheet (user_id) WHERE retired_at IS NULL;

CREATE TABLE recovery_helper (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- what the grown-up calls them ("Aunt Sam"); never an email or a phone number
  label         text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40 AND label !~ '@'),
  invite_hash   text NOT NULL UNIQUE CHECK (invite_hash ~ '^[0-9a-f]{64}$'),
  invite_expires_at timestamptz NOT NULL,
  accepted_at   timestamptz,
  -- the helper's own long-lived key (SHA-256), set when they accept; it opens
  -- exactly the two helper routes and nothing else
  key_hash      text UNIQUE CHECK (key_hash IS NULL OR key_hash ~ '^[0-9a-f]{64}$'),
  created_at    timestamptz NOT NULL DEFAULT now(),
  revoked_at    timestamptz,
  CONSTRAINT recovery_helper_accepted_has_key CHECK ((accepted_at IS NULL) = (key_hash IS NULL)),
  CONSTRAINT recovery_helper_invite_short CHECK (invite_expires_at <= created_at + interval '14 days')
);
-- ONE helper per account at a time (naming another removes the first)
CREATE UNIQUE INDEX recovery_helper_one_live_idx ON recovery_helper (user_id) WHERE revoked_at IS NULL;

CREATE TABLE recovery_request (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- the account being brought back. The request can never name any other.
  user_id        uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  mode           text NOT NULL CHECK (mode IN ('second_parent', 'sole_parent')),
  -- second_parent: another grown-up of the family started it (that IS their yes);
  -- sole_parent: the printed recovery sheet started it.
  started_by_kind text NOT NULL CHECK (started_by_kind IN ('parent', 'sheet')),
  -- SHA-256 of the 100-bit code only the new phone holds
  secret_hash    text NOT NULL UNIQUE CHECK (secret_hash ~ '^[0-9a-f]{64}$'),
  device_label   text NOT NULL DEFAULT '' CHECK (char_length(device_label) <= 60),
  -- wrong PINs presented at the end; five and the request is over
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  created_at     timestamptz NOT NULL DEFAULT now(),
  expires_at     timestamptz NOT NULL,
  -- two or more grown-ups: who said yes (the grown-up who started it), and when
  approved_by    uuid REFERENCES app_user(id) ON DELETE SET NULL,
  approved_at    timestamptz,
  -- one grown-up: whether a helper was named when this started, and their yes
  helper_id      uuid REFERENCES recovery_helper(id) ON DELETE SET NULL,
  helper_required boolean NOT NULL DEFAULT false,
  helper_confirmed_at timestamptz,
  -- the earliest moment the new phone may finish. Never sooner than 24 hours after the start.
  ready_at       timestamptz NOT NULL,
  cancelled_at   timestamptz,
  cancelled_by_kind text CHECK (cancelled_by_kind IN
                   ('owner_phone', 'other_parent', 'helper', 'new_phone', 'too_many_wrong',
                    'sheet_replaced', 'replaced_by_recovery', 'expired')),
  cancelled_by_user uuid REFERENCES app_user(id) ON DELETE SET NULL,
  completed_at   timestamptz,
  completed_device_id uuid REFERENCES paired_device(id) ON DELETE SET NULL,
  proof_used     text CHECK (proof_used IN ('pin', 'sheet', 'sheet_at_start')),
  CONSTRAINT recovery_request_expiry_after_creation CHECK (expires_at > created_at),
  CONSTRAINT recovery_request_short_lived CHECK (expires_at <= created_at + interval '14 days'),
  CONSTRAINT recovery_request_not_both CHECK (NOT (completed_at IS NOT NULL AND cancelled_at IS NOT NULL)),
  CONSTRAINT recovery_request_cancel_has_kind CHECK ((cancelled_at IS NULL) = (cancelled_by_kind IS NULL)),
  -- SD-2: never below 24 hours, whatever the code above does
  CONSTRAINT recovery_request_wait_floor CHECK (ready_at >= created_at + interval '24 hours'),
  CONSTRAINT recovery_request_ready_before_expiry CHECK (ready_at < expires_at),
  -- nobody approves their own recovery
  CONSTRAINT recovery_request_no_self_approval CHECK (approved_by IS NULL OR approved_by <> user_id),
  CONSTRAINT recovery_request_approval_pair CHECK ((approved_by IS NULL) = (approved_at IS NULL)),
  -- the two modes are two different shapes, never a mixture
  CONSTRAINT recovery_request_mode_shape CHECK (
    (mode = 'second_parent' AND started_by_kind = 'parent' AND approved_at IS NOT NULL AND helper_required = false) OR
    (mode = 'sole_parent'   AND started_by_kind = 'sheet'  AND approved_by IS NULL)),
  CONSTRAINT recovery_request_helper_confirm_needs_helper CHECK (helper_confirmed_at IS NULL OR helper_id IS NOT NULL),
  -- a finished request had to be ready (and, if it needed a helper, confirmed)
  CONSTRAINT recovery_request_done_was_ready CHECK (completed_at IS NULL OR completed_at >= ready_at),
  CONSTRAINT recovery_request_done_had_helper CHECK (
    completed_at IS NULL OR helper_required = false OR helper_confirmed_at IS NOT NULL),
  CONSTRAINT recovery_request_done_has_proof CHECK ((completed_at IS NULL) = (proof_used IS NULL))
);
CREATE INDEX recovery_request_user_open_idx ON recovery_request (user_id)
  WHERE completed_at IS NULL AND cancelled_at IS NULL;
CREATE INDEX recovery_request_user_created_idx ON recovery_request (user_id, created_at DESC);


ALTER TABLE recovery_sheet    ENABLE ROW LEVEL SECURITY;
ALTER TABLE recovery_sheet    FORCE  ROW LEVEL SECURITY;
ALTER TABLE recovery_helper   ENABLE ROW LEVEL SECURITY;
ALTER TABLE recovery_helper   FORCE  ROW LEVEL SECURITY;
ALTER TABLE recovery_request  ENABLE ROW LEVEL SECURITY;
ALTER TABLE recovery_request  FORCE  ROW LEVEL SECURITY;

CREATE POLICY recovery_sheet_system_all ON recovery_sheet
  FOR ALL USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');
CREATE POLICY recovery_helper_system_all ON recovery_helper
  FOR ALL USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');
CREATE POLICY recovery_request_system_all ON recovery_request
  FOR ALL USING (current_role_name() = 'system') WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE recovery_sheet IS
  'The printed recovery key of an account (0055): SHA-256 only, one live sheet per account, retired when replaced or used. System-only RLS.';
COMMENT ON TABLE recovery_helper IS
  'The ONE trusted helper an account may name (0055): hashed invite and hashed helper key. The helper can only answer a recovery of the account that named them. System-only RLS.';
COMMENT ON TABLE recovery_request IS
  'One attempt to get an account back on a new phone (0055): waiting period, yes votes, cancel, completion. Never deleted by the app. System-only RLS.';

-- ---------------------------------------------------- security_event -------
-- The kinds this adds are MERGED into whatever the constraint holds now, never swapped in as a fixed list: other
-- lanes extend the same constraint (0053 added account_recovered; the lost-phone lane adds its own), and a fixed
-- list here would silently remove theirs whichever of the migrations happened to run last.
DO $$
DECLARE
  def   text;
  kinds text[];
  add_kinds text[] := ARRAY[
    'recovery_sheet_made', 'recovery_helper_named', 'recovery_helper_removed',
    'recovery_started', 'recovery_approved', 'recovery_stopped'];
  k text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO def
    FROM pg_constraint c
   WHERE c.conname = 'security_event_kind_check' AND c.conrelid = 'security_event'::regclass;
  IF def IS NULL THEN
    RAISE EXCEPTION 'security_event_kind_check is missing; cannot add the recovery kinds';
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
