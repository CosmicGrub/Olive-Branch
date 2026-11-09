-- ============================================================================
-- 0046  A certified export of a BROKEN message chain does not use up the one
--       free certified export per guardian per rolling 12 months.  (owner,
--       2026-11-08)
--
-- The export is still produced and still recorded (it is evidence that it was
-- taken, and what it said), but a guardian who received a bundle that reports
-- its own fault should not have spent their year's allowance on it.
-- export_record.chain_verified records whether the chain verified when the
-- export was taken; the allowance counts only verified certified exports.
-- Existing rows were all taken before the distinction: they stay counted.
-- ============================================================================
BEGIN;

ALTER TABLE export_record ADD COLUMN chain_verified boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION certified_exports_last_year(p_user uuid, p_child uuid)
RETURNS integer AS $$
  SELECT count(*)::int FROM export_record
   WHERE requested_by = p_user AND child_id = p_child
     AND kind = 'certified' AND chain_verified AND created_at > now() - interval '12 months';
$$ LANGUAGE sql STABLE;

COMMIT;
