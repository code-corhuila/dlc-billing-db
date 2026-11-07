CREATE TABLE billing.outbox_deliveries (
    event_id UUID PRIMARY KEY REFERENCES billing.outbox_events(event_id) ON DELETE CASCADE,
    status VARCHAR(9) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PUBLISHED','FAILED')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 10),
    next_attempt_at TIMESTAMPTZ,
    published_at TIMESTAMPTZ,
    last_error_code VARCHAR(32) CHECK (last_error_code='BROKER_UNAVAILABLE'),
    CHECK ((status='PENDING' AND attempts<10 AND published_at IS NULL
               AND ((attempts=0 AND next_attempt_at IS NULL AND last_error_code IS NULL)
                 OR (attempts>0 AND next_attempt_at IS NOT NULL AND last_error_code IS NOT NULL)))
        OR (status='PUBLISHED' AND attempts>0 AND published_at IS NOT NULL
               AND next_attempt_at IS NULL AND last_error_code IS NULL)
        OR (status='FAILED' AND attempts=10 AND published_at IS NULL
               AND next_attempt_at IS NULL AND last_error_code IS NOT NULL))
);
CREATE INDEX idx_outbox_delivery_due ON billing.outbox_deliveries(next_attempt_at,event_id) WHERE status='PENDING';
CREATE FUNCTION billing.schedule_outbox_delivery() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO billing.outbox_deliveries(event_id) VALUES (NEW.event_id);
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION billing.schedule_outbox_delivery() FROM PUBLIC;
CREATE TRIGGER schedule_outbox_delivery AFTER INSERT ON billing.outbox_events
    FOR EACH ROW EXECUTE FUNCTION billing.schedule_outbox_delivery();
-- Include committed events predating this additive migration.
INSERT INTO billing.outbox_deliveries(event_id) SELECT event_id FROM billing.outbox_events;
CREATE FUNCTION billing.protect_outbox_delivery() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status<>'PENDING' OR NEW.event_id<>OLD.event_id OR NEW.attempts<>OLD.attempts+1 THEN
        RAISE EXCEPTION 'Delivery identity or completed result is immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION billing.protect_outbox_delivery() FROM PUBLIC;
CREATE TRIGGER protect_outbox_delivery BEFORE UPDATE ON billing.outbox_deliveries
    FOR EACH ROW EXECUTE FUNCTION billing.protect_outbox_delivery();
