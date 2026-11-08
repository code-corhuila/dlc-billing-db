\set ON_ERROR_STOP on
BEGIN;
\ir support/invoice-fixture.sql
SET LOCAL ROLE billing_runtime;
DO $$
DECLARE patient UUID=gen_random_uuid(); appointment UUID=gen_random_uuid();
 procedure UUID=gen_random_uuid(); source UUID=gen_random_uuid(); actor UUID=gen_random_uuid();
 account UUID=gen_random_uuid(); stamp TIMESTAMPTZ=now();
 sample billing.manual_charges; field TEXT;
BEGIN
 INSERT INTO billing.encounter_accounts(encounter_account_id,clinical_record_id,consultation_id,patient_id,appointment_id)
 VALUES(account,gen_random_uuid(),gen_random_uuid(),patient,appointment);
 INSERT INTO billing.clinical_procedures(procedure_id,treatment_id,patient_id,appointment_id,procedure_code,completed_at,fact_hash,financial_fact)
 VALUES(procedure,gen_random_uuid(),patient,appointment,'TEST',stamp,repeat('a',64),'{}');
 INSERT INTO billing.clinical_sources(source_record_id,procedure_id,item_type,quantity)
 VALUES(source,procedure,'ADDITIONAL_MATERIAL',1.2500);
 INSERT INTO billing.billable_items(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
 item_type,description,quantity,unit_price,justification,created_by,pricing_authority_role,created_at,updated_at)
 VALUES(source,account,patient,appointment,procedure,source,'ADDITIONAL_MATERIAL','Entered concept',1.2500,10.00,
 'Care justification',actor,'DENTIST',stamp,stamp);
 sample.charge_id=gen_random_uuid(); sample.item_id=source; sample.source_record_id=source;
 sample.procedure_id=procedure; sample.patient_id=patient; sample.appointment_id=appointment;
 sample.item_type='ADDITIONAL_MATERIAL'; sample.quantity=1.2500; sample.unit_price=10.00; sample.currency='COP';
 sample.concept='Entered concept'; sample.justification='Care justification'; sample.recorded_by=actor;
 sample.authority_role='DENTIST'; sample.recorded_at=stamp; sample.version=1; sample.status='READY';
 FOREACH field IN ARRAY ARRAY['unit_price','quantity','concept','justification','recorded_by','authority_role','recorded_at','item_type'] LOOP
  BEGIN
   INSERT INTO billing.manual_charges SELECT (jsonb_populate_record(sample,jsonb_build_object(field,
    CASE field WHEN 'unit_price' THEN '11.00' WHEN 'quantity' THEN '2' WHEN 'concept' THEN 'Changed'
    WHEN 'justification' THEN 'Changed reason' WHEN 'recorded_by' THEN gen_random_uuid()::text
    WHEN 'authority_role' THEN 'ADMINISTRATOR' WHEN 'recorded_at' THEN (stamp+interval '1 second')::text
    ELSE 'OTHER_AUTHORIZED_CHARGE' END))).*;
   RAISE EXCEPTION 'Mismatched % accepted',field;
  EXCEPTION WHEN check_violation THEN NULL; END;
 END LOOP;
 INSERT INTO billing.manual_charges SELECT sample.*;
 IF NOT EXISTS(SELECT FROM billing.manual_charges WHERE charge_id=sample.charge_id) THEN
  RAISE EXCEPTION 'Valid manual snapshot missing'; END IF;
END $$;
RESET ROLE;
DO $$
DECLARE patient UUID=gen_random_uuid(); a UUID=gen_random_uuid(); b UUID=gen_random_uuid();
 payment UUID=gen_random_uuid(); event UUID=gen_random_uuid(); actor UUID=gen_random_uuid();
BEGIN
 INSERT INTO billing.payment_methods(method) VALUES('CORRELATION_TEST');
 INSERT INTO billing.invoices(invoice_id,patient_id,total,balance,created_by)
 VALUES(a,patient,10,10,actor),(b,patient,10,10,actor);
 PERFORM pg_temp.seed_invoice_items(a);
 PERFORM pg_temp.seed_invoice_items(b);
 UPDATE billing.invoices SET status='ISSUED',invoice_number=invoice_id::text,issued_at=now(),version=2
 WHERE invoice_id IN(a,b);
 SET LOCAL ROLE billing_runtime;
 INSERT INTO billing.payments(payment_id,invoice_id,amount,method,recorded_by,recorded_at)
 VALUES(payment,a,1,'CORRELATION_TEST',actor,now());
 INSERT INTO billing.outbox_events(event_id,aggregate_id,event_type,event_version,occurred_at,event_body)
 VALUES(event,b,'PaymentRecorded',1,now(),jsonb_build_object('eventId',event,'aggregateId',b,
 'eventType','PaymentRecorded','version',1,'producer','billing-service','payload','{}'::jsonb,'metadata','{}'::jsonb));
 BEGIN
  INSERT INTO billing.payment_receipts(payment_id,event_id,invoice_id,invoice_version,invoice_snapshot)
  VALUES(payment,event,b,3,jsonb_build_object('id',b,'version',3,'status','PARTIALLY_PAID'));
  RAISE EXCEPTION 'Receipt for a different payment invoice accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 event=gen_random_uuid();
 INSERT INTO billing.outbox_events(event_id,aggregate_id,event_type,event_version,occurred_at,event_body)
 VALUES(event,a,'PaymentRecorded',1,now(),jsonb_build_object('eventId',event,'aggregateId',a,
 'eventType','PaymentRecorded','version',1,'producer','billing-service','payload','{}'::jsonb,'metadata','{}'::jsonb));
 INSERT INTO billing.payment_receipts(payment_id,event_id,invoice_id,invoice_version,invoice_snapshot)
 VALUES(payment,event,a,3,jsonb_build_object('id',a,'version',3,'status','PARTIALLY_PAID'));
END $$;
ROLLBACK;
