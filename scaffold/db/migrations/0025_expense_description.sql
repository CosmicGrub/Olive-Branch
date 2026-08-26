-- ============================================================================
--  OLIVE BRANCH — expense.description
--
--  Real, disclosed gap found wiring the first real backend for expenses
--  (server/routes.mjs's GET/POST .../expenses, packages/db/src/pool.ts's
--  proposeExpense()/expensesFor()): expense (0006_court_tier.sql) has never
--  had a free-text field at all — id, child_id, paid_by, amount_cents,
--  category, incurred_on, receipt_key, split_rule, status, created_at, and
--  nothing a guardian reading the ledger could use to tell "what was this
--  $89 medical expense actually FOR." expenses_screen.dart's own demo
--  fixtures (`LedgerLine.description`, `InboxItem.summary`) have always
--  carried one — "Orthodontist co-pay, Ivy's adjustment visit", "Winter
--  coat" — this column is what lets the real backend carry the same thing,
--  not a design change to the client.
--
--  NOT NULL, no default, no backfill needed: this table has had real RLS
--  since it was first migrated but, per this same pass's own audit finding,
--  literally never had a production writer before now — there are no
--  existing rows anywhere to break.
-- ============================================================================

BEGIN;

ALTER TABLE expense
  ADD COLUMN description text NOT NULL;

COMMIT;
