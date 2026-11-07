\set ON_ERROR_STOP on
BEGIN;
INSERT INTO billing.encounter_accounts
(encounter_account_id,clinical_record_id,consultation_id,appointment_id,patient_id)
VALUES ('40000000-0000-4000-8000-000000000001',gen_random_uuid(),gen_random_uuid(),
'40000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003');
INSERT INTO billing.billable_items
(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
item_type,description,quantity,unit_price,created_by,status)
VALUES ('40000000-0000-4000-8000-000000000004','40000000-0000-4000-8000-000000000001',
'40000000-0000-4000-8000-000000000003','40000000-0000-4000-8000-000000000002',
gen_random_uuid(),gen_random_uuid(),'BASE_PROCEDURE','Invoice test snapshot',1,10.01,gen_random_uuid(),'BILLED');
INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by,created_at)
VALUES ('50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000003',10.01,10.01,gen_random_uuid(),'2026-11-06T00:00:00Z');
INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id)
VALUES ('50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000003',
'40000000-0000-4000-8000-000000000004');
SET LOCAL ROLE billing_runtime;
DO $$
BEGIN
  IF (SELECT total FROM billing.invoices) <> 10.01 OR (SELECT count(*) FROM billing.invoice_items) <> 1 THEN
    RAISE EXCEPTION 'Runtime cannot read invoice snapshots';
  END IF;
  BEGIN
    UPDATE billing.invoices SET total=99;
    RAISE EXCEPTION 'Read runtime changed invoice amounts';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM billing.invoice_items;
    RAISE EXCEPTION 'Read runtime removed invoice sources';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$
BEGIN
  BEGIN
    INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
    VALUES (gen_random_uuid(),gen_random_uuid(),10,11,gen_random_uuid());
    RAISE EXCEPTION 'Balance above total accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,status,created_by)
    VALUES (gen_random_uuid(),gen_random_uuid(),10,10,'ISSUED',gen_random_uuid());
    RAISE EXCEPTION 'Issued invoice without financial identity accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
    VALUES ('50000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003',10.01,10.01,gen_random_uuid());
    INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id)
    SELECT '50000000-0000-4000-8000-000000000002',patient_id,item_id FROM billing.invoice_items;
    RAISE EXCEPTION 'Duplicate source allocation accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  DELETE FROM billing.invoice_items;
  INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
  VALUES ('50000000-0000-4000-8000-000000000003','50000000-0000-4000-8000-000000000004',10.01,10.01,gen_random_uuid());
  BEGIN
    INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id)
    VALUES ('50000000-0000-4000-8000-000000000003','50000000-0000-4000-8000-000000000004',
      '40000000-0000-4000-8000-000000000004');
    RAISE EXCEPTION 'Cross-patient allocation accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
ROLLBACK;
