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
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA IF NOT EXISTS billing AUTHORIZATION billing_migrator;
REVOKE ALL ON SCHEMA billing FROM PUBLIC;
