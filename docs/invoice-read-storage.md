# Invoice read storage

Changesets 010/011 add invoices and their owner-local item allocations after
the pre-invoice storage. No placeholder invoices or cross-owner foreign keys
are introduced. Financial item values stay in immutable BillableItem snapshots.

Invoice identity, patient, exact COP total/balance, lifecycle and audit fields
follow the official owner model. Issued states require an invoice number/date;
balances cannot exceed totals. A billable item has at most one allocation;
composite foreign keys reject a different patient on either side of the link.

The runtime receives SELECT only on invoices and invoice_items. Draft creation,
issuance, cancellation, payment transactions and their narrowly scoped grants
are separate increments. These migrations do not establish those workflows or
prove that administrative care finalization has happened.

## Verification

On isolated PostgreSQL 16, bootstrap as that database's DBA and migrate with
Liquibase 4.31.1 as billing_migrator, using billing for default/history schemas.
Eleven changesets apply; repeat update makes no new change. Existing SQL and
checksums are preserved. `tests/invoice-storage.sql` creates explicit synthetic
financial fixtures inside a transaction, checks runtime reads and denied writes,
rejects invalid balances/issue identity, duplicate allocation and cross-patient
links, then rolls back all fixtures. Run with `psql -v ON_ERROR_STOP=1 -f
tests/invoice-storage.sql` only against a disposable test database as its DBA.
The existing snapshot and runtime-permission suites also pass on the new schema.
