#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Load environment (.env for Docker Compose, ~/.pg_azure for credentials)
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi
if [[ -f "$HOME/.pg_azure" ]]; then
  set -a; source "$HOME/.pg_azure"; set +a
fi
MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_INTERVAL="${RETRY_INTERVAL:-2}"

# Build DATABASE_URL from individual env vars if not set directly
if [[ -z "${DATABASE_URL:-}" ]]; then
  PG_HOST="${PG_HOST:-localhost}"
  PG_PORT="${PG_PORT:-5432}"
  PG_USER="${PG_USER:-postgres}"
  PG_PASSWORD="${PG_PASSWORD:-postgres}"
  PG_DB="${PG_DB:-appdb}"
  PG_SSLMODE="${PG_SSLMODE:-disable}"
  DATABASE_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=${PG_SSLMODE}"
fi

echo "=== CDC Readiness Check ==="
echo "Target: ${DATABASE_URL%%@*}@..."

# Connectivity retry
attempt=0
until psql "${DATABASE_URL}" -c "SELECT 1" &>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $MAX_RETRIES ]]; then
    echo "FAIL: Cannot connect to database."
    exit 1
  fi
  echo "Waiting for database (${attempt}/${MAX_RETRIES}) ..."
  sleep "${RETRY_INTERVAL}"
done
echo "OK: Database connection established."

psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 <<'SQL'
SELECT name, setting
FROM pg_settings
WHERE name IN ('wal_level', 'max_replication_slots', 'max_wal_senders', 'max_slot_wal_keep_size')
ORDER BY name;

SELECT pubname, schemaname, tablename
FROM pg_publication_tables
WHERE pubname IN ('app_cdc_pub', 'app_cdc_pub_advanced')
ORDER BY pubname, schemaname, tablename;

SELECT slot_name, plugin, slot_type, active
FROM pg_replication_slots
ORDER BY slot_name;
SQL

echo "Running WAL safety query from scripts/wal-safety.sql ..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/scripts/wal-safety.sql"

echo "CDC readiness checks complete."
