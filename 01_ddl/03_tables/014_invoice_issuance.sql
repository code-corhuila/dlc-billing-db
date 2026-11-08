-- Recorded only by a validated owner pricing workflow, never from invoice HTTP input.
ALTER TABLE billing.billable_items ADD COLUMN pricing_authority_role VARCHAR(24)
    CHECK (pricing_authority_role IN ('DENTIST','ADMINISTRATOR'));
CREATE TABLE billing.outbox_events (
    event_id UUID PRIMARY KEY,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(80) NOT NULL CHECK (length(btrim(event_type))>0),
    event_version INTEGER NOT NULL CHECK (event_version>0),
    occurred_at TIMESTAMPTZ NOT NULL,
    event_body JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(event_id,aggregate_id),
    CHECK ((jsonb_typeof(event_body)='object'
        AND event_body->>'eventId'=event_id::text
        AND event_body->>'aggregateId'=aggregate_id::text
        AND event_body->>'eventType'=event_type
        AND event_body->>'version'=event_version::text
        AND event_body->>'producer'='billing-service'
        AND jsonb_typeof(event_body->'payload')='object'
        AND jsonb_typeof(event_body->'metadata')='object') IS TRUE)
);
CREATE INDEX idx_outbox_created ON billing.outbox_events(created_at,event_id);
CREATE TABLE billing.invoice_issuances (
    invoice_id UUID PRIMARY KEY REFERENCES billing.invoices(invoice_id),
    event_id UUID NOT NULL UNIQUE,
    issued_by UUID NOT NULL,
    invoice_version INTEGER NOT NULL CHECK (invoice_version>1),
    invoice_snapshot JSONB NOT NULL,
    FOREIGN KEY(event_id,invoice_id) REFERENCES billing.outbox_events(event_id,aggregate_id),
    CHECK ((jsonb_typeof(invoice_snapshot)='object'
        AND invoice_snapshot->>'id'=invoice_id::text
        AND invoice_snapshot->>'version'=invoice_version::text
        AND invoice_snapshot->>'status'='ISSUED') IS TRUE)
);
CREATE FUNCTION billing.protect_invoice_issuance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status<>'DRAFT' OR NEW.status<>'ISSUED' OR OLD.invoice_number IS NOT NULL
        OR NEW.invoice_number IS NULL OR NEW.issued_at IS NULL
        OR NEW.version<>OLD.version+1 OR NEW.updated_at<OLD.updated_at
        OR NEW.issued_at<OLD.created_at
        OR (to_jsonb(NEW)-ARRAY['status','version','updated_at','invoice_number','issued_at'])
            IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','invoice_number','issued_at']) THEN
        RAISE EXCEPTION 'Invoice issuance is immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER protect_invoice_issuance BEFORE UPDATE ON billing.invoices
    FOR EACH ROW EXECUTE FUNCTION billing.protect_invoice_issuance();
