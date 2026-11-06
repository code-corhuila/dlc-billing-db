CREATE TABLE billing.invoices (
    invoice_id UUID PRIMARY KEY,
    patient_id UUID NOT NULL,
    appointment_id UUID,
    invoice_number VARCHAR(80) UNIQUE CHECK (length(btrim(invoice_number)) > 0),
    issued_at TIMESTAMPTZ,
    total NUMERIC(14,2) NOT NULL CHECK (total >= 0 AND total < 'Infinity'::numeric),
    balance NUMERIC(14,2) NOT NULL CHECK (balance >= 0 AND balance <= total),
    currency VARCHAR(3) NOT NULL DEFAULT 'COP' CHECK (currency='COP'),
    status VARCHAR(16) NOT NULL DEFAULT 'DRAFT'
        CHECK (status IN ('DRAFT','ISSUED','PARTIALLY_PAID','PAID','CANCELLED')),
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    created_by UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (invoice_id,patient_id),
    CHECK ((invoice_number IS NULL) = (issued_at IS NULL)),
    CHECK (status NOT IN ('ISSUED','PARTIALLY_PAID','PAID') OR issued_at IS NOT NULL),
    CHECK (status <> 'DRAFT' OR balance=total),
    CHECK (status <> 'ISSUED' OR balance=total),
    CHECK (status <> 'PARTIALLY_PAID' OR (balance > 0 AND balance < total)),
    CHECK (status <> 'PAID' OR balance=0)
);
ALTER TABLE billing.billable_items ADD CONSTRAINT uq_billable_item_patient UNIQUE (item_id,patient_id);
CREATE TABLE billing.invoice_items (
    invoice_id UUID NOT NULL,
    patient_id UUID NOT NULL,
    item_id UUID NOT NULL UNIQUE,
    PRIMARY KEY (invoice_id,item_id),
    FOREIGN KEY (invoice_id,patient_id) REFERENCES billing.invoices(invoice_id,patient_id),
    FOREIGN KEY (item_id,patient_id) REFERENCES billing.billable_items(item_id,patient_id)
);
CREATE INDEX idx_invoice_patient_created ON billing.invoices(patient_id,created_at,invoice_id);
