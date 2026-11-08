# Billing DB publication

This branch publishes the pending Billing schema through changeset 031. It includes
31 prerequisite local commits absent from develop: additional rules/idempotency,
owner-scoped permissions, source snapshots, draft allocation, issuance/outbox, payments,
encounter admissions, clinical projections and administrative price correction.

New pending changes add financial correlations, preserve payment-method owner choices
while inserting missing supported codes, and close the audited financial boundaries:
allocation requires a locked DRAFT invoice; issuance requires billed items whose sum
matches the total; direct insertion of issued invoices is denied; catalog prices must
be finite. Applied historical changesets remain unchanged. Inconsistent historical data
stops the migration for explicit owner reconciliation.

SQL, concurrency, upgrade/recovery and focused JDBC compatibility runners are included.
The upgrade runner pins pre-boundary revision `5c0df70` rather than the moving HEAD;
`BILLING_UPGRADE_BASELINE` can explicitly select another compatible historical revision.
`BILLING_API_SOURCE` selects the matching API checkout for focused JDBC validation.

Publication validation passed: all 13 SQL suites, both real allocation/issuance lock
orders, refusal of inconsistent historical issuance, upgrade with preserved row hashes,
logical backup/restore with restored runtime grants, and 27 actual API transaction tests
without failures, errors or skips. The JDBC runner uses a clean compilation to avoid
reusing classes from an earlier fixture revision.

The API and Portal now also have actual local IAM/Gateway/Billing/Appointments
acceptance, including the API's first-payment minimum of 50%, PDFs and logout revocation.
After those checks, the synthetic invoices/payments/source appointments were removed
at the user's request. Cleanup changed only the isolated local data, not migrations,
payment methods, administrator access or other PostgreSQL deployments.

Local application history and earlier independent integration evidence remain in their
dated reports. Source fixtures are synthetic; full Clinical/Worker delivery, production
backup recovery, operational approval and deployment to qa/main remain separate gates.
Private configurations, credentials, backups and `.local-validation` evidence are excluded.
