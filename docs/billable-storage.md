# Billable snapshot storage

Changesets 008/009 add owner-local EncounterAccount and BillableItem storage
from the Billing data model and ADR-015/ADR-017. No invoice is created to hold
pre-invoice items; no foreign keys or reads target another owner's schema.

One account is identified by clinical record plus consultation. Composite
references keep an item's patient and appointment consistent with its account.
Source identity is unique across snapshots; a partial unique index prevents
two base items for one procedure, including manual/catalog reconciliation.

Quantities and unit prices use exact NUMERIC with explicit bounds/scale checks.
This intentionally avoids NUMERIC typmod silently rounding excess input
precision before a CHECK can inspect it. Stored line_total uses NUMERIC(14,2)
and PostgreSQL round(quantity * unit_price, 2), matching positive ROUND_HALF_UP.
Overflow fails rather than truncating. Prices remain independent of catalog changes.

Runtime receives SELECT/INSERT only on these new tables. It cannot rewrite or
delete snapshot amounts or narratives. Future invoice allocation and encounter
state transitions require separately reviewed transaction logic and grants;
these changesets do not implement admission, declaration or message consumers.
Protected justification/actor/source data must stay out of public projections.

## Verification

On a disposable PostgreSQL 16 database, apply bootstrap as its DBA, provision
the migrator password outside Git, and migrate with Liquibase 4.31.1 using
billing_migrator and billing as the default/history schema. Nine changesets
apply. Re-running update succeeds without another change. Run
`psql -v ON_ERROR_STOP=1 -f tests/billable-snapshots.sql` as that disposable DBA.
The script uses runtime permissions for real writes and history denials, then
checks invalid precision/amounts and mismatched patient references; it rolls back
all fixtures. The existing runtime-permissions SQL script also passes.
No shared or production database was changed. Existing changeset SQL is unchanged.
