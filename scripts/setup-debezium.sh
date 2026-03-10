#!/usr/bin/env bash
set -euo pipefail

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CONNECTOR_NAME="${CONNECTOR_NAME:-orders-connector}"

# Use service name "postgres" when called from inside Docker network, localhost otherwise.
DB_HOST="${DB_HOST:-postgres}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_NAME="${DB_NAME:-appdb}"

cat <<JSON >/tmp/${CONNECTOR_NAME}.json
{
  "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
  "database.hostname": "${DB_HOST}",
  "database.port": "${DB_PORT}",
  "database.user": "${DB_USER}",
  "database.password": "${DB_PASSWORD}",
  "database.dbname": "${DB_NAME}",
  "database.server.name": "dbserver1",
  "plugin.name": "pgoutput",
  "slot.name": "debezium_slot",
  "publication.name": "app_cdc_pub",
  "table.include.list": "public.orders",
  "tombstones.on.delete": "false",
  "snapshot.mode": "never",
  "topic.prefix": "dbserver1"
}
JSON

echo "Upserting Debezium connector '${CONNECTOR_NAME}' on ${CONNECT_URL} ..."
curl -sS -X PUT \
  -H "Content-Type: application/json" \
  --data @/tmp/${CONNECTOR_NAME}.json \
  "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/config" >/dev/null

echo "Connector upserted."
