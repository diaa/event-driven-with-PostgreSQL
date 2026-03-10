-- Example Drasi-style filtering intent (adapt as required by actual Drasi runtime syntax)
SELECT
  id,
  customer_id,
  amount,
  status,
  updated_at
FROM orders
WHERE amount >= 500
  AND status IN ('PAID', 'SHIPPED');
