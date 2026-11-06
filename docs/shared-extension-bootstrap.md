# Shared database extension prerequisite

Appointments DB develop 5b09c81 requires btree_gist in the DBA-owned
appointments_extensions schema. Billing formerly installed it in public on a
fresh database, causing the later Appointments bootstrap to abort with
`btree_gist is installed outside appointments_extensions`.

Billing now uses the existing protected prerequisite namespace on fresh
installations. No business migration/checksum changes, extension moves or extra
cross-owner grants are needed. PostgreSQL resolves the default GiST operator
classes without granting Billing access to that namespace. Runtime identities
cannot access the extension schema or the other owner's business schema.

An installed extension is preserved. Existing environments with btree_gist in
public still require a reviewed DBA compatibility/migration decision before
adding Appointments; this script deliberately does not relocate their extension.

Verification: set APPOINTMENTS_DB_SOURCE to the official DB checkout, then run
`python tests/shared-extension-bootstrap.py` and repeat with
`--appointments-first`. Each command creates and removes its own random Docker
network/container, runs both real Liquibase changelogs, repeats bootstrap and
Billing migration, checks isolation and runs all four Billing SQL suites.
Both orders passed against PostgreSQL 16 and Liquibase 4.31.1. No host port,
external database URL, persisted credential or production database is used.
