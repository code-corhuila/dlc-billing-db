\set ON_ERROR_STOP on
BEGIN;
\ir support/invoice-fixture.sql
SET LOCAL ROLE billing_runtime;
DO $$
DECLARE patient UUID=gen_random_uuid(); invoice UUID=gen_random_uuid();
 empty_invoice UUID=gen_random_uuid(); account UUID=gen_random_uuid();
 appointment UUID=gen_random_uuid(); extra UUID=gen_random_uuid();
 cycle INTEGER;
BEGIN
 BEGIN
  INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,status,invoice_number,issued_at,created_by)
  VALUES(gen_random_uuid(),patient,10,10,'ISSUED','FORBIDDEN-DIRECT',now(),gen_random_uuid());
  RAISE EXCEPTION 'Direct issued invoice insert accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
 VALUES(empty_invoice,patient,10,10,gen_random_uuid()),(invoice,patient,10,10,gen_random_uuid());
 BEGIN
  UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number=empty_invoice::text,issued_at=now()
  WHERE invoice_id=empty_invoice;
  RAISE EXCEPTION 'Empty invoice issued';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM pg_temp.seed_invoice_items(invoice);
 -- A billed item with an incorrect declared total must also be rejected.
 INSERT INTO billing.encounter_accounts(encounter_account_id,clinical_record_id,consultation_id,patient_id,appointment_id)
 VALUES(account,gen_random_uuid(),gen_random_uuid(),patient,appointment);
 INSERT INTO billing.billable_items(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
 item_type,description,quantity,unit_price,created_by,status)
 VALUES(extra,account,patient,appointment,gen_random_uuid(),gen_random_uuid(),
 'BASE_PROCEDURE','Financial boundary extra',1,99,gen_random_uuid(),'BILLED');
 INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id) VALUES(empty_invoice,patient,extra);
 BEGIN
  UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number=empty_invoice::text,issued_at=now()
  WHERE invoice_id=empty_invoice;
  RAISE EXCEPTION 'Incorrect invoice total issued';
 EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number=invoice::text,issued_at=now()
 WHERE invoice_id=invoice;
 -- Use a distinct item; uniqueness must not be the reason this insertion fails.
 extra=gen_random_uuid();
 INSERT INTO billing.billable_items(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
 item_type,description,quantity,unit_price,created_by,status)
 VALUES(extra,account,patient,appointment,gen_random_uuid(),gen_random_uuid(),
 'BASE_PROCEDURE','Late extra',1,99,gen_random_uuid(),'BILLED');
 BEGIN
  INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id) VALUES(invoice,patient,extra);
  RAISE EXCEPTION 'Item appended after issue';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT FROM billing.invoices i WHERE i.invoice_id=invoice AND total=10 AND version=2)
 OR (SELECT count(*) FROM billing.invoice_items ii WHERE ii.invoice_id=invoice)<>1 THEN
  RAISE EXCEPTION 'Rejected allocation changed issued state'; END IF;
 FOR cycle IN 1..2 LOOP
  INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
  VALUES(gen_random_uuid(),invoice,5,'CASH',gen_random_uuid(),now());
  BEGIN
   INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id) VALUES(invoice,patient,extra);
   RAISE EXCEPTION 'Item appended after payment';
  EXCEPTION WHEN check_violation THEN NULL; END;
 END LOOP;
END $$;
DO $$ DECLARE bad NUMERIC; BEGIN
 FOREACH bad IN ARRAY ARRAY['NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric,0::numeric,(-1)::numeric] LOOP
  BEGIN
   INSERT INTO billing.procedure_prices(price_id,procedure_code,name,base_price,valid_from,version,created_by,created_at,updated_at)
   VALUES(gen_random_uuid(),'BOUNDARY-PRICE','Boundary',bad,now(),1,gen_random_uuid(),now(),now());
   RAISE EXCEPTION 'Invalid procedure price accepted: %',bad;
  EXCEPTION WHEN check_violation OR numeric_value_out_of_range THEN NULL; END;
  BEGIN
   INSERT INTO billing.additional_price_rules(rule_id,rule_code,item_type,unit_price,valid_from,version,created_by,created_at,updated_at)
   VALUES(gen_random_uuid(),'BOUNDARY-RULE','ADDITIONAL_MATERIAL',bad,now(),1,gen_random_uuid(),now(),now());
   RAISE EXCEPTION 'Invalid additional rule price accepted: %',bad;
  EXCEPTION WHEN check_violation OR numeric_value_out_of_range THEN NULL; END;
 END LOOP;
END $$;
ROLLBACK;
