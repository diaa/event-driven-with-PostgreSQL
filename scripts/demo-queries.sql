-- =============================================================
-- Demo Queries — run these between scenarios to show progress
-- Usage: psql "$DATABASE_URL" -f scripts/demo-queries.sql
--   or copy-paste individual sections
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. DATABASE STRUCTURE — show the schema to the audience
-- ─────────────────────────────────────────────────────────────

\echo ''
\echo '══════════════════════════════════════════════'
\echo '  DATABASE STRUCTURE'
\echo '══════════════════════════════════════════════'

\echo ''
\echo '── Tables ──'
SELECT table_name, pg_size_pretty(pg_relation_size(quote_ident(table_name)))  AS size
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;

\echo ''
\echo '── Orders table (where traffic lands) ──'
SELECT column_name, data_type,
       CASE WHEN character_maximum_length IS NOT NULL
            THEN data_type || '(' || character_maximum_length || ')'
            ELSE data_type END AS full_type,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'orders'
ORDER BY ordinal_position;

\echo ''
\echo '── Check constraints (valid statuses & amounts) ──'
SELECT conname AS constraint_name,
       pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'orders'::regclass AND contype = 'c';

\echo ''
\echo '── Benchmark events table (where CDC consumers write) ──'
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'benchmark_events'
ORDER BY ordinal_position;

-- ─────────────────────────────────────────────────────────────
-- 2. CDC INFRASTRUCTURE — publications, slots, wal_level
-- ─────────────────────────────────────────────────────────────

\echo ''
\echo '══════════════════════════════════════════════'
\echo '  CDC INFRASTRUCTURE'
\echo '══════════════════════════════════════════════'

\echo ''
\echo '── WAL level ──'
SHOW wal_level;

\echo ''
\echo '── Publications ──'
SELECT pubname, puballtables,
       string_agg(tablename, ', ') AS tables
FROM pg_publication p
LEFT JOIN pg_publication_tables pt ON p.pubname = pt.pubname
GROUP BY p.pubname, p.puballtables;

\echo ''
\echo '── Replication slots ──'
SELECT slot_name, plugin, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_lag
FROM pg_replication_slots
ORDER BY slot_name;

-- ─────────────────────────────────────────────────────────────
-- 3. LIVE ORDER ACTIVITY — recent orders in the source table
-- ─────────────────────────────────────────────────────────────

\echo ''
\echo '══════════════════════════════════════════════'
\echo '  RECENT ORDERS (source table)'
\echo '══════════════════════════════════════════════'

\echo ''
\echo '── Last 10 orders ──'
SELECT id, customer_id, amount, status, created_at
FROM orders
ORDER BY id DESC
LIMIT 10;

\echo ''
\echo '── Order counts by status ──'
SELECT status, count(*) AS total,
       round(avg(amount)::numeric, 2) AS avg_amount,
       round(min(amount)::numeric, 2) AS min_amount,
       round(max(amount)::numeric, 2) AS max_amount
FROM orders
GROUP BY status
ORDER BY status;

\echo ''
\echo '── High-value orders (amount >= 500, PAID/SHIPPED) — the Drasi filter ──'
SELECT count(*) AS high_value_count,
       (SELECT count(*) FROM orders) AS total_orders,
       round(100.0 * count(*) / GREATEST((SELECT count(*) FROM orders), 1), 1) AS pct
FROM orders
WHERE amount >= 500 AND status IN ('PAID', 'SHIPPED');

-- ─────────────────────────────────────────────────────────────
-- 4. BENCHMARK RESULTS — what each CDC approach captured
-- ─────────────────────────────────────────────────────────────

\echo ''
\echo '══════════════════════════════════════════════'
\echo '  BENCHMARK RESULTS (benchmark_events table)'
\echo '══════════════════════════════════════════════'

\echo ''
\echo '── Events per approach ──'
SELECT approach,
       count(*) AS total_events,
       count(*) FILTER (WHERE notes LIKE '%filtered%') AS filtered_events,
       count(*) FILTER (WHERE notes NOT LIKE '%filtered%') AS unfiltered_events
FROM benchmark_events
GROUP BY approach
ORDER BY approach;

\echo ''
\echo '── Latency summary (from the built-in view) ──'
SELECT * FROM vw_benchmark_latency_summary;

\echo ''
\echo '── Last 5 captured events per approach ──'
SELECT approach, source_event_id, operation,
       round(latency_ms::numeric, 2) AS latency_ms,
       notes
FROM (
  SELECT *, row_number() OVER (PARTITION BY approach ORDER BY observed_at DESC) AS rn
  FROM benchmark_events
) ranked
WHERE rn <= 5
ORDER BY approach, rn;

-- ─────────────────────────────────────────────────────────────
-- 5. DRASI FILTERING — the key differentiator
-- ─────────────────────────────────────────────────────────────

\echo ''
\echo '══════════════════════════════════════════════'
\echo '  DRASI FILTERING RESULTS'
\echo '══════════════════════════════════════════════'

\echo ''
\echo '── Filtered (high-value orders) vs all events ──'
SELECT
  CASE WHEN notes LIKE '%filtered%' THEN 'drasi-filtered' ELSE approach END AS label,
  count(*) AS events,
  round(avg(latency_ms)::numeric, 2) AS avg_latency_ms,
  round(percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p50_ms,
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p95_ms
FROM benchmark_events
WHERE approach = 'drasi'
GROUP BY label
ORDER BY label;

\echo ''
\echo '── Sample filtered events (Drasi high-value orders) ──'
SELECT source_event_id, operation,
       round(latency_ms::numeric, 2) AS latency_ms,
       observed_at, notes
FROM benchmark_events
WHERE notes LIKE '%filtered%'
ORDER BY observed_at DESC
LIMIT 10;

\echo ''
\echo '── Key insight: wal2json and debezium have ZERO filtered rows ──'
SELECT approach,
       count(*) FILTER (WHERE notes LIKE '%filtered%') AS filtered_rows,
       count(*) FILTER (WHERE notes NOT LIKE '%filtered%') AS unfiltered_rows
FROM benchmark_events
GROUP BY approach
ORDER BY approach;

-- ─────────────────────────────────────────────────────────────
-- 6. SIDE-BY-SIDE COMPARISON — the money shot
-- ─────────────────────────────────────────────────────────────

\echo ''
\echo '══════════════════════════════════════════════'
\echo '  SIDE-BY-SIDE COMPARISON'
\echo '══════════════════════════════════════════════'

SELECT
  approach,
  count(*) FILTER (WHERE notes NOT LIKE '%filtered%') AS raw_events,
  count(*) FILTER (WHERE notes LIKE '%filtered%') AS filtered_events,
  count(*) AS total_captured,
  round(avg(latency_ms) FILTER (WHERE notes NOT LIKE '%filtered%')::numeric, 2) AS avg_ms,
  round(percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p50_ms,
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p95_ms,
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p99_ms
FROM benchmark_events
GROUP BY approach
ORDER BY approach;

\echo ''
\echo '── Note: filtered_events are high-value orders (>=500, PAID/SHIPPED)'
\echo '── Only Drasi captures these — wal2json & debezium show 0'
