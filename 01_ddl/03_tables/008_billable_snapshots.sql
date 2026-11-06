-- Owner-local pre-invoice storage (ADR-015/ADR-017); no cross-owner foreign keys.
CREATE TABLE billing.encounter_accounts (
    encounter_account_id UUID PRIMARY KEY,
    clinical_record_id UUID NOT NULL,
    consultation_id UUID NOT NULL,
    appointment_id UUID NOT NULL,
    patient_id UUID NOT NULL,
    declared_procedure_ids UUID[] NOT NULL DEFAULT '{}',
    declared_manual_charge_ids UUID[] NOT NULL DEFAULT '{}',
    status VARCHAR(24) NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN','DECLARED','CHARGES_COMPLETED')),
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    freeze_state VARCHAR(6) NOT NULL DEFAULT 'OPEN' CHECK (freeze_state IN ('OPEN','FROZEN')),
    freeze_operation_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (clinical_record_id,consultation_id),
    UNIQUE (encounter_account_id,patient_id,appointment_id),
    CHECK ((freeze_state='OPEN' AND freeze_operation_id IS NULL)
        OR (freeze_state='FROZEN' AND freeze_operation_id IS NOT NULL))
);

CREATE TABLE billing.billable_items (
    item_id UUID PRIMARY KEY,
    encounter_account_id UUID NOT NULL,
    patient_id UUID NOT NULL,
    appointment_id UUID NOT NULL,
    procedure_id UUID NOT NULL,
    source_record_id UUID NOT NULL UNIQUE,
    item_type VARCHAR(32) NOT NULL CHECK (item_type IN ('BASE_PROCEDURE','ADDITIONAL_MATERIAL',
        'ADDITIONAL_PROCEDURE','COMPLEXITY_ADJUSTMENT','OTHER_AUTHORIZED_CHARGE')),
    description VARCHAR(500) NOT NULL CHECK (length(btrim(description)) > 0),
    -- Unconstrained NUMERIC rejects excess precision instead of typmod rounding it.
    quantity NUMERIC NOT NULL CHECK (quantity > 0 AND quantity < 'Infinity'::numeric
        AND scale(quantity) BETWEEN 0 AND 4),
    unit_price NUMERIC NOT NULL CHECK (unit_price > 0 AND unit_price < 1000000000000
        AND scale(unit_price) BETWEEN 0 AND 2),
    line_total NUMERIC(14,2) GENERATED ALWAYS AS (round(quantity * unit_price,2)) STORED,
    currency VARCHAR(3) NOT NULL DEFAULT 'COP' CHECK (currency='COP'),
    approval_required BOOLEAN NOT NULL DEFAULT FALSE,
    catalog_version INTEGER CHECK (catalog_version > 0),
    justification TEXT,
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    status VARCHAR(8) NOT NULL DEFAULT 'UNBILLED' CHECK (status IN ('UNBILLED','BILLED')),
    FOREIGN KEY (encounter_account_id,patient_id,appointment_id)
        REFERENCES billing.encounter_accounts (encounter_account_id,patient_id,appointment_id)
);
CREATE UNIQUE INDEX uq_billable_base_procedure ON billing.billable_items(procedure_id)
    WHERE item_type='BASE_PROCEDURE';
CREATE INDEX idx_billable_patient_created ON billing.billable_items(patient_id,created_at,item_id);
CREATE INDEX idx_billable_procedure_created ON billing.billable_items(procedure_id,created_at,item_id);
