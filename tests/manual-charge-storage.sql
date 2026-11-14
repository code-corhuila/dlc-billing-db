\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF NOT has_table_privilege('billing_runtime','billing.manual_charges','INSERT')
 THEN RAISE EXCEPTION 'Manual charge insert unavailable'; END IF;
 IF has_table_privilege('billing_runtime','billing.manual_charges','UPDATE')
 OR has_table_privilege('billing_runtime','billing.manual_charges','DELETE')
 THEN RAISE EXCEPTION 'Manual charge audit can be rewritten'; END IF;
END $$;
ROLLBACK;
