\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.encounter_accounts(encounter_account_id,clinical_record_id,consultation_id,appointment_id,patient_id)
VALUES ('60000000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),
'60000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000003');
INSERT INTO billing.billable_items(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,
source_record_id,item_type,description,quantity,unit_price,created_by)
VALUES ('60000000-0000-4000-8000-000000000004','60000000-0000-4000-8000-000000000001',
'60000000-0000-4000-8000-000000000003','60000000-0000-4000-8000-000000000002',gen_random_uuid(),
gen_random_uuid(),'BASE_PROCEDURE','Synthetic draft fixture',1,10.01,gen_random_uuid());
INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
VALUES ('60000000-0000-4000-8000-000000000005','60000000-0000-4000-8000-000000000003',10.01,10.01,gen_random_uuid());
INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id)
VALUES ('60000000-0000-4000-8000-000000000005','60000000-0000-4000-8000-000000000003','60000000-0000-4000-8000-000000000004');
INSERT INTO billing.invoice_appointment_validations(invoice_id,appointment_id,patient_id,appointment_version,validated_at)
VALUES ('60000000-0000-4000-8000-000000000005','60000000-0000-4000-8000-000000000002',
'60000000-0000-4000-8000-000000000003',7,now());
UPDATE billing.billable_items SET status='BILLED',version=version+1,updated_at=now()
WHERE item_id='60000000-0000-4000-8000-000000000004';
DO $$ BEGIN
  BEGIN
    UPDATE billing.billable_items SET status='UNBILLED',version=version+1,updated_at=now();
    RAISE EXCEPTION 'Billed source reopened';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE billing.billable_items SET unit_price=20;
    RAISE EXCEPTION 'Financial snapshot rewritten';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE billing.invoices SET total=20;
    RAISE EXCEPTION 'Invoice amount rewritten';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM billing.invoice_appointment_validations;
    RAISE EXCEPTION 'Authority evidence deleted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
