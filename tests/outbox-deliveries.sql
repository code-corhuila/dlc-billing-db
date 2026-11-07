\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.outbox_events(event_id,aggregate_id,event_type,event_version,occurred_at,event_body)
SELECT '72000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000002','InvoiceIssued',1,now(),
jsonb_build_object('eventId','72000000-0000-4000-8000-000000000001','aggregateId','72000000-0000-4000-8000-000000000002',
'eventType','InvoiceIssued','version',1,'producer','billing-service','payload','{}'::jsonb,'metadata','{}'::jsonb);
DO $$ BEGIN
  IF (SELECT count(*) FROM billing.outbox_deliveries WHERE event_id='72000000-0000-4000-8000-000000000001'
      AND status='PENDING' AND attempts=0)<>1 THEN RAISE EXCEPTION 'Publication intent not scheduled'; END IF;
END $$;
SELECT event_id FROM billing.outbox_deliveries WHERE event_id='72000000-0000-4000-8000-000000000001' FOR UPDATE SKIP LOCKED;
UPDATE billing.outbox_deliveries SET attempts=1,last_error_code='BROKER_UNAVAILABLE',next_attempt_at=now()+interval '5 seconds'
WHERE event_id='72000000-0000-4000-8000-000000000001';
UPDATE billing.outbox_deliveries SET status='PUBLISHED',attempts=2,published_at=now(),next_attempt_at=NULL,last_error_code=NULL
WHERE event_id='72000000-0000-4000-8000-000000000001';
DO $$ BEGIN
  BEGIN
    UPDATE billing.outbox_events SET event_body='{}'; RAISE EXCEPTION 'Event rewritten';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM billing.outbox_deliveries; RAISE EXCEPTION 'Delivery history deleted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE billing.outbox_deliveries SET event_id=gen_random_uuid(); RAISE EXCEPTION 'Delivery identity changed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE billing.outbox_deliveries SET status='PENDING',published_at=NULL; RAISE EXCEPTION 'Published event reopened';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;
