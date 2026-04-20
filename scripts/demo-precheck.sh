#!/usr/bin/env bash
set -euo pipefail

# Pre-flight readiness check for the CDC demo.
# Validates infrastructure health without starting any scenario.

PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" &>/dev/null; then
    echo "  ✓ ${label}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${label}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Demo Pre-flight Check ==="
echo ""

# --- Database ---
echo "[Database]"
if [[ -n "${DATABASE_URL:-}" ]]; then
  DB_URL="${DATABASE_URL}"
elif [[ -n "${PG_HOST:-}" ]]; then
  PG_SSLMODE="${PG_SSLMODE:-disable}"
  DB_URL="postgresql://${PG_USER:-postgres}:${PG_PASSWORD:-postgres}@${PG_HOST}:${PG_PORT:-5432}/${PG_DB:-appdb}?sslmode=${PG_SSLMODE}"
else
  DB_URL="postgresql://postgres:postgres@localhost:5432/appdb?sslmode=disable"
fi

check "PostgreSQL reachable" psql "${DB_URL}" -c "SELECT 1"
check "wal_level=logical" psql "${DB_URL}" -tAc "SELECT 1 FROM pg_settings WHERE name='wal_level' AND setting='logical'"
check "Publication app_cdc_pub exists" psql "${DB_URL}" -tAc "SELECT 1 FROM pg_publication WHERE pubname='app_cdc_pub'"
check "benchmark_events table exists" psql "${DB_URL}" -tAc "SELECT 1 FROM information_schema.tables WHERE table_name='benchmark_events'"

echo ""

# --- Kafka / Debezium ---
echo "[Kafka & Debezium]"
check "Kafka broker container running" docker inspect -f '{{.State.Running}}' edp-kafka
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
check "Kafka Connect healthy" curl -sf "${CONNECT_URL}/connectors"
check "Kafka UI reachable" curl -sf "http://localhost:8081"

echo ""

# --- Monitoring ---
echo "[Monitoring]"
check "Grafana reachable" curl -sf "http://localhost:3000/api/health"
check "Prometheus reachable" curl -sf "http://localhost:9090/-/healthy"

echo ""

# --- Dashboard ---
echo "[Dashboard]"
check "Streamlit dashboard reachable" curl -sf "http://localhost:8501/_stcore/health"

echo ""
echo "=== Result: ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  echo "WARNING: Some checks failed. Review above before starting scenarios."
  exit 1
fi
echo "All checks passed. Ready for demo."
