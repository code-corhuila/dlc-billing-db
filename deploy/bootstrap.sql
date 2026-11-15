-- Run once as the development/stage DBA. Provision passwords separately.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='billing_migrator') THEN
    CREATE ROLE billing_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='billing_runtime') THEN
    CREATE ROLE billing_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname IN ('billing_migrator','billing_runtime')
      AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls))
      OR pg_has_role('billing_runtime','billing_migrator','MEMBER') THEN
    RAISE EXCEPTION 'Existing Billing role has unexpected privileges';
  END IF;
  IF EXISTS (SELECT FROM pg_namespace n JOIN pg_roles r ON r.oid=n.nspowner
      WHERE n.nspname='billing' AND r.rolname <> 'billing_migrator') THEN
    RAISE EXCEPTION 'Existing Billing schema has another owner; reviewed ownership migration required';
  END IF;
END $$;
-- Match the existing Appointments owner prerequisite on a fresh shared database.
-- Preserve installed extensions: relocating an existing deployment is a DBA decision.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_extension WHERE extname='btree_gist') THEN
    IF EXISTS (SELECT FROM pg_namespace WHERE nspname='appointments_extensions'
        AND nspowner <> current_user::regrole) THEN
      RAISE EXCEPTION 'Existing extension schema has another owner; DBA review required';
    END IF;
    CREATE SCHEMA IF NOT EXISTS appointments_extensions;
    REVOKE ALL ON SCHEMA appointments_extensions FROM PUBLIC;
    CREATE EXTENSION btree_gist WITH SCHEMA appointments_extensions;
  END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS billing AUTHORIZATION billing_migrator;
REVOKE ALL ON SCHEMA billing FROM PUBLIC;
