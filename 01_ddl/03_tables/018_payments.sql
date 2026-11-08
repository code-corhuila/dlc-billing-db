CREATE TABLE billing.payment_methods (
 method VARCHAR(40) PRIMARY KEY CHECK (length(btrim(method))>0),
 active BOOLEAN NOT NULL DEFAULT true
);
CREATE TABLE billing.payments (
 payment_id UUID PRIMARY KEY,
 invoice_id UUID NOT NULL REFERENCES billing.invoices(invoice_id),
 amount NUMERIC NOT NULL CHECK (amount>0 AND amount<1000000000000 AND scale(amount)<=2),
 method VARCHAR(40) NOT NULL REFERENCES billing.payment_methods(method),
 recorded_by UUID NOT NULL,
 recorded_at TIMESTAMPTZ NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 version INTEGER NOT NULL DEFAULT 1 CHECK (version=1)
);
CREATE INDEX idx_payment_invoice_created ON billing.payments(invoice_id,created_at,payment_id);
CREATE FUNCTION billing.validate_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE invoice billing.invoices%ROWTYPE;
BEGIN
 SELECT * INTO invoice FROM billing.invoices WHERE invoice_id=NEW.invoice_id FOR UPDATE;
 IF NOT FOUND OR invoice.status NOT IN ('ISSUED','PARTIALLY_PAID') OR NEW.amount>invoice.balance
 OR invoice.version=2147483647 OR NEW.recorded_at<invoice.issued_at THEN
  RAISE EXCEPTION 'Invoice not payable' USING ERRCODE='23514';
 END IF;
 PERFORM FROM billing.payment_methods WHERE method=NEW.method AND active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment method unavailable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_payment BEFORE INSERT ON billing.payments
 FOR EACH ROW EXECUTE FUNCTION billing.validate_payment();
-- Forward extension of 014; issued identities and source amounts stay immutable.
CREATE OR REPLACE FUNCTION billing.protect_invoice_issuance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.version<>OLD.version+1 OR NEW.updated_at<OLD.updated_at THEN
  RAISE EXCEPTION 'Invalid invoice version' USING ERRCODE='23514';
 END IF;
 IF OLD.status='DRAFT' AND NEW.status='ISSUED' AND OLD.invoice_number IS NULL
 AND NEW.invoice_number IS NOT NULL AND NEW.issued_at>=OLD.created_at
 AND (to_jsonb(NEW)-ARRAY['status','version','updated_at','invoice_number','issued_at'])
 IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','invoice_number','issued_at']) THEN
  RETURN NEW;
 END IF;
 IF OLD.status IN ('ISSUED','PARTIALLY_PAID') AND NEW.status IN ('PARTIALLY_PAID','PAID')
 AND NEW.balance<OLD.balance
 AND NEW.balance=OLD.total-(SELECT COALESCE(sum(amount),0) FROM billing.payments WHERE invoice_id=OLD.invoice_id)
 AND (to_jsonb(NEW)-ARRAY['status','version','updated_at','balance'])
 IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','balance']) THEN
  RETURN NEW;
 END IF;
 RAISE EXCEPTION 'Invoice financial history is immutable' USING ERRCODE='23514';
END $$;
CREATE FUNCTION billing.apply_payment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE billing.invoices SET balance=balance-NEW.amount,
 status=CASE WHEN balance=NEW.amount THEN 'PAID' ELSE 'PARTIALLY_PAID' END,
 version=version+1,updated_at=NEW.recorded_at WHERE invoice_id=NEW.invoice_id;
 RETURN NEW;
END $$;
CREATE TRIGGER apply_payment AFTER INSERT ON billing.payments
 FOR EACH ROW EXECUTE FUNCTION billing.apply_payment();
REVOKE EXECUTE ON FUNCTION billing.validate_payment(),billing.apply_payment() FROM PUBLIC;
CREATE TABLE billing.payment_receipts (
 payment_id UUID PRIMARY KEY REFERENCES billing.payments(payment_id),
 event_id UUID NOT NULL UNIQUE,
 invoice_id UUID NOT NULL,
 invoice_version INTEGER NOT NULL CHECK (invoice_version>2),
 invoice_snapshot JSONB NOT NULL,
 FOREIGN KEY(event_id,invoice_id) REFERENCES billing.outbox_events(event_id,aggregate_id),
 CHECK ((invoice_snapshot->>'id'=invoice_id::text
  AND invoice_snapshot->>'version'=invoice_version::text
  AND invoice_snapshot->>'status' IN ('PARTIALLY_PAID','PAID')) IS TRUE)
);

