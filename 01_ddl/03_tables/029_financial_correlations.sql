-- Preserve existing migrations and reject mismatched financial evidence.
ALTER TABLE billing.payments ADD CONSTRAINT uq_payment_invoice UNIQUE(payment_id,invoice_id);
ALTER TABLE billing.payment_receipts ADD CONSTRAINT fk_receipt_payment_invoice
 FOREIGN KEY(payment_id,invoice_id) REFERENCES billing.payments(payment_id,invoice_id);

CREATE FUNCTION billing.validate_manual_charge_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS (
  SELECT FROM billing.billable_items b JOIN billing.clinical_sources s
   ON s.source_record_id=b.source_record_id
  WHERE b.item_id=NEW.item_id AND b.source_record_id=NEW.source_record_id
   AND b.procedure_id=NEW.procedure_id AND b.patient_id=NEW.patient_id
   AND b.appointment_id=NEW.appointment_id AND b.item_type=NEW.item_type
   AND b.quantity=NEW.quantity AND b.unit_price=NEW.unit_price AND b.currency=NEW.currency
   AND b.description=NEW.concept AND b.justification=NEW.justification
   AND b.created_by=NEW.recorded_by AND b.pricing_authority_role=NEW.authority_role
   AND b.created_at=NEW.recorded_at AND NOT b.approval_required
   AND s.procedure_id=NEW.procedure_id AND s.item_type=NEW.item_type AND s.quantity=NEW.quantity
 ) THEN
  RAISE EXCEPTION 'Manual charge does not match its financial and clinical source'
   USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_manual_charge_snapshot BEFORE INSERT ON billing.manual_charges
 FOR EACH ROW EXECUTE FUNCTION billing.validate_manual_charge_snapshot();
REVOKE EXECUTE ON FUNCTION billing.validate_manual_charge_snapshot() FROM PUBLIC;
