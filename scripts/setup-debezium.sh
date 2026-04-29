#!/usr/bin/env bash
set -euo pipefail

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CONNECTOR_NAME="${CONNECTOR_NAME:-orders-connector}"
MAX_RETRIES="${MAX_RETRIES:-30}"
RETRY_INTERVAL="${RETRY_INTERVAL:-5}"

DB_HOST="${DB_HOST:-${PG_HOST:-postgres}}"
DB_PORT="${DB_PORT:-${PG_PORT:-5432}}"
DB_USER="${DB_USER:-${PG_USER:-postgres}}"
DB_PASSWORD="${DB_PASSWORD:-${PG_PASSWORD:-postgres}}"
DB_NAME="${DB_NAME:-${PG_DB:-appdb}}"
DB_SSLMODE="${DB_SSLMODE:-${PG_SSLMODE:-disable}}"

# Wait for Kafka Connect to be ready
attempt=0
echo "Waiting for Kafka Connect at ${CONNECT_URL} ..."
until curl -sf "${CONNECT_URL}/connectors" &>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $MAX_RETRIES ]]; then
    echo "ERROR: Kafka Connect not ready after ${MAX_RETRIES} attempts."
    exit 1
  fi
  sleep "${RETRY_INTERVAL}"
done
echo "Kafka Connect is ready."

# Build connector config — include SSL properties when sslmode != disable
SSL_CONFIG=""
if [[ "${DB_SSLMODE}" != "disable" ]]; then
  SSL_CONFIG=",\"database.sslmode\": \"${DB_SSLMODE}\""
fi

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
  "topic.prefix": "dbserver1"${SSL_CONFIG}
}
JSON

echo "Upserting Debezium connector '${CONNECTOR_NAME}' on ${CONNECT_URL} ..."
curl -sS -X PUT \
  -H "Content-Type: application/json" \
  --data @/tmp/${CONNECTOR_NAME}.json \
  "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/config" >/dev/null

echo "Connector upserted."
