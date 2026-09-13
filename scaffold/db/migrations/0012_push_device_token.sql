-- ============================================================================
--  OLIVE BRANCH — push device tokens
--  MASTERFILE §11 (push/call transport). Feeds packages/transport/src/fcm.ts,
--  apns.ts and notify.ts's notifyDevices() — packages/transport/src/push.ts's
--  buildPush()/sendGuard() already exist and are untouched by this migration.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- OWNER COLUMN — decided by reading packages/db/src/pool.ts's withSession()
-- and packages/auth/src/auth.ts's VerifiedPrincipal first, as instructed.
--
-- A session's identity is EITHER a child (roleName='child', childId set,
-- userId NULL) OR an adult/system actor (userId set, childId NULL) — never
-- both (withSession() itself throws otherwise). Push targets are not only
-- guardians: push.ts's own PushKind list includes call_incoming,
-- message_ready and turn_ready, all of which ring/notify on the CHILD's own
-- tablet, not only a guardian's phone (§11 — "a call from Dad arriving as a
-- silent notification is a broken product" is about the child's device
-- receiving the call). So device_token needs to be registerable by either
-- principal shape, and needs an owner column matching whichever registered
-- it — exactly the "exactly one subject" shape pin_credential (0004) already
-- uses for the same underlying reason (a child_unlock PIN belongs to a
-- child; a guardian_escalation PIN belongs to a user; never both on one row).
CREATE TABLE device_token (
  id             uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_user_id  uuid REFERENCES app_user(id) ON DELETE CASCADE,
  owner_child_id uuid REFERENCES child(id)    ON DELETE CASCADE,
  platform       text NOT NULL CHECK (platform IN ('android','ios')),
  token          text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  last_seen_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT device_token_has_exactly_one_owner CHECK (
    (owner_user_id IS NOT NULL AND owner_child_id IS NULL) OR
    (owner_user_id IS NULL AND owner_child_id IS NOT NULL)
  )
);

-- ---------------------------------------------------------------------------
-- DEDUPE — decided and documented here, as instructed, because the answer is
-- not obvious and the wrong one silently accumulates dead rows forever.
--
-- registerDeviceToken(pool, principal, platform, token) — packages/db/src/
-- pool.ts — takes no client-generated device id, only the token itself. That
-- rules out "dedupe by device id": there is nothing here to correlate "this
-- is the same physical device as row X" ACROSS a token rotation, because by
-- definition the new token is a value the server has never seen before and
-- carries no reference back to the old one.
--
-- So dedupe is BY TOKEN, globally unique across every owner:
--   - The common case (an app re-registering on every launch, same token) is
--     a plain UPSERT on this unique index — one row, last_seen_at bumped.
--   - Re-registration under a DIFFERENT owner (account deleted and a new one
--     signed in on the same physical device, or a shared family tablet
--     switching hands) re-attributes the row rather than erroring — the
--     token is what FCM/APNs hands back for THIS install right now, so it is
--     always correct to trust the most recent registration over a stale one.
--   - A genuine OS-level token ROTATION registers as a brand-new row (new
--     token value, nothing to UPSERT against) — the OLD row is not
--     collapsed away at registration time. It is reaped reactively:
--     notifyDevices() (packages/transport/src/notify.ts) sends to every row
--     for that owner, and FCM's UNREGISTERED / APNs' Unregistered /
--     BadDeviceToken response on the stale token is exactly the definitive
--     "this device is gone" signal that removeDeviceTokenSystem() acts on.
--     This is the same pattern most production FCM/APNs integrations use in
--     practice (Google's own guidance: prune on send failure, not on a
--     schedule) — a deliberate choice given the literal 4-arg signature,
--     not an oversight. Documented here so a future contributor doesn't
--     "fix" the missing device-id parameter without reading this reasoning.
CREATE UNIQUE INDEX device_token_token_key ON device_token (token);

CREATE INDEX ON device_token (owner_user_id)  WHERE owner_user_id  IS NOT NULL;
CREATE INDEX ON device_token (owner_child_id) WHERE owner_child_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- RLS. ENABLE + FORCE, deny-by-default — db/DEPLOYMENT.md's three bypass
-- paths all closed the same way every other table in this file's family
-- closes them.
--
-- REVISED FROM A FIRST DRAFT THAT SHIPPED WITH NO SELECT POLICY FOR CHILD/
-- GUARDIAN AT ALL — found broken by testing against a live Postgres, not by
-- review, so the wrong reasoning is left visible below (struck through in
-- prose, not deleted) rather than quietly replaced, because the mistake is
-- the useful part for the next person who reaches for the same shortcut.
--
-- THE WRONG ASSUMPTION: that UPDATE/DELETE policies' own USING clauses are
-- sufficient to let a principal locate and act on their own rows, so SELECT
-- could be omitted entirely for child/guardian ("no read policy needs to
-- exist for anyone other than system," per the task) without cost beyond
-- "you cannot list these."
--
-- WHAT'S ACTUALLY TRUE, verified empirically here: Postgres's row-security
-- model does NOT let an UPDATE or DELETE policy's USING clause substitute
-- for SELECT visibility. To locate which existing rows a WHERE clause
-- matches, UPDATE and DELETE both ALSO require the row to pass the table's
-- SELECT policies, IN ADDITION to their own command-specific policy — with
-- ZERO SELECT policies present, that intersection is always empty, so
-- UPDATE/DELETE match NOTHING, ever, regardless of what their own USING
-- clause says. (INSERT is different again: a fresh INSERT with no
-- RETURNING doesn't need to locate an existing row, so it works with zero
-- SELECT policies — but `RETURNING` on that INSERT, and the UPDATE half of
-- `ON CONFLICT DO UPDATE`, hit the exact same wall.)
--
-- Proven with a throwaway probe table before touching this file: a plain
-- `UPDATE ... WHERE owner_user_id = current_actor()` against a row that
-- genuinely belongs to the caller matched ZERO rows with no SELECT policy
-- present, and matched the row correctly the moment a permissive SELECT
-- policy was added — same USING clause, same GUCs, only the presence of a
-- SELECT policy changed. registerDeviceToken()'s re-registration path
-- (INSERT ... ON CONFLICT DO UPDATE) and unregisterDeviceToken()'s DELETE
-- were both silently no-op'ing against real, matching rows before this was
-- caught — device_token_delete_own's/_update_own's USING clauses were
-- never the problem; the missing SELECT policy was.
--
-- THE FIX: a SELF-SCOPED SELECT policy, own rows only — device_token_select_
-- own below. This does NOT reopen the thing the task's instruction actually
-- cared about: nobody can list ANOTHER principal's device tokens, which is
-- the real leak surface this RLS exists to close. "A principal can see
-- their own rows" is not that leak; it is, if anything, closer to what a
-- real "manage your notification devices" settings screen would eventually
-- want anyway.
--
-- Kept COMMAND-SCOPED (not collapsed into one FOR ALL) because the INSERT
-- policy's WITH CHECK still needs its own "exactly one owner column set,
-- matching the caller" shape distinct from a bare row-ownership USING
-- clause — same reasoning 0007's custody_order_child_own/not_child_scope
-- split already established for "a single shape doesn't fit every command
-- here," just landing on five policies instead of two.
ALTER TABLE device_token ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_token FORCE  ROW LEVEL SECURITY;

CREATE POLICY device_token_select_own ON device_token
  FOR SELECT USING (
    (current_role_name() = 'child' AND owner_child_id = current_child())
    OR
    (current_role_name() IS DISTINCT FROM 'child'
       AND current_role_name() IS DISTINCT FROM 'system'
       AND owner_user_id = current_actor())
  );

CREATE POLICY device_token_insert_own ON device_token
  FOR INSERT WITH CHECK (
    (current_role_name() = 'child'
       AND current_child() IS NOT NULL
       AND owner_child_id = current_child()
       AND owner_user_id IS NULL)
    OR
    (current_role_name() IS DISTINCT FROM 'child'
       AND current_role_name() IS DISTINCT FROM 'system'
       AND current_actor() IS NOT NULL
       AND owner_user_id = current_actor()
       AND owner_child_id IS NULL)
  );

CREATE POLICY device_token_update_own ON device_token
  FOR UPDATE USING (
    (current_role_name() = 'child' AND owner_child_id = current_child())
    OR
    (current_role_name() IS DISTINCT FROM 'child'
       AND current_role_name() IS DISTINCT FROM 'system'
       AND owner_user_id = current_actor())
  ) WITH CHECK (
    (current_role_name() = 'child'
       AND owner_child_id = current_child() AND owner_user_id IS NULL)
    OR
    (current_role_name() IS DISTINCT FROM 'child'
       AND current_role_name() IS DISTINCT FROM 'system'
       AND owner_user_id = current_actor() AND owner_child_id IS NULL)
  );

CREATE POLICY device_token_delete_own ON device_token
  FOR DELETE USING (
    (current_role_name() = 'child' AND owner_child_id = current_child())
    OR
    (current_role_name() IS DISTINCT FROM 'child'
       AND current_role_name() IS DISTINCT FROM 'system'
       AND owner_user_id = current_actor())
  );

-- system is the sender (packages/transport/src/notify.ts's notifyDevices(),
-- run from a background/server context under withSystemSession) — never a
-- request-scoped client role, never exposed over the API. This SELECT
-- policy is permissive and OR's with device_token_select_own above: system
-- sees every row (deviceTokensFor() looks up ANY user's/child's devices by
-- design — it's the sender), while child/guardian still only ever see their
-- own via the other policy. A second policy grants system DELETE too, but
-- ONLY for reaping a token FCM/APNs has just told us is dead
-- (removeDeviceTokenSystem in pool.ts) — system is deliberately not granted
-- INSERT/UPDATE, since it never registers a token on anyone's behalf.
CREATE POLICY device_token_system_read ON device_token
  FOR SELECT USING (current_role_name() = 'system');

CREATE POLICY device_token_system_prune ON device_token
  FOR DELETE USING (current_role_name() = 'system');

COMMIT;
