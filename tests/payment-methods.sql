\set ON_ERROR_STOP on
BEGIN;
\ir support/invoice-fixture.sql
DO $$ BEGIN
 IF (SELECT count(*) FROM billing.payment_methods WHERE active AND method IN
 ('CASH','CREDIT_CARD','DEBIT_CARD','BANK_TRANSFER','NEQUI_DAVIPLATA','OTHER'))<>6 THEN
  RAISE EXCEPTION 'Default payment methods missing or inactive on fresh install'; END IF;
END $$;
INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
VALUES('75000000-0000-4000-8000-000000000001',gen_random_uuid(),6,6,gen_random_uuid());
SELECT pg_temp.seed_invoice_items('75000000-0000-4000-8000-000000000001');
UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number='BIL-method-test',issued_at=now()
WHERE invoice_id='75000000-0000-4000-8000-000000000001';
UPDATE billing.payment_methods SET active=false WHERE method='OTHER';
SET LOCAL ROLE billing_runtime;
DO $$ BEGIN
 BEGIN
  INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
  VALUES(gen_random_uuid(),'75000000-0000-4000-8000-000000000001',1,'OTHER',gen_random_uuid(),now());
  RAISE EXCEPTION 'Disabled method accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
  VALUES(gen_random_uuid(),'75000000-0000-4000-8000-000000000001',1,'UNKNOWN_METHOD',gen_random_uuid(),now());
  RAISE EXCEPTION 'Unknown method accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  UPDATE billing.payment_methods SET active=true WHERE method='OTHER';
  RAISE EXCEPTION 'Runtime changed method configuration';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE billing.payment_methods SET active=true WHERE method='OTHER';
SET LOCAL ROLE billing_runtime;
DO $$ DECLARE code TEXT; BEGIN
 FOREACH code IN ARRAY ARRAY['CASH','CREDIT_CARD','DEBIT_CARD','BANK_TRANSFER','NEQUI_DAVIPLATA','OTHER'] LOOP
  INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
  VALUES(gen_random_uuid(),'75000000-0000-4000-8000-000000000001',1,code,gen_random_uuid(),now());
 END LOOP;
 IF NOT EXISTS(SELECT FROM billing.invoices WHERE invoice_id='75000000-0000-4000-8000-000000000001'
 AND status='PAID' AND balance=0 AND version=8) THEN
  RAISE EXCEPTION 'Configured methods did not produce correct payment balance'; END IF;
END $$;
ROLLBACK;
