-- Drasi continuous queries (Cypher syntax)
-- These are defined in drasi-server-config.yaml; kept here for reference.

-- 1. Unfiltered: captures all order changes (benchmark parity with wal2json/debezium)
-- MATCH (o:orders)
-- RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount,
--        o.status AS status, o.updated_at AS updated_at

-- 2. Filtered: high-value paid/shipped orders (demonstrates Drasi filtering)
-- MATCH (o:orders)
-- WHERE o.amount >= 500 AND o.status IN ['PAID', 'SHIPPED']
-- RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount,
--        o.status AS status, o.updated_at AS updated_at
