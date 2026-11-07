-- Preserve valid historical care-time prices; migration 026 remains unchanged.
CREATE OR REPLACE FUNCTION billing.correct_price(p_item UUID,p_actor UUID,p_price NUMERIC,p_reason TEXT,p_version INTEGER)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,billing AS $$
DECLARE b billing.billable_items; v_invoice UUID; v_current UUID; v_account UUID;
 v_status TEXT; v_now TIMESTAMPTZ; v_invoice_updated TIMESTAMPTZ;
BEGIN
 IF p_actor IS NULL OR p_price IS NULL OR p_price<=0 OR p_price>=1000000000000 OR scale(p_price)<>2
 OR p_reason IS NULL OR length(btrim(p_reason))=0 OR length(p_reason)>1000 OR p_version IS NULL OR p_version<1 THEN
  RAISE EXCEPTION 'Invalid correction' USING ERRCODE='22023'; END IF;
 -- Serialize against reconciliation before it computes durable financial totals.
 SELECT encounter_account_id INTO v_account FROM billing.billable_items WHERE item_id=p_item;
 PERFORM 1 FROM billing.encounter_accounts WHERE encounter_account_id=v_account FOR UPDATE;
 -- Issuance takes the invoice lock first. Recheck allocation after the item lock.
 SELECT invoice_id INTO v_invoice FROM billing.invoice_items WHERE item_id=p_item;
 IF v_invoice IS NOT NULL THEN
  SELECT status,updated_at INTO v_status,v_invoice_updated FROM billing.invoices WHERE invoice_id=v_invoice FOR UPDATE;
 END IF;
 SELECT * INTO b FROM billing.billable_items WHERE item_id=p_item FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Item not found' USING ERRCODE='P0002'; END IF;
 SELECT invoice_id INTO v_current FROM billing.invoice_items WHERE item_id=p_item;
 IF v_current IS DISTINCT FROM v_invoice OR (v_invoice IS NOT NULL AND v_status<>'DRAFT')
 OR (b.pricing_authority_role IN ('DENTIST','ADMINISTRATOR') AND length(btrim(b.justification))>0) IS TRUE
 OR b.version<>p_version OR NOT b.approval_required
 OR EXISTS(SELECT FROM billing.manual_charges WHERE item_id=p_item)
 OR round(b.quantity*p_price,2)>=1000000000000 THEN
  RAISE EXCEPTION 'Correction conflicts with current state' USING ERRCODE='40001'; END IF;
 v_now=greatest(clock_timestamp(),b.updated_at,v_invoice_updated);
 INSERT INTO billing.price_corrections(correction_id,item_id,actor_id,reason,previous_price,unit_price,previous_version,corrected_at)
 VALUES(gen_random_uuid(),p_item,p_actor,p_reason,b.unit_price,p_price,b.version,v_now);
 UPDATE billing.billable_items SET unit_price=p_price,approval_required=FALSE,version=version+1,updated_at=v_now WHERE item_id=p_item;
 IF v_invoice IS NOT NULL THEN
  UPDATE billing.invoices SET total=(SELECT sum(bi.line_total) FROM billing.invoice_items ii
   JOIN billing.billable_items bi USING(item_id) WHERE ii.invoice_id=v_invoice),
   balance=(SELECT sum(bi.line_total) FROM billing.invoice_items ii
   JOIN billing.billable_items bi USING(item_id) WHERE ii.invoice_id=v_invoice),
   version=version+1,updated_at=greatest(v_now,updated_at) WHERE invoice_id=v_invoice;
 END IF;
END $$;
REVOKE ALL ON FUNCTION billing.correct_price(UUID,UUID,NUMERIC,TEXT,INTEGER) FROM PUBLIC;
