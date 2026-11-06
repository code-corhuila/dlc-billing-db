REVOKE ALL ON billing.procedure_prices, billing.additional_price_rules,
    billing.idempotency_records FROM billing_runtime;
REVOKE USAGE ON SCHEMA billing FROM billing_runtime;
