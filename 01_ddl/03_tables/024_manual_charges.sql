ALTER TABLE billing.clinical_procedures ADD CONSTRAINT uq_clinical_procedure_correlation
 UNIQUE(procedure_id,patient_id,appointment_id);
CREATE TABLE billing.manual_charges (
 charge_id UUID PRIMARY KEY,
 item_id UUID NOT NULL UNIQUE REFERENCES billing.billable_items(item_id),
 source_record_id UUID NOT NULL UNIQUE REFERENCES billing.clinical_sources(source_record_id),
 procedure_id UUID NOT NULL,
 patient_id UUID NOT NULL,
 appointment_id UUID NOT NULL,
 item_type VARCHAR(32) NOT NULL,
 quantity NUMERIC NOT NULL CHECK (quantity>0 AND quantity<'Infinity'::numeric AND scale(quantity)<=4),
 unit_price NUMERIC NOT NULL CHECK (unit_price>0 AND unit_price<1000000000000 AND scale(unit_price)<=2),
 currency VARCHAR(3) NOT NULL DEFAULT 'COP' CHECK(currency='COP'),
 concept VARCHAR(500) NOT NULL CHECK(length(btrim(concept))>0),
 justification VARCHAR(1000) NOT NULL CHECK(length(btrim(justification))>0),
 recorded_by UUID NOT NULL,
 authority_role VARCHAR(24) NOT NULL CHECK(authority_role IN ('DENTIST','ADMINISTRATOR')),
 recorded_at TIMESTAMPTZ NOT NULL,
 version INTEGER NOT NULL DEFAULT 1 CHECK(version=1),
 status VARCHAR(16) NOT NULL DEFAULT 'READY' CHECK(status IN ('READY','PENDING_CLINICAL')),
 CHECK(item_id=source_record_id),
 FOREIGN KEY(procedure_id,patient_id,appointment_id) REFERENCES billing.clinical_procedures(procedure_id,patient_id,appointment_id)
);
CREATE FUNCTION billing.protect_encounter_financial_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF current_user<>'billing_runtime' THEN RETURN NEW; END IF;
 IF NEW.version<>OLD.version+1 OR NEW.updated_at<OLD.updated_at THEN
  RAISE EXCEPTION 'Invalid encounter version' USING ERRCODE='23514';
 END IF;
 IF OLD.status='OPEN' AND NEW.status='DECLARED' AND NEW.freeze_state='FROZEN'
 AND (to_jsonb(NEW)-ARRAY['status','declared_procedure_ids','declared_manual_charge_ids','freeze_state','freeze_operation_id','version','updated_at'])
 IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','declared_procedure_ids','declared_manual_charge_ids','freeze_state','freeze_operation_id','version','updated_at'])
 AND EXISTS(SELECT FROM billing.clinical_declarations d JOIN billing.encounter_write_gates g
  ON g.clinical_record_id=d.clinical_record_id AND g.consultation_id=d.consultation_id
  WHERE d.clinical_record_id=NEW.clinical_record_id AND d.consultation_id=NEW.consultation_id
  AND d.patient_id=NEW.patient_id AND d.appointment_id=NEW.appointment_id
  AND d.procedure_ids=NEW.declared_procedure_ids AND d.manual_charge_ids=NEW.declared_manual_charge_ids
  AND g.freeze_state='FROZEN' AND g.freeze_operation_id=NEW.freeze_operation_id) THEN RETURN NEW; END IF;
 IF OLD.status='DECLARED' AND NEW.status='CHARGES_COMPLETED'
 AND (to_jsonb(NEW)-ARRAY['status','version','updated_at']) IS NOT DISTINCT FROM (to_jsonb(OLD)-ARRAY['status','version','updated_at'])
 AND NOT EXISTS(SELECT FROM unnest(OLD.declared_procedure_ids) AS p(id) WHERE NOT EXISTS
  (SELECT FROM billing.procedure_charge_receipts r WHERE r.procedure_id=p.id AND r.encounter_account_id=OLD.encounter_account_id))
 AND NOT EXISTS(SELECT FROM unnest(OLD.declared_manual_charge_ids) AS c(id) WHERE NOT EXISTS
  (SELECT FROM billing.manual_charges m JOIN billing.billable_items b ON b.item_id=m.item_id
   WHERE m.charge_id=c.id AND m.status='READY' AND b.encounter_account_id=OLD.encounter_account_id)) THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'Encounter financial state is immutable' USING ERRCODE='23514';
END $$;
CREATE TRIGGER protect_encounter_financial_transition BEFORE UPDATE ON billing.encounter_accounts
 FOR EACH ROW EXECUTE FUNCTION billing.protect_encounter_financial_transition();
CREATE FUNCTION billing.require_manual_charge_commit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF current_user='billing_runtime' AND NEW.state='COMMITTED' AND NOT EXISTS
 (SELECT FROM billing.manual_charges m JOIN billing.billable_items b ON b.item_id=m.item_id
  JOIN billing.encounter_accounts e ON e.encounter_account_id=b.encounter_account_id
  WHERE m.charge_id=NEW.charge_id AND e.clinical_record_id=NEW.clinical_record_id AND e.consultation_id=NEW.consultation_id) THEN
  RAISE EXCEPTION 'Admission has no committed charge' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER require_manual_charge_commit BEFORE UPDATE ON billing.manual_charge_admissions
 FOR EACH ROW EXECUTE FUNCTION billing.require_manual_charge_commit();
REVOKE EXECUTE ON FUNCTION billing.protect_encounter_financial_transition(),billing.require_manual_charge_commit() FROM PUBLIC;
