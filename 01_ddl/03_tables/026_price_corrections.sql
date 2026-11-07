-- Narrow owner capability: runtime cannot directly rewrite prices or audit rows.
CREATE TABLE billing.price_corrections (
 correction_id UUID PRIMARY KEY,
 item_id UUID NOT NULL REFERENCES billing.billable_items(item_id),
 actor_id UUID NOT NULL,
 reason VARCHAR(1000) NOT NULL CHECK(length(btrim(reason))>0),
 previous_price NUMERIC NOT NULL,
 unit_price NUMERIC NOT NULL CHECK(unit_price>0 AND unit_price<1000000000000 AND scale(unit_price)=2),
 previous_version INTEGER NOT NULL CHECK(previous_version>0),
 corrected_at TIMESTAMPTZ NOT NULL,
 transaction_id BIGINT NOT NULL DEFAULT txid_current(),
 UNIQUE(item_id,previous_version)
);

CREATE OR REPLACE FUNCTION billing.protect_billable_allocation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.approval_required AND NOT NEW.approval_required
 AND OLD.status=NEW.status AND NEW.version=OLD.version+1 AND NEW.updated_at>=OLD.updated_at
 AND NOT EXISTS(SELECT FROM billing.manual_charges WHERE item_id=OLD.item_id)
 AND (to_jsonb(NEW)-ARRAY['unit_price','approval_required','version','updated_at','line_total'])
 IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['unit_price','approval_required','version','updated_at','line_total'])
 AND EXISTS(SELECT FROM billing.price_corrections c WHERE c.item_id=OLD.item_id
 AND c.previous_version=OLD.version AND c.previous_price=OLD.unit_price
 AND c.unit_price=NEW.unit_price AND c.corrected_at=NEW.updated_at AND c.transaction_id=txid_current())
 AND NOT EXISTS(SELECT FROM billing.invoice_items ii JOIN billing.invoices i USING(invoice_id)
 WHERE ii.item_id=OLD.item_id AND i.status<>'DRAFT') THEN RETURN NEW; END IF;
 IF OLD.status<>'UNBILLED' OR NEW.status<>'BILLED' OR NEW.version<>OLD.version+1
 OR NEW.updated_at<OLD.updated_at
 OR (to_jsonb(NEW)-ARRAY['status','version','updated_at','line_total'])
 IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','line_total']) THEN
  RAISE EXCEPTION 'Billable snapshot is immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION billing.protect_invoice_issuance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.version<>OLD.version+1 OR NEW.updated_at<OLD.updated_at THEN
  RAISE EXCEPTION 'Invalid invoice version' USING ERRCODE='23514'; END IF;
 IF OLD.status='DRAFT' AND NEW.status='DRAFT' AND NEW.balance=NEW.total
 AND NEW.total=(SELECT sum(b.line_total) FROM billing.invoice_items ii
 JOIN billing.billable_items b USING(item_id) WHERE ii.invoice_id=OLD.invoice_id)
 AND EXISTS(SELECT FROM billing.price_corrections c JOIN billing.invoice_items ii USING(item_id)
 WHERE ii.invoice_id=OLD.invoice_id AND c.transaction_id=txid_current() AND c.corrected_at=NEW.updated_at)
 AND (to_jsonb(NEW)-ARRAY['total','balance','version','updated_at'])
 IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['total','balance','version','updated_at']) THEN RETURN NEW; END IF;
 IF OLD.status='DRAFT' AND NEW.status='ISSUED' AND OLD.invoice_number IS NULL
 AND NEW.invoice_number IS NOT NULL AND NEW.issued_at>=OLD.created_at
 AND (to_jsonb(NEW)-ARRAY['status','version','updated_at','invoice_number','issued_at'])
 IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','invoice_number','issued_at']) THEN RETURN NEW; END IF;
 IF OLD.status IN ('ISSUED','PARTIALLY_PAID') AND NEW.status IN ('PARTIALLY_PAID','PAID')
 AND NEW.balance<OLD.balance
 AND NEW.balance=OLD.total-(SELECT COALESCE(sum(amount),0) FROM billing.payments WHERE invoice_id=OLD.invoice_id)
 AND (to_jsonb(NEW)-ARRAY['status','version','updated_at','balance'])
 IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at','balance']) THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'Invoice financial history is immutable' USING ERRCODE='23514';
END $$;

CREATE FUNCTION billing.correct_price(p_item UUID,p_actor UUID,p_price NUMERIC,p_reason TEXT,p_version INTEGER)
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
