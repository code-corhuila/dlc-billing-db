# Billing database runtime identity

Run `deploy/bootstrap.sql` as the stage DBA before migrations. It creates separate
`billing_migrator` and `billing_runtime` logins without passwords, installs the
required extension, and creates the migrator-owned schema. Provision passwords
through the stage secret mechanism; never embed them in SQL or Git. Existing
schemas owned by another role are rejected, not silently reassigned. Inspect and
plan their owner migration separately.

Run Liquibase as `billing_migrator`, using both default schema and Liquibase
history schema `billing`. The migrator receives no superuser or role-management
privilege. Changeset 007 requires the bootstrap roles and catalog changesets
through 006. Runtime receives only schema usage, SELECT/INSERT on the three API
tables and UPDATE of validity-end/audit-time columns on catalog tables.
It cannot rewrite historical amounts, delete retained responses, create tables,
or read/change Liquibase metadata. Future tables receive no implicit API grants.

Verify on an isolated migrated database with `tests/runtime-permissions.sql`.
The test uses SET LOCAL ROLE and rolls its writes back. Deployment credentials
must use `billing_runtime`; the existing test administrator is not a runtime
identity. Validate other owner schemas through the infrastructure scope checker
once those real schemas exist. This change modifies no production instance.

Verified 2026-11-06 on isolated PostgreSQL 16: seven changesets applied using
billing_migrator, permission/write/rollback checks passed, second update ran zero
changesets, and validation against the older test database passed without checksum
changes. No production database or existing schema ownership was modified.
