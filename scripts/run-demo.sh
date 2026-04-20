#!/usr/bin/env bash
# ==========================================================================
# run-demo.sh — Orchestrated demo script for CDC Showdown recording
#
# Runs the full demo end-to-end with narration pauses.
# Press ENTER at each pause to advance to the next step.
#
# Usage:
#   bash ./scripts/run-demo.sh
#
# Prerequisites:
#   All services already running:
#     docker compose up -d --build
#     docker compose --profile consumers --profile drasi up -d --build
# ==========================================================================
set -euo pipefail

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-edp-postgres}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-appdb}"
DRASI_URL="${DRASI_URL:-http://localhost:8080}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

step=0

pause() {
  echo ""
  echo -e "${YELLOW}▶ Press ENTER to continue...${NC}"
  read -r
  echo ""
}

section() {
  step=$((step + 1))
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Step ${step}: $1${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

run_sql() {
  docker exec -i "${POSTGRES_CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -c "$1"
}

# ===== INTRO =====
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        CDC Showdown: wal2json vs Debezium vs Drasi         ║${NC}"
echo -e "${CYAN}║       Same source · Same workload · Three approaches       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  All three CDC consumers are running in parallel."
echo "  One Locust load test feeds them all simultaneously."
echo ""
echo "  Dashboards:"
echo "    Benchmark:  http://localhost:8501"
echo "    Grafana:    http://localhost:3000  (admin/admin)"
echo "    Kafka UI:   http://localhost:8081"
echo "    Locust:     http://localhost:8089"
echo ""

pause

# ===== STEP 1: SHOW THE ARCHITECTURE =====
section "Verify the system is ready"

echo "  Checking containers..."
docker ps --format "table {{.Names}}\t{{.Status}}" --filter "name=edp-" 2>/dev/null
echo ""

echo "  Checking replication slots..."
run_sql "SELECT slot_name, plugin, active FROM pg_replication_slots;"
echo ""

echo "  Checking Debezium connector..."
curl -sS http://localhost:8083/connectors/orders-connector/status 2>/dev/null | python3 -m json.tool 2>/dev/null || curl -sS http://localhost:8083/connectors/orders-connector/status 2>/dev/null
echo ""

echo -e "${GREEN}  ✓ All systems ready${NC}"

pause

# ===== STEP 2: RESET BENCHMARK DATA =====
section "Reset benchmark data (clean slate)"

echo "  Truncating benchmark_events..."
run_sql "TRUNCATE TABLE benchmark_events;"
echo ""
echo "  Current order count:"
run_sql "SELECT count(*) AS existing_orders FROM orders;"

echo -e "${GREEN}  ✓ Clean slate for benchmarking${NC}"

pause

# ===== STEP 3: START TRAFFIC =====
section "Start traffic (Locust — 50 users, 10/s spawn, 5 min)"

echo "  Starting Locust container with autostart..."
docker compose --profile load up -d --build 2>/dev/null

echo ""
echo "  Locust is running at: http://localhost:8089"
echo "  Traffic is flowing — 70% INSERTs, 30% UPDATEs on the orders table."
echo ""
echo "  All three consumers are capturing events:"
echo "    • wal2json  → direct logical replication slot"
echo "    • Debezium  → PostgreSQL → Kafka topic → consumer"
echo "    • Drasi     → PostgreSQL → continuous query → HTTP sink"

pause

# ===== STEP 4: OBSERVE WAL2JSON =====
section "CDC Path 1: wal2json — Custom consumer"

echo "  wal2json reads directly from a logical replication slot."
echo "  No middleware, no broker — raw WAL → Python consumer."
echo ""
echo "  Tail wal2json container logs (last 10 lines):"
docker logs --tail 10 edp-wal2json-consumer 2>&1 || echo "  (container logs not available)"
echo ""
echo "  Current benchmark events captured:"
run_sql "SELECT count(*) AS wal2json_events FROM benchmark_events WHERE approach = 'wal2json';"

pause

# ===== STEP 5: OBSERVE DEBEZIUM =====
section "CDC Path 2: Debezium + Kafka"

echo "  Debezium captures WAL via pgoutput → publishes to Kafka → consumer reads topic."
echo "  Extra hop through Kafka adds latency but gives you ecosystem integrations."
echo ""
echo "  Tail Debezium consumer logs (last 10 lines):"
docker logs --tail 10 edp-debezium-consumer 2>&1 || echo "  (container logs not available)"
echo ""
echo "  Kafka topic: dbserver1.public.orders"
echo "  View in Kafka UI: http://localhost:8081"
echo ""
echo "  Current benchmark events captured:"
run_sql "SELECT count(*) AS debezium_events FROM benchmark_events WHERE approach = 'debezium';"

pause

# ===== STEP 6: OBSERVE DRASI =====
section "CDC Path 3: Drasi — Continuous queries"

echo "  Drasi evaluates Cypher queries against the WAL stream in real-time."
echo "  Only matching rows are forwarded — no extra broker needed."
echo ""
echo "  Active queries:"
curl -sS "${DRASI_URL}/api/v1/queries" 2>/dev/null | python3 -m json.tool 2>/dev/null || curl -sS "${DRASI_URL}/api/v1/queries" 2>/dev/null || echo "  (Drasi API not available)"
echo ""
echo "  Current benchmark events captured:"
run_sql "SELECT count(*) AS drasi_events FROM benchmark_events WHERE approach = 'drasi';"

pause

# ===== STEP 7: LIVE QUERY CHANGE (DRASI WOW MOMENT) =====
section "Drasi advantage: Add a query WHILE traffic is flowing"

echo -e "${BOLD}  This is the key differentiator.${NC}"
echo ""
echo "  With wal2json → you'd change Python code → redeploy → lose events"
echo "  With Debezium  → reconfigure connector → restart → rolling update"
echo "  With Drasi     → one API call → immediate, zero downtime"
echo ""
echo "  Adding 'cancelled-orders' query — detect cancellations for refund system:"

# Add cancelled-orders query
if command -v bash &>/dev/null && [ -f ./scripts/drasi-add-query.sh ]; then
  bash ./scripts/drasi-add-query.sh cancelled-orders \
    "MATCH (o:orders) WHERE o.status = 'CANCELLED' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at" \
    2>/dev/null || echo "  (Query may already exist or Drasi API not available)"
else
  echo "  (drasi-add-query.sh not found, skipping)"
fi

echo ""
echo "  Adding 'rush-orders' query — priority fulfillment for orders ≥\$200, just PAID:"

if command -v bash &>/dev/null && [ -f ./scripts/drasi-add-query.sh ]; then
  bash ./scripts/drasi-add-query.sh rush-orders \
    "MATCH (o:orders) WHERE o.amount >= 200 AND o.status = 'PAID' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at" \
    2>/dev/null || echo "  (Query may already exist or Drasi API not available)"
else
  echo "  (drasi-add-query.sh not found, skipping)"
fi

echo ""
echo -e "${GREEN}  ✓ New queries are live — no restart, no downtime${NC}"
echo ""
echo "  Check filtered events arriving:"
run_sql "SELECT source_event_id, operation, latency_ms, notes FROM benchmark_events WHERE notes LIKE 'drasi filtered%' ORDER BY observed_at DESC LIMIT 5;"

pause

# ===== STEP 8: COMPARE ALL THREE =====
section "Compare all three approaches"

echo "  Latency summary (p50 / p95 / p99):"
run_sql "SELECT * FROM vw_benchmark_latency_summary;"

echo ""
echo "  Event counts by approach:"
run_sql "SELECT approach, count(*) AS total_events FROM benchmark_events GROUP BY approach ORDER BY approach;"

echo ""
echo "  Open the Benchmark Dashboard for visual comparison:"
echo "    http://localhost:8501"
echo ""
echo "  Open Grafana for PostgreSQL overhead metrics:"
echo "    http://localhost:3000"

pause

# ===== STEP 9: WAL SAFETY =====
section "WAL safety — operational reality"

echo "  Replication slots and their lag:"
run_sql "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal FROM pg_replication_slots;"

echo ""
echo "  Key takeaway: every CDC approach creates a replication slot."
echo "  Inactive slots retain WAL indefinitely → disk risk."
echo "  Always: monitor slots, drop unused ones, set max_slot_wal_keep_size."

pause

# ===== STEP 10: DECISION GUIDE =====
section "Decision guide"

echo ""
echo "  ┌──────────────┬───────────────────────────────────────────────┐"
echo "  │ Choose       │ When                                         │"
echo "  ├──────────────┼───────────────────────────────────────────────┤"
echo "  │ wal2json     │ Minimal stack, full control, low latency     │"
echo "  │ Debezium     │ Kafka ecosystem, rich connectors, streaming  │"
echo "  │ Drasi        │ Declarative filtering, runtime query changes │"
echo "  └──────────────┴───────────────────────────────────────────────┘"
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    Demo complete! 🎉                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Cleanup: docker compose --profile load --profile consumers --profile drasi down"
echo "  Full reset: docker compose down -v"
echo ""
