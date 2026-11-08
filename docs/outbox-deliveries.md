# Durable event delivery state

Changesets 016/017 keep publication bookkeeping in outbox_deliveries, separate
from the immutable financial envelope and issuance snapshot. Every new outbox
insert schedules one PENDING row in its transaction; older events are backfilled.
Only delivery status, attempts and retry/confirmation timestamps are writable by
the runtime. Event identity/content and financial history cannot be rewritten.

Workers lock only delivery rows. Each attempt increments the counter once;
confirmed or exhausted outcomes cannot be reopened by a routine update. Ten
failed attempts retain FAILED work for operator reconciliation; no unbounded
retry or automatic deletion is provided. A reviewed requeue workflow remains
separate. Source-owner deletion cascades bookkeeping only; runtime DELETE
remains denied and financial history still has its own foreign-key guards.

Six SQL suites and repeat migration passed on disposable PostgreSQL 16 using
the limited runtime identity. Actual RabbitMQ confirms/recovery require the
following API publisher and real broker integration increments.

Upgrade verification also passed from pre-relay Billing DB 1f35d18: an existing
committed event received exactly one PENDING row, its body stayed byte-for-byte
unchanged, and repeat migration introduced no duplicate. The disposable API
integration test tests/integration/test_outbox_upgrade.py finished in 92.541 s.
