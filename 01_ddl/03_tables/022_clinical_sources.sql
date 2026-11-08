CREATE TABLE billing.clinical_inbox (
 event_id UUID PRIMARY KEY,
 event_type VARCHAR(32) NOT NULL CHECK (event_type IN ('ProcedureCompleted','ConsultationRecorded','ClinicalCareCompleted')),
 event_hash CHAR(64) NOT NULL CHECK (event_hash ~ '^[0-9a-f]{64}$'),
 financial_fact JSONB NOT NULL,
 received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 projected_at TIMESTAMPTZ,
 CHECK ((financial_fact->>'eventId'=event_id::text AND financial_fact->>'eventType'=event_type
  AND jsonb_typeof(financial_fact->'payload')='object') IS TRUE),
 CHECK (NOT jsonb_path_exists(financial_fact,'$.**.clinicalReason')),
 CHECK (projected_at IS NULL OR projected_at>=received_at)
);
CREATE INDEX idx_clinical_inbox_pending ON billing.clinical_inbox(received_at,event_id) WHERE projected_at IS NULL;
CREATE TABLE billing.clinical_procedures (
 procedure_id UUID PRIMARY KEY,
 treatment_id UUID NOT NULL,
 patient_id UUID NOT NULL,
 appointment_id UUID NOT NULL,
 procedure_code TEXT NOT NULL CHECK (length(procedure_code)>0),
 completed_at TIMESTAMPTZ NOT NULL,
 fact_hash CHAR(64) NOT NULL CHECK (fact_hash ~ '^[0-9a-f]{64}$'),
 financial_fact JSONB NOT NULL
);
CREATE TABLE billing.clinical_sources (
 source_record_id UUID PRIMARY KEY,
 procedure_id UUID NOT NULL REFERENCES billing.clinical_procedures(procedure_id),
 item_type VARCHAR(32) NOT NULL CHECK (item_type IN ('BASE_PROCEDURE','ADDITIONAL_MATERIAL',
  'ADDITIONAL_PROCEDURE','COMPLEXITY_ADJUSTMENT','OTHER_AUTHORIZED_CHARGE')),
 quantity NUMERIC NOT NULL CHECK (quantity>0 AND quantity<'Infinity'::numeric AND scale(quantity)<=4),
 source_code TEXT
);
CREATE UNIQUE INDEX uq_clinical_base ON billing.clinical_sources(procedure_id) WHERE item_type='BASE_PROCEDURE';
CREATE INDEX idx_clinical_procedure_sources ON billing.clinical_sources(procedure_id,source_record_id);
CREATE TABLE billing.clinical_consultations (
 consultation_id UUID PRIMARY KEY,
 clinical_record_id UUID NOT NULL,
 patient_id UUID NOT NULL,
 appointment_id UUID,
 dentist_id UUID NOT NULL,
 recorded_at TIMESTAMPTZ NOT NULL,
 fact_hash CHAR(64) NOT NULL CHECK (fact_hash ~ '^[0-9a-f]{64}$'),
 financial_fact JSONB NOT NULL
);
CREATE INDEX idx_clinical_consultation_correlation ON billing.clinical_consultations(patient_id,appointment_id);
CREATE TABLE billing.clinical_declarations (
 clinical_record_id UUID NOT NULL,
 consultation_id UUID NOT NULL,
 patient_id UUID NOT NULL,
 appointment_id UUID NOT NULL,
 dentist_id UUID NOT NULL,
 procedure_ids UUID[] NOT NULL,
 manual_charge_ids UUID[] NOT NULL,
 completed_at TIMESTAMPTZ NOT NULL,
 clinical_version BIGINT NOT NULL CHECK (clinical_version>0),
 fact_hash CHAR(64) NOT NULL CHECK (fact_hash ~ '^[0-9a-f]{64}$'),
 financial_fact JSONB NOT NULL,
 PRIMARY KEY(clinical_record_id,consultation_id)
);
CREATE TABLE billing.procedure_charge_receipts (
 procedure_id UUID PRIMARY KEY REFERENCES billing.clinical_procedures(procedure_id),
 encounter_account_id UUID NOT NULL REFERENCES billing.encounter_accounts(encounter_account_id),
 event_id UUID NOT NULL UNIQUE,
 FOREIGN KEY(event_id,encounter_account_id) REFERENCES billing.outbox_events(event_id,aggregate_id)
);
CREATE TABLE billing.encounter_charge_receipts (
 encounter_account_id UUID PRIMARY KEY REFERENCES billing.encounter_accounts(encounter_account_id),
 event_id UUID NOT NULL UNIQUE,
 FOREIGN KEY(event_id,encounter_account_id) REFERENCES billing.outbox_events(event_id,aggregate_id)
);
CREATE FUNCTION billing.protect_clinical_inbox() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.projected_at IS NOT NULL OR NEW.projected_at IS NULL
 OR (to_jsonb(NEW)-'projected_at') IS DISTINCT FROM (to_jsonb(OLD)-'projected_at') THEN
  RAISE EXCEPTION 'Clinical inbox is immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_clinical_inbox BEFORE UPDATE ON billing.clinical_inbox
 FOR EACH ROW EXECUTE FUNCTION billing.protect_clinical_inbox();
REVOKE EXECUTE ON FUNCTION billing.protect_clinical_inbox() FROM PUBLIC;
