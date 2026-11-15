# Invoice issuance storage

Changesets 014/015 add an append-only outbox and one issuance audit snapshot per
invoice. Limited runtime grants allow DRAFT→ISSUED identity/version updates,
never total, balance, source amount changes or history deletion. A database
trigger fixes issued identity and preserves every other header field. Existing
changesets and checksums are unchanged.

The nullable internal pricing_authority_role records the verified Dentist or
Administrator role at manual price entry. It is not an invoice HTTP field and
must be populated by the validated owner pricing workflow. Old snapshots gain
no inferred authority. Issuance must reject unproven manual entries, while a
valid justified manual price requires no legacy second approval threshold.

The outbox stores the canonical envelope and a unique event identity. Its
insertion must commit atomically with issuance and the saved HTTP response.
Relay delivery bookkeeping will be separate; no broker/worker availability is
needed for financial commit. No delivery or email success is asserted here.

Five SQL suites and repeat migration passed on disposable PostgreSQL 16 with
Liquibase 4.31.1 and billing_runtime. Tests cover issuance writes, fixed identity,
no amount rewrite, no price-authority rewrite, append-only event/history and
unique issuance. Future payment lifecycle grants need their own guarded migration.
