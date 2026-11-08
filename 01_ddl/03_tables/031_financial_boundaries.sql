-- Forward correction for audit A01-A03. Existing invalid catalog values stop
-- deployment for owner investigation; historical money is never silently replaced.
ALTER TABLE billing.procedure_prices ADD CONSTRAINT chk_procedure_price_finite
 CHECK (base_price < 1000000000000);
ALTER TABLE billing.additional_price_rules ADD CONSTRAINT chk_additional_rule_finite
 CHECK (unit_price < 1000000000000);

CREATE FUNCTION billing.validate_invoice_item_allocation() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,billing AS $$
DECLARE invoice_status TEXT;
BEGIN
 -- Same row lock as issuance: allocation cannot race past its financial boundary.
 SELECT status INTO invoice_status FROM billing.invoices
 WHERE invoice_id=NEW.invoice_id FOR UPDATE;
 IF NOT FOUND OR invoice_status<>'DRAFT' THEN
  RAISE EXCEPTION 'Items can only be allocated to a draft invoice' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_invoice_item_allocation BEFORE INSERT ON billing.invoice_items
 FOR EACH ROW EXECUTE FUNCTION billing.validate_invoice_item_allocation();

CREATE FUNCTION billing.validate_invoice_financial_boundary() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,billing AS $$
DECLARE item_count BIGINT; item_total NUMERIC; all_billed BOOLEAN;
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'DRAFT' OR NEW.invoice_number IS NOT NULL OR NEW.issued_at IS NOT NULL THEN
   RAISE EXCEPTION 'Invoices must begin as drafts' USING ERRCODE='23514';
  END IF;
 ELSIF OLD.status='DRAFT' AND NEW.status='ISSUED' THEN
  -- UPDATE already holds the invoice lock. Snapshot values cannot change while
  -- issuing: ordinary updates are immutable and corrections lock this invoice too.
  SELECT count(*),sum(b.line_total),bool_and(b.status='BILLED')
   INTO item_count,item_total,all_billed
   FROM billing.invoice_items ii JOIN billing.billable_items b USING(item_id)
   WHERE ii.invoice_id=NEW.invoice_id;
  IF item_count=0 OR item_total IS DISTINCT FROM NEW.total OR all_billed IS NOT TRUE THEN
   RAISE EXCEPTION 'Invoice requires billed items matching its total' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER validate_invoice_financial_boundary BEFORE INSERT OR UPDATE ON billing.invoices
 FOR EACH ROW EXECUTE FUNCTION billing.validate_invoice_financial_boundary();
REVOKE EXECUTE ON FUNCTION billing.validate_invoice_item_allocation(),
 billing.validate_invoice_financial_boundary() FROM PUBLIC;

-- Trigger creation has locked both tables against concurrent writes. Do not
-- certify a deployment whose existing issued history already violates the rule.
DO $$ BEGIN
 IF EXISTS (
  SELECT FROM billing.invoices i LEFT JOIN billing.invoice_items ii USING(invoice_id)
  LEFT JOIN billing.billable_items b USING(item_id)
  WHERE i.status IN ('ISSUED','PARTIALLY_PAID','PAID') GROUP BY i.invoice_id
  HAVING count(b.item_id)=0 OR sum(b.line_total)<>i.total OR bool_and(b.status='BILLED') IS NOT TRUE
 ) THEN
  RAISE EXCEPTION 'Existing issued invoice history requires owner reconciliation'
   USING ERRCODE='23514';
 END IF;
END $$;
