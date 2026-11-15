# Manual charge financial storage

024/025 add immutable manual amounts, concepts, justifications, actor/role and
source correlation. Runtime may insert/read but cannot rewrite or delete charges.
Manual item identity is the clinical source UUID; charge identity is separate.
A committed admission must reference the matching durable manual money record.

Encounter transitions are restricted for runtime: OPEN to DECLARED must match the
stored Clinical declaration and frozen gate; DECLARED to CHARGES_COMPLETED requires
procedure receipts and declared manual charges. Financial identity stays fixed.
Migrator-owned synthetic fixtures remain administratively configurable for tests.

RED: manual charge table absent. GREEN: six SQL suites passed, including manual,
clinical inbox, admissions, billable snapshots, issuance and payments; repeat
migration passed. Actual manual HTTP/authorization work is a separate increment.
