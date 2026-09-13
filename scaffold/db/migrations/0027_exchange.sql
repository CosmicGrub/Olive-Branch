-- ============================================================================
--  OLIVE BRANCH — exchange_bag_item, exchange_running_late_log,
--  exchange_arrival_event
--
--  Real backend for the FOURTH coordination-layer feature closed this pass
--  (handover log, expenses, medications/emergency-card came first —
--  v0.49.52-0.49.54). Found by this project's own coordination-layer audit
--  (MASTERFILE §20.2b): exchange_screen.dart has real, already-tested pure
--  logic ported from packages/care/src/care.ts (manifestOrder/unpacked,
--  recordArrival/auditArrival, §9.7.1-9.7.3) but no table, route, or pool.ts
--  function anywhere — the screen has never made a network call.
--
--  Scope, disclosed: this migration backs ONLY the bag manifest, running-late
--  log, and arrival event sections. exchange_screen.dart's Handoff/Coming-up
--  sections stay on their existing demo `_demoOrder` data — making those live
--  would mean porting packages/custody/src/schedule.ts's full timezone-aware
--  `exchanges()` (cross-zone instant math), a separate, larger task from the
--  bag/late/arrival domain actually scoped here. The read-only custody-order
--  facts those sections WOULD need already exist, real, at
--  GET /v1/children/:childId/custody-order (server/routes.mjs) — nothing new
--  is added here to support them.
--
--  P3 (§9.7.2) enforced structurally, not just by convention:
--  exchange_arrival_event has no latitude/longitude/coords/address column —
--  there is physically nowhere to put a coordinate. The route layer
--  (server/routes.mjs) never reads a location-shaped field off the request
--  body either, matching packages/care/src/care.ts's LOCATION_KEYS /
--  auditArrival and exchange_screen.dart's own auditArrivalPayload — three
--  independent guards on three separate layers (client, route, schema) for
--  the same rule.
--
--  RLS: `..._no_child` throughout, the identical `current_role_name() IS
--  DISTINCT FROM 'child'` shape every other guardian-only coordination table
--  this migration series uses (expense_no_child, medication_no_child, etc.).
-- ============================================================================

BEGIN;

CREATE TABLE exchange_bag_item (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id   uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  label      text NOT NULL,
  essential  boolean NOT NULL DEFAULT false,
  sent       boolean NOT NULL DEFAULT false,
  returned   boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON exchange_bag_item (child_id);

ALTER TABLE exchange_bag_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchange_bag_item FORCE  ROW LEVEL SECURITY;
CREATE POLICY exchange_bag_item_no_child ON exchange_bag_item
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

-- §9.7.3 — append-only by design. No UPDATE/DELETE route is ever registered
-- for this table (exchange_screen.dart's own file header: "there is no
-- _editLateEntry and no _deleteLateEntry anywhere in this file").
CREATE TABLE exchange_running_late_log (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id           uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  eta_minutes        integer NOT NULL CHECK (eta_minutes > 0),
  reported_by_user_id uuid NOT NULL REFERENCES app_user(id),
  logged_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON exchange_running_late_log (child_id, logged_at DESC);

ALTER TABLE exchange_running_late_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchange_running_late_log FORCE  ROW LEVEL SECURITY;
CREATE POLICY exchange_running_late_log_no_child ON exchange_running_late_log
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

-- An EVENT, never a place (§9.7.2, P3) — see this file's own header. `
-- scheduled_at` is never client-supplied: the route resolves it from the
-- child's real active custody_order (exchange_time/order_tz,
-- activeCustodyOrderFor() in packages/db/src/pool.ts), the same "never trust
-- a client-supplied record-keeping time" discipline medication_dose's own
-- local_date column already established. `exchange_id` is this row's own id
-- — there is no separate "scheduled exchange" entity in this schema (that
-- would be part of the Handoff/Coming-up scope disclosed above, not this
-- table); each arrival log is its own, self-contained event.
CREATE TABLE exchange_arrival_event (
  id                 uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id           uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  scheduled_at       timestamptz NOT NULL,
  arrived_at         timestamptz NOT NULL,
  delay_minutes      integer NOT NULL CHECK (delay_minutes >= 0),
  reported_by_user_id uuid NOT NULL REFERENCES app_user(id),
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON exchange_arrival_event (child_id, created_at DESC);

ALTER TABLE exchange_arrival_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE exchange_arrival_event FORCE  ROW LEVEL SECURITY;
CREATE POLICY exchange_arrival_event_no_child ON exchange_arrival_event
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

COMMIT;
