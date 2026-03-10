INSERT INTO customers (external_customer_id, email, full_name, tier)
VALUES
  ('cust-demo-001', 'alice.demo@example.com', 'Alice Demo', 'STANDARD'),
  ('cust-demo-002', 'bob.demo@example.com', 'Bob Demo', 'PREMIUM'),
  ('cust-demo-003', 'charlie.demo@example.com', 'Charlie Demo', 'VIP')
ON CONFLICT (external_customer_id) DO NOTHING;
