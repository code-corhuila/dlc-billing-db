\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.encounter_accounts
(encounter_account_id,clinical_record_id,consultation_id,appointment_id,patient_id)
VALUES ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',
'10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000004',
'10000000-0000-4000-8000-000000000005');
INSERT INTO billing.billable_items
(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
item_type,description,quantity,unit_price,created_by,justification)
VALUES ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',
'10000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000004',
'20000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000003',
'BASE_PROCEDURE','Synthetic financial snapshot',0.5000,0.01,
'20000000-0000-4000-8000-000000000004','Protected test justification');
DO $$
DECLARE sample billing.billable_items%ROWTYPE;
BEGIN
  SELECT * INTO STRICT sample FROM billing.billable_items;
  IF sample.line_total <> 0.01 OR sample.status <> 'UNBILLED' THEN
    RAISE EXCEPTION 'Exact per-line half-up rounding failed';
  END IF;
  BEGIN
    INSERT INTO billing.encounter_accounts SELECT * FROM billing.encounter_accounts;
    RAISE EXCEPTION 'Duplicate encounter accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    sample.item_id := '30000000-0000-4000-8000-000000000001';
    INSERT INTO billing.billable_items
    (item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
     item_type,description,quantity,unit_price,currency,approval_required,catalog_version,
     justification,created_by,created_at,updated_at,version,status)
    SELECT sample.item_id,sample.encounter_account_id,sample.patient_id,sample.appointment_id,
      sample.procedure_id,sample.source_record_id,sample.item_type,sample.description,
      sample.quantity,sample.unit_price,sample.currency,sample.approval_required,
      sample.catalog_version,sample.justification,sample.created_by,sample.created_at,
      sample.updated_at,sample.version,sample.status;
    RAISE EXCEPTION 'Duplicate source accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    UPDATE billing.billable_items SET unit_price=99;
    RAISE EXCEPTION 'Runtime rewrote a snapshot';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM billing.billable_items;
    RAISE EXCEPTION 'Runtime deleted financial history';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$
DECLARE q numeric; price numeric;
BEGIN
  FOREACH q IN ARRAY ARRAY[0,-1,0.12345,'Infinity'::numeric,'NaN'::numeric] LOOP
    BEGIN
      INSERT INTO billing.billable_items
      (item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
       item_type,description,quantity,unit_price,created_by)
      SELECT gen_random_uuid(),encounter_account_id,patient_id,appointment_id,procedure_id,
       gen_random_uuid(),'ADDITIONAL_MATERIAL','Invalid quantity',q,1,created_by FROM billing.billable_items;
      RAISE EXCEPTION 'Invalid quantity accepted';
    EXCEPTION WHEN check_violation OR numeric_value_out_of_range THEN NULL; END;
  END LOOP;
  FOREACH price IN ARRAY ARRAY[0,-1,1.001,1000000000000,'NaN'::numeric] LOOP
    BEGIN
      INSERT INTO billing.billable_items
      (item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
       item_type,description,quantity,unit_price,created_by)
      SELECT gen_random_uuid(),encounter_account_id,patient_id,appointment_id,procedure_id,
       gen_random_uuid(),'ADDITIONAL_MATERIAL','Invalid price',1,price,created_by FROM billing.billable_items;
      RAISE EXCEPTION 'Invalid unit price accepted';
    EXCEPTION WHEN check_violation OR numeric_value_out_of_range THEN NULL; END;
  END LOOP;
  BEGIN
    INSERT INTO billing.billable_items
    (item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
     item_type,description,quantity,unit_price,created_by)
    SELECT gen_random_uuid(),encounter_account_id,gen_random_uuid(),appointment_id,procedure_id,
      gen_random_uuid(),'ADDITIONAL_MATERIAL','Wrong patient',1,1,created_by FROM billing.billable_items;
    RAISE EXCEPTION 'Encounter patient mismatch accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
ROLLBACK;
