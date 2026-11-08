# Internal payment history

018/019 are forward-only migrations extending the 014 invoice lifecycle without
changing its checksum. Payments and event-state receipts are immutable to runtime;
configuration belongs to the owner. Migration 030 now inserts the six documented
MVP codes when missing: `CASH`, `CREDIT_CARD`, `DEBIT_CARD`, `BANK_TRANSFER`,
`NEQUI_DAVIPLATA`, `OTHER`. New rows are active; existing rows keep their active
state through `ON CONFLICT DO NOTHING`. No real payment gateway or money transfer
is involved. Source: `dlc-docs/12-ux-ui/mvp/MVP-SPEC.md` (PaymentMethod) and
`dlc-docs/03-product/mvp-scope.md` (Billing). The current API contract accepts a
method string and validates it against this owner catalog.

An owner migration/deployment credential may disable a method with
`UPDATE billing.payment_methods SET active=false WHERE method='OTHER';`.
Historical payments remain readable. Runtime can only read this configuration.
The Portal currently requires the exact code in its method text input.
Rollback must preserve used method rows; disable methods rather than delete
payment history. Apply the regular Liquibase changelog to configure an existing
environment; changing these repository files alone does not update a live DB.

The insert trigger locks the invoice and rejects unpayable state, excess balance,
invalid methods and exhausted versions. The invoice trigger preserves issued
identity/items/totals and accepts only balances matching the immutable payment sum.
Runtime receives no configuration UPDATE or history DELETE/UPDATE permission.

RED: payments.sql failed because payment_methods did not exist. GREEN: all seven
SQL suites passed on fresh PostgreSQL 16, with repeated Liquibase update. API tests
also passed partial/full payment, concurrency, replay and rollback using runtime.

Verified 2026-11-07: Liquibase validate/update/repeat update, all 12 SQL suites,
and seed replay preserving disabled/custom owner methods passed on disposable
PostgreSQL 16. Each of the six default codes registered a payment successfully;
disabled/unknown methods and runtime configuration writes were rejected.
