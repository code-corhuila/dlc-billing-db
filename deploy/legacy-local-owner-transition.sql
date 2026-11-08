-- Explicit DBA transition for the inspected legacy LOCAL billing_test database.
-- Preserves objects, Liquibase IDs/checksums and all business rows.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'billing_test' OR session_user<>'billing_test' THEN
  RAISE EXCEPTION 'This transition is restricted to the inspected local test DB'; END IF;
 IF EXISTS(SELECT FROM pg_namespace WHERE nspname='billing'
  AND pg_get_userbyid(nspowner) NOT IN ('billing_test','billing_migrator')) THEN
  RAISE EXCEPTION 'Unexpected Billing owner'; END IF;
 IF to_regclass('public.databasechangelog') IS NOT NULL
 AND to_regclass('billing.databasechangelog') IS NOT NULL THEN
  RAISE EXCEPTION 'Two Liquibase histories require investigation'; END IF;
END $$;
ALTER SCHEMA billing OWNER TO billing_migrator;
DO $$ DECLARE t RECORD; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='billing' AND tableowner='billing_test' LOOP
  EXECUTE format('ALTER TABLE billing.%I OWNER TO billing_migrator',t.tablename);
 END LOOP;
 IF to_regclass('public.databasechangelog') IS NOT NULL THEN
  ALTER TABLE public.databasechangelog SET SCHEMA billing;
  ALTER TABLE public.databasechangeloglock SET SCHEMA billing;
  ALTER TABLE billing.databasechangelog OWNER TO billing_migrator;
  ALTER TABLE billing.databasechangeloglock OWNER TO billing_migrator;
 END IF;
END $$;
COMMIT;
