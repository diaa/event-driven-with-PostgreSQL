#!/usr/bin/env bash
# --------------------------------------------------------------------------
# drasi-demo-live-filter.sh — Self-contained script for recording the Drasi
# "live query change" demo moment.
#
# What it does (while Locust traffic is already running):
#   1. Shows current high-value-orders results from Drasi
#   2. Adds a brand-new "cancelled-orders" query at runtime
#   3. Adds a "rush-orders" query (≥$200, just PAID) at runtime
#   4. Tails the Drasi server logs so you can see filtered events appear
#
# Prerequisites:
#   - All services running: docker compose up -d --build
#   - Drasi profile running: docker compose --profile drasi up -d --build
#   - Locust traffic generator running (http://localhost:8089)
#
# Usage:
#   ./scripts/drasi-demo-live-filter.sh
# --------------------------------------------------------------------------
set -euo pipefail

DRASI_URL="${DRASI_URL:-http://localhost:8080}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      Drasi Live Query Demo — No Restart Required           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# --------------------------------------------------------------------------
echo "▸ Step 1: Verify Drasi Server is healthy"
echo "  GET ${DRASI_URL}/health"
echo ""
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${DRASI_URL}/health" || true)
if [ "${HTTP_CODE}" != "200" ]; then
  echo "  ✗ Drasi Server returned ${HTTP_CODE}. Is it running?"
  echo "    Try: docker compose --profile drasi up -d --build"
  exit 1
fi
echo "  ✓ Drasi Server is healthy."
echo ""

# --------------------------------------------------------------------------
echo "▸ Step 2: Show existing queries"
echo "  GET ${DRASI_URL}/api/v1/queries"
echo ""
curl -sS "${DRASI_URL}/api/v1/queries" | python3 -m json.tool 2>/dev/null || curl -sS "${DRASI_URL}/api/v1/queries"
echo ""
echo "  → You can see 'all-orders' and 'high-value-orders' are already running."
echo ""

# --------------------------------------------------------------------------
echo "▸ Step 3: Check high-value-orders results (amount ≥ \$500 AND PAID/SHIPPED)"
echo "  GET ${DRASI_URL}/api/v1/queries/high-value-orders/results"
echo ""
curl -sS "${DRASI_URL}/api/v1/queries/high-value-orders/results" | python3 -m json.tool 2>/dev/null || curl -sS "${DRASI_URL}/api/v1/queries/high-value-orders/results"
echo ""

# --------------------------------------------------------------------------
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  NOW: Adding a new query WHILE traffic is flowing."
echo "  With wal2json or Debezium, this would require a code change"
echo "  and redeployment. With Drasi, it's a single API call."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# --------------------------------------------------------------------------
echo "▸ Step 4: Add 'cancelled-orders' query — detect cancellations in real-time"
echo "  Retail use case: immediately notify finance/refund system"
echo ""

./scripts/drasi-add-query.sh cancelled-orders \
  "MATCH (o:orders) WHERE o.status = 'CANCELLED' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at"

echo ""

# --------------------------------------------------------------------------
echo "▸ Step 5: Add 'rush-orders' query — priority fulfillment for hot meals"
echo "  Retail use case: orders ≥ \$200 that just got PAID → start preparing now"
echo ""

./scripts/drasi-add-query.sh rush-orders \
  "MATCH (o:orders) WHERE o.amount >= 200 AND o.status = 'PAID' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at"

echo ""

# --------------------------------------------------------------------------
echo "▸ Step 6: Verify all queries are now running"
echo "  GET ${DRASI_URL}/api/v1/queries"
echo ""
curl -sS "${DRASI_URL}/api/v1/queries" | python3 -m json.tool 2>/dev/null || curl -sS "${DRASI_URL}/api/v1/queries"
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Done! New queries are live. Check these while traffic runs:║"
echo "║                                                            ║"
echo "║  Cancelled orders:                                         ║"
echo "║    curl ${DRASI_URL}/api/v1/queries/cancelled-orders/results  ║"
echo "║                                                            ║"
echo "║  Rush orders:                                              ║"
echo "║    curl ${DRASI_URL}/api/v1/queries/rush-orders/results       ║"
echo "║                                                            ║"
echo "║  Benchmark events (filtered):                              ║"
echo "║    SELECT * FROM benchmark_events                          ║"
echo "║    WHERE notes LIKE 'drasi filtered%'                      ║"
echo "║    ORDER BY observed_at DESC LIMIT 20;                     ║"
echo "║                                                            ║"
echo "║  Drasi server logs:                                        ║"
echo "║    docker logs -f edp-drasi-server                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
