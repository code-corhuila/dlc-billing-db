# Encounter write admission storage

020/021 implement ADR-017 owner-local gates without creating placeholder financial
accounts or inventing patient/appointment IDs when Clinical freezes an empty
encounter. The key is exactly clinicalRecordId plus consultationId.

Admission INSERT takes the same gate row lock as freeze, so it either precedes
freeze or fails closed. ADMITTED outcomes never expire. Only COMMITTED/ABORTED
resolution is allowed; the audit cannot be deleted or reopened by runtime. Gates
use versioned transitions, retain operation identity, and cannot reopen after a
recorded committed declaration. Freeze history retains explicit releases.

RED failed on the missing gate. GREEN: encounter-admissions, payments,
invoice-issuance and outbox-deliveries SQL suites passed, with repeat migration.
This is coordination storage, not evidence of a complete manual charge workflow.
The future charge transaction must resolve admission and money atomically; only
authoritative source correlation can enable that HTTP write.
