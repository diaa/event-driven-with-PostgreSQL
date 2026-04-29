#!/usr/bin/env bash
set -euo pipefail

# Show current scenario progress or overall comparison across all scenarios.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Load environment (.env for Docker Compose, ~/.pg_azure for credentials)
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi
if [[ -f "$HOME/.pg_azure" ]]; then
  set -a; source "$HOME/.pg_azure"; set +a
fi

if [[ -n "${DATABASE_URL:-}" ]]; then
  DB_URL="${DATABASE_URL}"
elif [[ -n "${PG_HOST:-}" ]]; then
  DB_URL="postgresql://${PG_USER:-postgres}:${PG_PASSWORD:-postgres}@${PG_HOST}:${PG_PORT:-5432}/${PG_DB:-appdb}?sslmode=${PG_SSLMODE:-disable}"
else
  DB_URL="postgresql://postgres:postgres@localhost:5432/appdb?sslmode=disable"
fi

echo "════════════════════════════════════════════"
echo "  CDC Benchmark — Overall Comparison"
echo "════════════════════════════════════════════"
echo ""

echo "--- Latency Summary ---"
psql "${DB_URL}" <<'SQL'
SELECT
  approach,
  count(*) AS total_events,
  round(avg(latency_ms)::numeric, 2) AS avg_ms,
  round(percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p50_ms,
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p95_ms,
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p99_ms
FROM benchmark_events
WHERE latency_ms IS NOT NULL
GROUP BY approach
ORDER BY approach;
SQL

echo ""
echo "--- Throughput (events per 5s, last 60s) ---"
psql "${DB_URL}" <<'SQL'
SELECT
  approach,
  date_bin('5 seconds', observed_at, timestamptz '2000-01-01') AS bucket,
  count(*) AS events
FROM benchmark_events
WHERE observed_at > now() - interval '60 seconds'
GROUP BY approach, bucket
ORDER BY bucket DESC, approach
LIMIT 36;
SQL

echo ""
echo "--- Replication Slot Status ---"
psql "${DB_URL}" <<'SQL'
SELECT slot_name, plugin, slot_type, active,
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS bytes_behind
FROM pg_replication_slots
ORDER BY slot_name;
SQL

echo ""
echo "View Streamlit dashboard at http://localhost:8501 for charts."
