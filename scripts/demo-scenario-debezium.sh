#!/usr/bin/env bash
set -euo pipefail

# Scenario: Debezium + Kafka consumer
# Run this script manually after completing the wal2json scenario.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Auto-detect external database mode
COMPOSE_FILES="-f ${ROOT_DIR}/docker-compose.yml"
if [[ -f "${ROOT_DIR}/docker-compose.external-db.yml" ]] && [[ -n "${PG_HOST:-}" ]]; then
  COMPOSE_FILES="${COMPOSE_FILES} -f ${ROOT_DIR}/docker-compose.external-db.yml"
fi
DC="docker compose ${COMPOSE_FILES}"
APPROACH="debezium"
RUN_LABEL="${RUN_LABEL:-$(date +%H%M%S)-debezium}"
LOCUST_USERS="${LOCUST_USERS:-50}"
LOCUST_SPAWN_RATE="${LOCUST_SPAWN_RATE:-10}"
LOCUST_RUN_TIME="${LOCUST_RUN_TIME:-2m}"

export RUN_LABEL

echo "════════════════════════════════════════════"
echo "  Scenario 2: Debezium+Kafka — label: ${RUN_LABEL}"
echo "════════════════════════════════════════════"

# --- Reset ---
echo ""
echo "[1/5] Resetting debezium benchmark data ..."
SLOTS_TO_DROP="debezium_slot" RESET_APPROACH="debezium" bash "${ROOT_DIR}/scripts/reset-demo.sh"

# --- Setup connector ---
echo ""
echo "[2/5] Registering Debezium connector with Kafka Connect ..."
bash "${ROOT_DIR}/scripts/setup-debezium.sh"

# --- Start consumer ---
echo ""
echo "[3/5] Starting Debezium consumer ..."
${DC} --profile consumers up -d debezium-consumer
sleep 3

echo ""
echo "Consumer started. Quick log check:"
docker logs --tail 5 edp-debezium-consumer 2>&1 || true
echo ""
echo "── NEXT: Open Kafka UI (http://localhost:8081)"
echo "   → Topic: dbserver1.public.orders → see messages flowing"
echo ""
read -rp "Press Enter once you've checked Kafka UI ..."

# --- Start load ---
echo ""
echo "[4/5] Starting Locust load (${LOCUST_USERS} users, ${LOCUST_RUN_TIME}) ..."
LOCUST_USERS="${LOCUST_USERS}" LOCUST_SPAWN_RATE="${LOCUST_SPAWN_RATE}" LOCUST_RUN_TIME="${LOCUST_RUN_TIME}" \
  ${DC} --profile load up -d locust

echo ""
echo "══════════════════════════════════════════════"
echo "  Load is running for ${LOCUST_RUN_TIME}."
echo "  → Switch to SLIDES: Debezium mechanism & tradeoffs"
echo "  → Come back here when the 2 minutes are up."
echo "══════════════════════════════════════════════"
echo ""
read -rp "Press Enter when load is complete to see results ..."

# --- Results ---
echo ""
echo "[5/5] Scenario results for ${RUN_LABEL}:"

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
echo "Stopping Debezium consumer & load ..."
${DC} --profile consumers stop debezium-consumer
${DC} --profile load stop locust

echo ""
echo "══════════════════════════════════════════════"
echo "  Debezium scenario complete."
echo ""
echo "  NEXT STEPS:"
echo "  1. → Streamlit: refresh to see both approaches (2 bars)"
echo "  2. → PSQL terminal: verify wal2json + debezium both in DB"
echo "  3. → SLIDES: move to Drasi flow slide"
echo "  4. → Run: bash scripts/demo-scenario-drasi.sh"
echo "══════════════════════════════════════════════"
