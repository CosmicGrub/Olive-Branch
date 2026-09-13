-- ============================================================================
--  OLIVE BRANCH — a child can be the SENDER of an async video message
--  MASTERFILE §9.5, §9.8.1. Closes a real, already-confirmed gap named by
--  this pass's own audit finding "child_async_video_sender_identity schema
--  change" and already disclosed (not hidden) in three places before this
--  migration existed:
--    - client/lib/receipt_screen.dart's header, point 3
--    - server/routes.mjs's POST /v1/children/:childId/messages handler
--    - packages/messaging/test/pipeline.test.mjs's M2 suite
--
--  THE GAP, confirmed by reading the schema rather than assumed: 0001_phase0_
--  init.sql built `media_artifact.author_id` and `delivery_intent.sender_id`
--  as `uuid REFERENCES app_user(id)` — `sender_id` additionally `NOT NULL`.
--  Both columns can therefore only ever name a GUARDIAN (or other app_user-
--  backed adult). A child has no `app_user` row at all — packages/auth/src/
--  auth.ts's VerifiedPrincipal carries `userId: string | null`, null for
--  every `roleName: 'child'` session — so there was no id a child-originated
--  capture could ever legally put in either column. captureMessage() (this
--  pass leaves that half-fixed function's OWN authorization branch alone)
--  reached `can('message', [], childId, now, 'child')` with structurally
--  empty edges (a child never holds a guardianship edge to herself) and
--  honestly refused every child-originated send with `not_authorized` — a
--  real rejection, not a silent bypass, but the schema gave it no other
--  option: there was no representation of "sent by the child herself" to
--  authorize INTO.
--
--  THE FIX is representational, not just a permission flip: two new,
--  NULLABLE, child-referencing columns, so a row can name its sender as
--  EITHER an app_user (unchanged, existing behaviour) OR a child (new),
--  never neither and never both — a CHECK constraint each, not an
--  application-layer convention that the next writer could accidentally
--  skip. `sender_id` on delivery_intent loses its NOT NULL because the XOR
--  CHECK below is what now guarantees "a sender exists", not the column's
--  own nullability.
--
--  SELF-AUTHORSHIP ONLY, enforced in the schema, not just in application
--  code — this is the second half of the audit finding: "a design that
--  can't distinguish which child sent a video when multiple children share
--  a device." `author_child_id`/`sender_child_id` must equal the row's own
--  `child_id`. A child session can only ever write rows scoped to her own
--  `childId` (packages/api/src/api.ts's A3 — childId from the verified
--  session/path, never the body), so in practice this CHECK is redundant
--  with that application-layer guarantee on every real request — it is kept
--  anyway, as a second, independent lock: if a future handler ever passed
--  the wrong child's id through (a copy-paste bug, a batch job, a kiosk
--  session confused about which sibling is in front of it), the database
--  itself refuses to attribute one child's video to a different child's
--  row, rather than silently accepting whatever the caller claims. Same
--  "second lock, not the only one" posture packages/family-graph/src/
--  authorize.ts's own header already states for `can()` relative to RLS.
--
--  NOT done here, and deliberately not: no guardian-side "read what my
--  child sent me" route or view. This migration closes the SENDER identity
--  gap only — receipt_screen.dart's own header (point 2) already discloses
--  that no live caller wires "Send one back" to a real server yet, and
--  routes.mjs's inbox is (and remains) child-received-only. Building the
--  reverse-direction inbox is real, separate follow-up work, not silently
--  implied by this migration.
-- ============================================================================

BEGIN;

-- ------------------------------------------------------------ media_artifact
ALTER TABLE media_artifact
  ADD COLUMN author_child_id uuid REFERENCES child(id) ON DELETE CASCADE;

ALTER TABLE media_artifact
  ADD CONSTRAINT author_is_one_kind
    CHECK (author_id IS NULL OR author_child_id IS NULL);

-- A child may only ever be recorded as the author of her OWN artifact — see
-- this migration's own header on why this is enforced twice (app layer +
-- here), not once.
ALTER TABLE media_artifact
  ADD CONSTRAINT child_author_is_self
    CHECK (author_child_id IS NULL OR author_child_id = child_id);

-- ----------------------------------------------------------- delivery_intent
ALTER TABLE delivery_intent
  ALTER COLUMN sender_id DROP NOT NULL;

ALTER TABLE delivery_intent
  ADD COLUMN sender_child_id uuid REFERENCES child(id) ON DELETE CASCADE;

-- Exactly one sender, always — the XOR this column's own former NOT NULL
-- used to guarantee alone, now guaranteed across both columns together.
ALTER TABLE delivery_intent
  ADD CONSTRAINT sender_is_exactly_one_kind
    CHECK ((sender_id IS NOT NULL) <> (sender_child_id IS NOT NULL));

ALTER TABLE delivery_intent
  ADD CONSTRAINT child_sender_is_self
    CHECK (sender_child_id IS NULL OR sender_child_id = child_id);

-- intent_batch is DELIBERATELY untouched. Message banking (§9.8.1, the
-- "record N nights ahead" batch flow) is a guardian-only capability — a
-- single child reply ("Send one back") never passes `opts.newBatch`
-- (packages/db/src/pool.ts's persistCapturedMessage()), so intent_batch.
-- sender_id staying `NOT NULL REFERENCES app_user(id)` is correct, not an
-- oversight this migration forgot.

-- health_check is intentionally NOT re-declared here. Neither media_artifact
-- nor delivery_intent carries row-level security (confirmed: neither name
-- appears anywhere in the `rls_unforced` list any prior migration built, and
-- packages/db/src/pool.ts's own persistCapturedMessage() doc comment already
-- names that as a real, disclosed, DEFERRED gap — "its own migration and its
-- own review, not a side effect of adding one new write path"). This
-- migration does not close that gap and does not pretend to; adding an RLS
-- policy here would be exactly the undeclared, unaudited widening
-- child_theme_preference's own header (0017) warns against. The two new
-- CHECK constraints above are enforced for every role, RLS or not — they are
-- not a substitute for that separate audit, but they are real, unconditional
-- protection against the specific "wrong child attributed" failure mode this
-- pass's audit finding named.

COMMENT ON COLUMN media_artifact.author_child_id IS
  'Set when this artifact was recorded by the CHILD herself (an async video '
  'reply), never together with author_id. NULL author_id AND NULL '
  'author_child_id still means "unknown/system", exactly as before this '
  'migration — this column narrows an existing ambiguity, it does not '
  'remove it.';

COMMENT ON COLUMN delivery_intent.sender_child_id IS
  'Set when this intent was authored by the CHILD herself. Exactly one of '
  'sender_id/sender_child_id is non-null on every row (sender_is_exactly_'
  'one_kind) — unlike media_artifact.author_id, a delivery_intent has never '
  'been allowed an unattributed sender, and still is not.';

COMMIT;
