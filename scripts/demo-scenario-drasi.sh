#!/usr/bin/env bash
set -euo pipefail

# Scenario: Drasi pgoutput consumer
# Run this script manually after completing the Debezium scenario.
#
# SAFETY: Only one Drasi consumer should use drasi_slot at a time.
# Do NOT run this concurrently with the Drasi Server profile.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Auto-detect external database mode
COMPOSE_FILES="-f ${ROOT_DIR}/docker-compose.yml"
if [[ -f "${ROOT_DIR}/docker-compose.external-db.yml" ]] && [[ -n "${PG_HOST:-}" ]]; then
  COMPOSE_FILES="${COMPOSE_FILES} -f ${ROOT_DIR}/docker-compose.external-db.yml"
fi
DC="docker compose ${COMPOSE_FILES}"
APPROACH="drasi"
RUN_LABEL="${RUN_LABEL:-$(date +%H%M%S)-drasi}"
LOCUST_USERS="${LOCUST_USERS:-50}"
LOCUST_SPAWN_RATE="${LOCUST_SPAWN_RATE:-10}"
LOCUST_RUN_TIME="${LOCUST_RUN_TIME:-2m}"

export RUN_LABEL

echo "════════════════════════════════════════════"
echo "  Scenario: Drasi — label: ${RUN_LABEL}"
echo "════════════════════════════════════════════"

# --- Safety check: ensure drasi-server is not running ---
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'edp-drasi-server'; then
  echo "ERROR: edp-drasi-server is running and will conflict with drasi_slot."
  echo "Stop it first:  docker compose --profile drasi stop drasi-server"
  exit 1
fi

# --- Reset ---
echo ""
echo "[1/4] Resetting benchmark data ..."
SLOTS_TO_DROP="drasi_slot" RESET_APPROACH="drasi" bash "${ROOT_DIR}/scripts/reset-demo.sh"

# --- Start consumer ---
echo ""
echo "[2/4] Starting Drasi consumer ..."
${DC} --profile consumers up -d --build drasi-consumer
sleep 3

echo "Consumer logs (last 5 lines):"
docker logs --tail 5 edp-drasi-consumer 2>&1 || true

# --- Start load ---
echo ""
echo "[3/4] Starting Locust load (${LOCUST_USERS} users, ${LOCUST_RUN_TIME}) ..."
LOCUST_USERS="${LOCUST_USERS}" LOCUST_SPAWN_RATE="${LOCUST_SPAWN_RATE}" LOCUST_RUN_TIME="${LOCUST_RUN_TIME}" \
  ${DC} --profile load up -d --build locust

echo ""
echo "Load running. Monitor progress:"
echo "  • Locust UI:   http://localhost:8089"
echo "  • Streamlit:   http://localhost:8501"
echo "  • Consumer:    docker logs -f edp-drasi-consumer"
echo ""
echo "Press Enter when load is complete to see results ..."
read -r

# --- Results ---
echo ""
echo "[4/4] Scenario results for ${RUN_LABEL}:"

if [[ -n "${DATABASE_URL:-}" ]]; then
  DB_URL="${DATABASE_URL}"
elif [[ -n "${PG_HOST:-}" ]]; then
  DB_URL="postgresql://${PG_USER:-postgres}:${PG_PASSWORD:-postgres}@${PG_HOST}:${PG_PORT:-5432}/${PG_DB:-appdb}?sslmode=${PG_SSLMODE:-disable}"
else
  DB_URL="postgresql://postgres:postgres@localhost:5432/appdb?sslmode=disable"
fi

psql "${DB_URL}" <<SQL
SELECT
  '${APPROACH}' AS approach,
  count(*) AS total_events,
  round(avg(latency_ms)::numeric, 2) AS avg_latency_ms,
  round(percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p50_ms,
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p95_ms,
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p99_ms
FROM benchmark_events
WHERE approach = '${APPROACH}';
SQL

# --- Stop consumer ---
echo ""
echo "Stopping Drasi consumer ..."
${DC} --profile consumers stop drasi-consumer
${DC} --profile load stop locust

echo ""
echo "Scenario '${APPROACH}' complete."
