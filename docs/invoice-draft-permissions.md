# Invoice draft allocation permissions

Changesets 012/013 extend read storage for the real draft transaction. Runtime
can INSERT invoices/allocations and immutable appointment-validation evidence,
and UPDATE only billable status/version/audit time. It still cannot rewrite
amounts, descriptions, patients, source identities or invoice totals, or delete
financial/audit history. The previous read-only INSERT denial test is retired
because invoice creation is now an intended owner capability.

The allocation trigger permits only UNBILLED to BILLED with version +1 and
nondecreasing audit time, preserving every other stored field. Generated line
total is checked through its immutable quantity/unit-price inputs because it
is computed after BEFORE triggers. A BILLED source cannot be reopened.

invoice_appointment_validations stores the verified terminal appointment
version/time for invoice audit, including drafts spanning several appointments.
It is owner-local implementation data, not a new external contract or a cache
that replaces an authoritative check for a new invoice.

Verification on disposable PostgreSQL 16 / Liquibase 4.31.1: thirteen changesets
apply and repeat update makes no additional change. All four SQL suites pass,
including permitted allocation and denied history changes. Six real JDBC
transaction tests pass as billing_runtime. Test fixtures are synthetic and all
resources are removed. No shared database or applied changeset SQL was changed.
