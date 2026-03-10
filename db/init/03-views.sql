CREATE OR REPLACE VIEW vw_benchmark_latency_summary AS
SELECT
  approach,
  count(*) AS total_events,
  round(avg(latency_ms)::numeric, 2) AS avg_latency_ms,
  round(percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p50_latency_ms,
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p95_latency_ms,
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p99_latency_ms
FROM benchmark_events
WHERE latency_ms IS NOT NULL
GROUP BY approach;

CREATE OR REPLACE VIEW vw_benchmark_throughput_5s AS
SELECT
  approach,
  date_bin('5 seconds', observed_at, timestamptz '2000-01-01 00:00:00+00') AS window_start,
  count(*) AS events_in_window
FROM benchmark_events
GROUP BY approach, window_start
ORDER BY window_start DESC;
