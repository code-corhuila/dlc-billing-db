-- MVP-SPEC PaymentMethod codes. Internal recording only; no payment provider integration.
-- Preserve owner configuration, including deliberately disabled methods.
INSERT INTO billing.payment_methods(method,active) VALUES
 ('CASH',true),
 ('CREDIT_CARD',true),
 ('DEBIT_CARD',true),
 ('BANK_TRANSFER',true),
 ('NEQUI_DAVIPLATA',true),
 ('OTHER',true)
ON CONFLICT(method) DO NOTHING;
