#!/usr/bin/env bash
# --------------------------------------------------------------------------
# drasi-add-query.sh — Register a new continuous query on Drasi Server at
# runtime without restarting any services.
#
# Usage:
#   ./scripts/drasi-add-query.sh <query-id> <cypher-query> [reaction-url]
#
# Examples:
#   # Add a "cancelled orders" query and wire it to the filtered sink
#   ./scripts/drasi-add-query.sh cancelled-orders \
#       "MATCH (o:orders) WHERE o.status = 'CANCELLED' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at"
#
#   # Add a "rush orders" query (high-amount + just paid)
#   ./scripts/drasi-add-query.sh rush-orders \
#       "MATCH (o:orders) WHERE o.amount >= 200 AND o.status = 'PAID' RETURN o.id AS id, o.customer_id AS customer_id, o.amount AS amount, o.status AS status, o.updated_at AS updated_at"
# --------------------------------------------------------------------------
set -euo pipefail

DRASI_URL="${DRASI_URL:-http://localhost:8080}"
SINK_URL="${SINK_URL:-http://drasi-sink:8090}"

QUERY_ID="${1:?Usage: $0 <query-id> <cypher-query>}"
CYPHER_QUERY="${2:?Usage: $0 <query-id> <cypher-query>}"

echo ""
echo "=== Adding Drasi continuous query: ${QUERY_ID} ==="
echo "    Drasi Server: ${DRASI_URL}"
echo ""

# Step 1: Register the query
echo "[1/2] Registering query '${QUERY_ID}' ..."

curl -sS -X POST \
  -H "Content-Type: application/json" \
  "${DRASI_URL}/api/v1/queries" \
  -d @- <<JSON
{
  "id": "${QUERY_ID}",
  "query": "${CYPHER_QUERY}",
  "queryLanguage": "Cypher",
  "sources": [{"sourceId": "orders-db"}],
  "enableBootstrap": false
}
JSON

echo ""
echo "    Query registered."

# Step 2: Add an HTTP reaction to send matches to the filtered sink
echo "[2/2] Adding HTTP reaction for '${QUERY_ID}' → ${SINK_URL}/filtered-events ..."

curl -sS -X POST \
  -H "Content-Type: application/json" \
  "${DRASI_URL}/api/v1/reactions" \
  -d @- <<JSON
{
  "kind": "http",
  "id": "${QUERY_ID}-sink",
  "queries": ["${QUERY_ID}"],
  "autoStart": true,
  "baseUrl": "${SINK_URL}",
  "routes": {
    "${QUERY_ID}": {
      "added": {
        "url": "/filtered-events",
        "method": "POST",
        "body": "{\"event_id\": \"{{after.id}}\", \"source_commit_ts\": \"{{after.updated_at}}\", \"operation\": \"INSERT\", \"query_id\": \"${QUERY_ID}\"}",
        "headers": {"Content-Type": "application/json"}
      },
      "updated": {
        "url": "/filtered-events",
        "method": "POST",
        "body": "{\"event_id\": \"{{after.id}}\", \"source_commit_ts\": \"{{after.updated_at}}\", \"operation\": \"UPDATE\", \"query_id\": \"${QUERY_ID}\"}",
        "headers": {"Content-Type": "application/json"}
      }
    }
  }
}
JSON

echo ""
echo "=== Done. Query '${QUERY_ID}' is now live. ==="
echo "    Events matching this query will appear at: ${SINK_URL}/filtered-events"
echo "    Check results: curl ${DRASI_URL}/api/v1/queries/${QUERY_ID}/results"
echo ""
