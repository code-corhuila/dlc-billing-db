CREATE TABLE billing.invoice_appointment_validations (
    invoice_id UUID NOT NULL,
    appointment_id UUID NOT NULL,
    patient_id UUID NOT NULL,
    appointment_version BIGINT NOT NULL CHECK (appointment_version > 0),
    validated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (invoice_id,appointment_id),
    FOREIGN KEY (invoice_id,patient_id) REFERENCES billing.invoices(invoice_id,patient_id)
);
CREATE FUNCTION billing.protect_billable_allocation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Generated line_total is recomputed after BEFORE triggers; its inputs stay immutable.
    IF OLD.status <> 'UNBILLED' OR NEW.status <> 'BILLED' OR NEW.version <> OLD.version + 1
        OR NEW.updated_at < OLD.updated_at
        OR (to_jsonb(NEW) - ARRAY['status','version','updated_at','line_total'])
            IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status','version','updated_at','line_total']) THEN
        RAISE EXCEPTION 'Billable snapshot is immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER protect_billable_allocation BEFORE UPDATE ON billing.billable_items
    FOR EACH ROW EXECUTE FUNCTION billing.protect_billable_allocation();
