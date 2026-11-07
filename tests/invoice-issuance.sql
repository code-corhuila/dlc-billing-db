\set ON_ERROR_STOP on
BEGIN;
INSERT INTO billing.encounter_accounts(encounter_account_id,clinical_record_id,consultation_id,appointment_id,patient_id,status)
VALUES ('71000000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),
'71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','CHARGES_COMPLETED');
INSERT INTO billing.billable_items(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
item_type,description,quantity,unit_price,created_by,status,justification,pricing_authority_role)
VALUES ('71000000-0000-4000-8000-000000000004','71000000-0000-4000-8000-000000000001',
'71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000002',gen_random_uuid(),gen_random_uuid(),
'BASE_PROCEDURE','Synthetic authorized manual price',1,10.01,gen_random_uuid(),'BILLED','Protected reason','DENTIST');
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
VALUES ('71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000003',10.01,10.01,gen_random_uuid());
INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id)
VALUES ('71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004');
UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number='BIL-test-issuance',issued_at=now(),updated_at=now()
WHERE invoice_id='71000000-0000-4000-8000-000000000005';
INSERT INTO billing.outbox_events(event_id,aggregate_id,event_type,event_version,occurred_at,event_body)
SELECT '71000000-0000-4000-8000-000000000006',invoice_id,'InvoiceIssued',1,issued_at,
jsonb_build_object('eventId','71000000-0000-4000-8000-000000000006','aggregateId',invoice_id,
'eventType','InvoiceIssued','version',1,'producer','billing-service','aggregateType','Invoice',
'occurredAt',issued_at,'payload',jsonb_build_object('invoiceId',invoice_id,'patientId',patient_id,
'total',total::text,'currency','COP','issuedAt',issued_at,'issuedBy',created_by),
'metadata',jsonb_build_object('correlationId',gen_random_uuid(),'causationId',gen_random_uuid(),'actorUserId',created_by))
FROM billing.invoices WHERE invoice_id='71000000-0000-4000-8000-000000000005';
INSERT INTO billing.invoice_issuances(invoice_id,event_id,issued_by,invoice_version,invoice_snapshot)
SELECT invoice_id,'71000000-0000-4000-8000-000000000006',created_by,version,
jsonb_build_object('id',invoice_id,'version',version,'status',status,'total',total::text,'balance',balance::text)
FROM billing.invoices WHERE invoice_id='71000000-0000-4000-8000-000000000005';
DO $$ BEGIN
  BEGIN
    UPDATE billing.invoices SET invoice_number='rewritten';
    RAISE EXCEPTION 'Issued identity rewritten';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE billing.invoices SET total=20;
    RAISE EXCEPTION 'Invoice amount rewritten';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE billing.billable_items SET pricing_authority_role='ADMINISTRATOR';
    RAISE EXCEPTION 'Historical price authority rewritten';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE billing.outbox_events SET event_body='{}';
    RAISE EXCEPTION 'Event rewritten';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM billing.invoice_issuances;
    RAISE EXCEPTION 'Issuance history deleted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO billing.invoice_issuances SELECT * FROM billing.invoice_issuances;
    RAISE EXCEPTION 'Duplicate issuance accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
ROLLBACK;
