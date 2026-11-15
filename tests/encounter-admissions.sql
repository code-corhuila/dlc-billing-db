\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.encounter_write_gates(clinical_record_id,consultation_id)
VALUES ('75000000-0000-4000-8000-000000000001','75000000-0000-4000-8000-000000000002');
INSERT INTO billing.manual_charge_admissions(operation_id,clinical_record_id,consultation_id,charge_id)
VALUES ('75000000-0000-4000-8000-000000000003','75000000-0000-4000-8000-000000000001',
'75000000-0000-4000-8000-000000000002',gen_random_uuid());
UPDATE billing.encounter_write_gates SET freeze_state='FROZEN',freeze_operation_id=gen_random_uuid(),version=version+1
WHERE clinical_record_id='75000000-0000-4000-8000-000000000001';
DO $$ BEGIN
 IF (SELECT count(*) FROM billing.manual_charge_admissions WHERE state='ADMITTED')<>1
 THEN RAISE EXCEPTION 'Unknown admission disappeared'; END IF;
 BEGIN
 INSERT INTO billing.manual_charge_admissions(operation_id,clinical_record_id,consultation_id,charge_id)
 VALUES(gen_random_uuid(),'75000000-0000-4000-8000-000000000001','75000000-0000-4000-8000-000000000002',gen_random_uuid());
 RAISE EXCEPTION 'Late admission accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
UPDATE billing.manual_charge_admissions SET state='ABORTED',resolved_at=now()
WHERE operation_id='75000000-0000-4000-8000-000000000003';
DO $$ BEGIN
 BEGIN
 UPDATE billing.manual_charge_admissions SET state='COMMITTED',resolved_at=now();
 RAISE EXCEPTION 'Terminal admission reopened'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
 DELETE FROM billing.manual_charge_admissions;
 RAISE EXCEPTION 'Admission audit deleted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
