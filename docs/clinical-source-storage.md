# Clinical source storage

022/023 add an immutable minimized inbox and owner-local procedure, extra,
consultation and declaration projections. Event IDs, procedure IDs and clinical
source IDs have separate uniqueness boundaries. Runtime cannot rewrite or delete
facts; only a one-way projected timestamp can be added to the inbox.

The original envelope is hashed by the receiver; clinical narrative is discarded.
The inbox additionally rejects any clinicalReason property through JSONPath.
No placeholder amount or financial account is created by receiving a source.
Receipt tables reserve once-only procedure/account publication identities for
reconciliation; all event receipts refer to the existing immutable outbox.

RED: inbox relation absent. GREEN: clinical-inbox, encounter-admissions, payments,
invoice-issuance and outbox-deliveries SQL suites passed, including repeat migration.
Financial transitions and transport consumption require later API increments.
