-- ============================================================================
--  OLIVE BRANCH — real auth credentials: guardian PIN, WebAuthn, ceremony
--  challenges. MASTERFILE §7.1, §8.1, §8.3. Closes the release blocker: the
--  client (client/lib/main.dart's `_demoGuardianPin = '1273'`) accepted one
--  hardcoded, unauthenticated code with nothing behind it. auth.ts already had
--  real, unit-tested crypto (hashPin/verifyPin, verifyAssertion) with no table
--  to persist against — this migration is that table.
--
--  SUPERSEDES 0004_auth_and_reaper.sql's `pin_credential`, `webauthn_credential`
--  and `webauthn_challenge`, rather than adding new tables beside them. Those
--  three were scaffolded speculatively ahead of a real caller and never wired
--  to a single line of application code — verified by grep across every .ts/
--  .mjs file in this repository before writing this migration: zero matches
--  outside the migrations themselves and the `health_check` monitoring view.
--  Their shape also does not fit the ceremony this pass actually implements:
--    - 0004's pin_credential is `kind`-discriminated (child_unlock vs
--      guardian_escalation) and keyed by EITHER child_id OR user_id. The real
--      kiosk ceremony (server/routes.mjs's kiosk-pin/verify) has no per-child
--      PIN at all — a PIN belongs to a GUARDIAN, and a child's kiosk checks
--      the entered code against every live guardian of that child
--      (packages/db/src/pool.ts's guardiansOfChild()). Bending the kind/
--      child_id/user_id shape to fit that would be real complexity serving no
--      one; a single user_id-keyed table is what the actual caller needs.
--    - 0004's webauthn_challenge is a bare `challenge PRIMARY KEY`, global
--      across every purpose. The real flow needs `purpose` ('register' vs
--      'login') so a captured registration challenge cannot be replayed
--      against the login endpoint — auth_challenge below carries that.
--  Dropping and recreating under the SAME names (rather than leaving the old
--  tables dead beside new, differently-named ones) is deliberate: two
--  never-reconciled "pin_credential"-shaped tables in one schema is exactly
--  the kind of silent drift this codebase's own CHANGELOG conventions exist
--  to prevent. Nothing has ever written a row to any of the three (dead
--  code, confirmed above), so there is no data to migrate.
-- ============================================================================

BEGIN;

DROP TABLE IF EXISTS webauthn_challenge;
DROP TABLE IF EXISTS webauthn_credential;
DROP TABLE IF EXISTS pin_credential;

-- ------------------------------------------------------------------- PINs ----
-- One PIN per GUARDIAN (app_user), not per child. The kiosk ceremony checks an
-- entered code against every live guardian of the child in front of the
-- kiosk (packages/db/src/pool.ts's guardiansOfChild() + pinCredentialFor()),
-- so the credential's natural key is the guardian, not the child.
CREATE TABLE pin_credential (
  user_id        uuid PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  -- Full parameterised scrypt string (auth.ts's hashPin output: 'scrypt$N$r$p$
  -- salt$key'), so the cost can be raised later without invalidating existing
  -- hashes — same reasoning 0004's original column carried, kept verbatim.
  pin_hash       text NOT NULL,
  failed_attempts int NOT NULL DEFAULT 0,
  locked_until   timestamptz,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pin_hash_is_parameterised CHECK (pin_hash LIKE 'scrypt$%')
);

-- PIN material must never be readable by a child session, even its own
-- guardian's hash — a child who defeated the kiosk lock must not be able to
-- read the very secret that would let her defeat it again. FORCE is not
-- optional: without it the table OWNER (who every migration in this file
-- runs as) bypasses every policy below, and the guardian-only claim becomes
-- decorative (db/DEPLOYMENT.md's own point #1).
ALTER TABLE pin_credential ENABLE ROW LEVEL SECURITY;
ALTER TABLE pin_credential FORCE  ROW LEVEL SECURITY;

-- A child role gets ZERO policies here — not a policy a child could satisfy,
-- no policy at all. Combined with FORCE, Postgres denies every command from
-- a child-role session by default; there is no "no policy matched, so allow"
-- fallback in row-level security. (Verified for real, not assumed: see
-- packages/db/test/auth_credentials.test.mjs's RLS section, which asserts a
-- child session gets zero rows on SELECT and a query ERROR — not just an
-- empty result — on INSERT/UPDATE, which is what FORCE with no matching
-- policy actually produces.)
--
-- A guardian may touch only HER OWN row. `current_actor() IS NOT NULL` guards
-- the case current_actor() and user_id are both NULL, which would otherwise
-- vacuously satisfy `user_id = current_actor()` under three-valued NULL
-- logic... except NULL = NULL is itself NULL (not true) in SQL, so that
-- specific case cannot actually happen — the redundancy is kept anyway
-- because relying on the reader to re-derive that from first principles is
-- worse than one extra, obviously-true clause.
CREATE POLICY pin_credential_owner_only ON pin_credential
  FOR ALL USING (
    current_role_name() IS DISTINCT FROM 'child'
    AND current_actor() IS NOT NULL
    AND user_id = current_actor()
  );

-- ------------------------------------------------------------------ WebAuthn --
CREATE TABLE webauthn_credential (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  credential_id  text UNIQUE NOT NULL,     -- base64url, per auth.ts's Credential
  public_key_pem text NOT NULL,            -- ES256 SPKI, extracted by attestation.ts
  sign_count     bigint NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON webauthn_credential (user_id);

ALTER TABLE webauthn_credential ENABLE ROW LEVEL SECURITY;
ALTER TABLE webauthn_credential FORCE  ROW LEVEL SECURITY;

-- Same owner-only shape as pin_credential: a guardian manages her own
-- passkeys, a child gets nothing (no policy exists for the child role).
CREATE POLICY webauthn_credential_owner_only ON webauthn_credential
  FOR ALL USING (
    current_role_name() IS DISTINCT FROM 'child'
    AND current_actor() IS NOT NULL
    AND user_id = current_actor()
  );

-- Second, narrower policy — NOT a widening of who can read a passkey, a
-- carve-out for the one caller that structurally CANNOT be scoped to "her own
-- row" because whose row it is is the very question being answered. WebAuthn
-- LOGIN (server/index.mjs's /v1/auth/webauthn/login/verify, before this
-- README's route, before any session token exists) receives a bare
-- credentialId from the client and must find out which guardian it belongs
-- to — that is identity resolution, the same class of "the API needs this
-- before/independent of can()" already established for edgesFor() and
-- guardiansOfChild() in this file's own header comments, extended here to a
-- table that (unlike guardianship) actually carries RLS. The system role has
-- no other route into this table: nothing in packages/db/src/pool.ts ever
-- opens a `system`-scoped session against webauthn_credential except
-- webauthnCredentialById() (read, to resolve identity) and
-- updateWebauthnSignCount() (write, to persist the replay counter
-- immediately after auth.ts's verifyAssertion() has independently proven
-- possession of the matching private key) — both narrow, reviewed, named
-- functions, not a general-purpose bypass.
CREATE POLICY webauthn_credential_system_lookup ON webauthn_credential
  FOR ALL USING (current_role_name() = 'system');

-- --------------------------------------------------------------- challenges --
-- One table for BOTH ceremonies (register/login), disambiguated by `purpose` —
-- 0004's webauthn_challenge had no such column, so a challenge minted for
-- registration could be replayed at the login endpoint and vice versa; this
-- fixes that rather than reproducing it under a new name. Server-internal
-- bookkeeping only: no per-request principal ever has a legitimate reason to
-- read or write this table directly (contrast pin_credential/
-- webauthn_credential, which a guardian legitimately manages herself).
CREATE TABLE auth_challenge (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  challenge   text NOT NULL,
  purpose     text NOT NULL CHECK (purpose IN ('register','login')),
  issued_at   timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz
);
-- consumeChallenge()'s lookup filters on exactly these three columns.
CREATE INDEX ON auth_challenge (user_id, purpose, consumed_at);

ALTER TABLE auth_challenge ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_challenge FORCE  ROW LEVEL SECURITY;

-- System-only, full stop — not guardian-or-system, not child-or-system.
-- packages/db/src/pool.ts's createChallenge()/consumeChallenge() are the
-- ONLY code in this repository that ever opens a session against this table,
-- and both always run under withSystemSession(), by the same reasoning
-- 0004's original design intended for its own webauthn_challenge (server-
-- internal ceremony bookkeeping) but never encoded as an actual RLS policy —
-- that table had RLS enabled nowhere at all. This one does.
CREATE POLICY auth_challenge_system_only ON auth_challenge
  FOR ALL USING (current_role_name() = 'system');

-- ------------------------------------------------------------ observability --
-- Extend the same rls_unforced health check 0005/0006 already carry, so a
-- FORCE dropped from any of these three tables by a future edit is caught
-- the same way it would be for child_journal_entry/expense/message_log.
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
     AND c.relname IN ('child_journal_entry','pin_credential','expense',
                        'message_log','webauthn_credential','auth_challenge')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
