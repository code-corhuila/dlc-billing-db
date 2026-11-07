# Internal payment history

018/019 are forward-only migrations extending the 014 invoice lifecycle without
changing its checksum. Payments and event-state receipts are immutable to runtime;
configuration belongs to the owner. No payment methods are enabled by migration.
Configure approved internal/simulated codes in billing.payment_methods through
owner deployment tooling; no real payment gateway or money transfer is involved.

The insert trigger locks the invoice and rejects unpayable state, excess balance,
invalid methods and exhausted versions. The invoice trigger preserves issued
identity/items/totals and accepts only balances matching the immutable payment sum.
Runtime receives no configuration UPDATE or history DELETE/UPDATE permission.

RED: payments.sql failed because payment_methods did not exist. GREEN: all seven
SQL suites passed on fresh PostgreSQL 16, with repeated Liquibase update. API tests
also passed partial/full payment, concurrency, replay and rollback using runtime.
