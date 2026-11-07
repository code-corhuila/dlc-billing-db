-- The coordination gate also exists for encounters with no financial account yet.
CREATE TABLE billing.encounter_write_gates (
 clinical_record_id UUID NOT NULL,
 consultation_id UUID NOT NULL,
 freeze_state VARCHAR(6) NOT NULL DEFAULT 'OPEN' CHECK (freeze_state IN ('OPEN','FROZEN')),
 freeze_operation_id UUID,
 version INTEGER NOT NULL DEFAULT 1 CHECK (version>0),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(clinical_record_id,consultation_id),
 CHECK ((freeze_state='OPEN')=(freeze_operation_id IS NULL))
);
CREATE TABLE billing.encounter_freezes (
 clinical_record_id UUID NOT NULL,
 consultation_id UUID NOT NULL,
 operation_id UUID NOT NULL,
 state VARCHAR(9) NOT NULL DEFAULT 'ACTIVE' CHECK (state IN ('ACTIVE','RELEASED','COMMITTED')),
 settlement JSONB,
 PRIMARY KEY(clinical_record_id,consultation_id,operation_id),
 FOREIGN KEY(clinical_record_id,consultation_id) REFERENCES billing.encounter_write_gates
);
CREATE TABLE billing.manual_charge_admissions (
 operation_id UUID PRIMARY KEY,
 clinical_record_id UUID NOT NULL,
 consultation_id UUID NOT NULL,
 charge_id UUID NOT NULL UNIQUE,
 state VARCHAR(9) NOT NULL DEFAULT 'ADMITTED' CHECK (state IN ('ADMITTED','COMMITTED','ABORTED')),
 admitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 resolved_at TIMESTAMPTZ,
 FOREIGN KEY(clinical_record_id,consultation_id) REFERENCES billing.encounter_write_gates,
 CHECK ((state='ADMITTED')=(resolved_at IS NULL)),
 CHECK (resolved_at IS NULL OR resolved_at>=admitted_at)
);
CREATE FUNCTION billing.protect_charge_admission() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE gate billing.encounter_write_gates%ROWTYPE;
BEGIN
 IF TG_OP='INSERT' THEN
  SELECT * INTO gate FROM billing.encounter_write_gates
  WHERE clinical_record_id=NEW.clinical_record_id AND consultation_id=NEW.consultation_id FOR UPDATE;
  IF NOT FOUND OR gate.freeze_state<>'OPEN' OR NEW.state<>'ADMITTED' THEN
   RAISE EXCEPTION 'Encounter is frozen or unavailable' USING ERRCODE='23514';
  END IF;
 ELSE
  IF OLD.state<>'ADMITTED' OR NEW.state NOT IN ('COMMITTED','ABORTED')
  OR (to_jsonb(NEW)-ARRAY['state','resolved_at']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['state','resolved_at']) THEN
   RAISE EXCEPTION 'Admission is immutable' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_charge_admission BEFORE INSERT OR UPDATE ON billing.manual_charge_admissions
 FOR EACH ROW EXECUTE FUNCTION billing.protect_charge_admission();
CREATE FUNCTION billing.protect_encounter_gate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.version<>OLD.version+1 OR NEW.updated_at<OLD.updated_at OR NEW.freeze_state=OLD.freeze_state
 OR (to_jsonb(NEW)-ARRAY['freeze_state','freeze_operation_id','version','updated_at'])
 IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['freeze_state','freeze_operation_id','version','updated_at'])
 OR EXISTS(SELECT FROM billing.encounter_freezes WHERE clinical_record_id=OLD.clinical_record_id
  AND consultation_id=OLD.consultation_id AND state='COMMITTED') THEN
  RAISE EXCEPTION 'Encounter gate transition rejected' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_encounter_gate BEFORE UPDATE ON billing.encounter_write_gates
 FOR EACH ROW EXECUTE FUNCTION billing.protect_encounter_gate();
CREATE FUNCTION billing.protect_encounter_freeze() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.state<>'ACTIVE' OR NEW.state NOT IN ('RELEASED','COMMITTED')
 OR (to_jsonb(NEW)-ARRAY['state','settlement']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['state','settlement']) THEN
  RAISE EXCEPTION 'Freeze outcome is immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER protect_encounter_freeze BEFORE UPDATE ON billing.encounter_freezes
 FOR EACH ROW EXECUTE FUNCTION billing.protect_encounter_freeze();
REVOKE EXECUTE ON FUNCTION billing.protect_charge_admission(),billing.protect_encounter_gate(),billing.protect_encounter_freeze() FROM PUBLIC;
