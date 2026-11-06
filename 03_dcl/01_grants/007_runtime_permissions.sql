REVOKE ALL ON ALL TABLES IN SCHEMA billing FROM billing_runtime;
GRANT USAGE ON SCHEMA billing TO billing_runtime;
GRANT SELECT, INSERT ON billing.procedure_prices, billing.additional_price_rules,
    billing.idempotency_records TO billing_runtime;
GRANT UPDATE (valid_to, updated_at) ON billing.procedure_prices,
    billing.additional_price_rules TO billing_runtime;
