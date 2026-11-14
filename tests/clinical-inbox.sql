\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE billing_runtime;
INSERT INTO billing.clinical_inbox(event_id,event_type,event_hash,financial_fact)
VALUES ('84000000-0000-4000-8000-000000000001','ProcedureCompleted',repeat('a',64),
'{"eventId":"84000000-0000-4000-8000-000000000001","eventType":"ProcedureCompleted","payload":{}}');
DO $$ BEGIN
 BEGIN
 UPDATE billing.clinical_inbox SET financial_fact='{}';
 RAISE EXCEPTION 'Inbox fact rewritten'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
 DELETE FROM billing.clinical_inbox;
 RAISE EXCEPTION 'Inbox audit deleted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
 INSERT INTO billing.clinical_inbox SELECT * FROM billing.clinical_inbox;
 RAISE EXCEPTION 'Duplicate event accepted'; EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
ROLLBACK;
