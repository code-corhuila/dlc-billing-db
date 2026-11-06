\set ON_ERROR_STOP on
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'billing_runtime') THEN
    RAISE EXCEPTION 'Billing runtime role is missing';
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname IN ('billing_runtime','billing_migrator')
      AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)) THEN
    RAISE EXCEPTION 'Billing roles have elevated privileges';
  END IF;
  IF has_schema_privilege('billing_runtime','billing','CREATE')
      OR pg_has_role('billing_runtime','billing_migrator','MEMBER') THEN
    RAISE EXCEPTION 'Runtime can migrate its schema';
  END IF;
  IF has_table_privilege('billing_runtime','billing.databasechangelog','SELECT')
      OR has_table_privilege('billing_runtime','billing.procedure_prices','DELETE')
      OR has_table_privilege('billing_runtime','billing.idempotency_records','UPDATE') THEN
    RAISE EXCEPTION 'Runtime can change history or read migration metadata';
  END IF;
END $$;

BEGIN;
CREATE SCHEMA billing_other_owner_probe;
CREATE TABLE billing_other_owner_probe.private_data(id int);
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.procedure_prices
(price_id,procedure_code,name,base_price,currency,valid_from,status,version,created_by,created_at,updated_at)
VALUES ('11111111-1111-4111-8111-111111111111','PERMISSION-CHECK','Permission check',10.01,
'COP','2026-01-01','ACTIVE',1,'11111111-1111-4111-8111-111111111111',now(),now());
UPDATE billing.procedure_prices SET valid_to='2026-02-01',updated_at=now()
WHERE procedure_code='PERMISSION-CHECK';
INSERT INTO billing.additional_price_rules
(rule_id,rule_code,item_type,unit_price,currency,requires_approval,valid_from,status,version,created_by,created_at,updated_at)
VALUES ('22222222-2222-4222-8222-222222222222','PERMISSION-CHECK','ADDITIONAL_MATERIAL',
10.01,'COP',false,'2026-01-01','ACTIVE',1,'11111111-1111-4111-8111-111111111111',now(),now());
UPDATE billing.additional_price_rules SET valid_to='2026-02-01',updated_at=now()
WHERE rule_code='PERMISSION-CHECK';
INSERT INTO billing.idempotency_records
(record_id,idempotency_key,actor_id,operation_name,resource_key,request_hash,response_status,
response_headers,response_body,created_at,expires_at)
VALUES ('33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444',
'11111111-1111-4111-8111-111111111111','permission-test','PERMISSION-CHECK',repeat('a',64),
201,'{}','{}',now(),now()+interval '7 days');
DO $$
BEGIN
  IF (SELECT count(*) FROM billing.procedure_prices WHERE procedure_code='PERMISSION-CHECK') <> 1 THEN
    RAISE EXCEPTION 'Catalog read failed';
  END IF;
  BEGIN
    UPDATE billing.procedure_prices SET base_price=20 WHERE procedure_code='PERMISSION-CHECK';
    RAISE EXCEPTION 'Runtime rewrote a historical amount';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM 1 FROM billing_other_owner_probe.private_data;
    RAISE EXCEPTION 'Runtime read another owner schema';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    CREATE TABLE billing.forbidden_table(id int);
    RAISE EXCEPTION 'Runtime executed DDL';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM billing.idempotency_records;
    RAISE EXCEPTION 'Runtime removed retained responses';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
SELECT 'Billing runtime permission checks passed' AS result;
