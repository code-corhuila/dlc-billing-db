\set ON_ERROR_STOP on
BEGIN;
\ir support/invoice-fixture.sql
INSERT INTO billing.payment_methods(method) VALUES ('SYNTHETIC_LOCAL');
INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
VALUES ('74000000-0000-4000-8000-000000000001',gen_random_uuid(),10.01,10.01,gen_random_uuid());
SELECT pg_temp.seed_invoice_items('74000000-0000-4000-8000-000000000001');
UPDATE billing.invoices SET status='ISSUED',version=2,invoice_number='BIL-payment-test',issued_at=now()
WHERE invoice_id='74000000-0000-4000-8000-000000000001';
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
VALUES (gen_random_uuid(),'74000000-0000-4000-8000-000000000001',4.01,'SYNTHETIC_LOCAL',gen_random_uuid(),now());
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM billing.invoices WHERE invoice_id='74000000-0000-4000-8000-000000000001'
 AND balance=6.00 AND status='PARTIALLY_PAID' AND version=3) THEN RAISE EXCEPTION 'Incorrect partial balance'; END IF;
 BEGIN
 INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
 VALUES(gen_random_uuid(),'74000000-0000-4000-8000-000000000001',6.01,'SYNTHETIC_LOCAL',gen_random_uuid(),now());
 RAISE EXCEPTION 'Overpayment accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
 UPDATE billing.invoices SET balance=0,status='PAID',version=4;
 RAISE EXCEPTION 'Balance changed without payment'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
 UPDATE billing.payments SET amount=1;
 RAISE EXCEPTION 'Payment rewritten'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
 INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
 VALUES(gen_random_uuid(),'74000000-0000-4000-8000-000000000001',1,'UNCONFIGURED',gen_random_uuid(),now());
 RAISE EXCEPTION 'Unconfigured method accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
VALUES(gen_random_uuid(),'74000000-0000-4000-8000-000000000001',6,'SYNTHETIC_LOCAL',gen_random_uuid(),now());
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM billing.invoices WHERE invoice_id='74000000-0000-4000-8000-000000000001'
 AND balance=0 AND status='PAID' AND version=4) THEN RAISE EXCEPTION 'Incorrect paid balance'; END IF;
 BEGIN
 DELETE FROM billing.payments;
 RAISE EXCEPTION 'Payment history deleted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
