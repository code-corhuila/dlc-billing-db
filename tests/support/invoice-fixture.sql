-- Test-only fixture: use real billed items instead of issuing empty invoices.
CREATE OR REPLACE FUNCTION pg_temp.seed_invoice_items(p_invoice UUID) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE invoice billing.invoices; account UUID=gen_random_uuid(); item UUID=gen_random_uuid();
 appointment UUID;
BEGIN
 SELECT * INTO STRICT invoice FROM billing.invoices WHERE invoice_id=p_invoice;
 appointment=COALESCE(invoice.appointment_id,gen_random_uuid());
 INSERT INTO billing.encounter_accounts(encounter_account_id,clinical_record_id,consultation_id,patient_id,appointment_id)
 VALUES(account,gen_random_uuid(),gen_random_uuid(),invoice.patient_id,appointment);
 INSERT INTO billing.billable_items(item_id,encounter_account_id,patient_id,appointment_id,procedure_id,source_record_id,
 item_type,description,quantity,unit_price,created_by,status,catalog_version)
 VALUES(item,account,invoice.patient_id,appointment,gen_random_uuid(),gen_random_uuid(),
 'BASE_PROCEDURE','Synthetic billed invoice fixture',1,invoice.total,invoice.created_by,'BILLED',1);
 INSERT INTO billing.invoice_items(invoice_id,patient_id,item_id) VALUES(p_invoice,invoice.patient_id,item);
END $$;
