#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_RETRIES="${MAX_RETRIES:-10}"
RETRY_INTERVAL="${RETRY_INTERVAL:-3}"

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

echo "Target: ${DATABASE_URL%%@*}@..."

# Retry loop for external DB connectivity
attempt=0
until psql "${DATABASE_URL}" -c "SELECT 1" &>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $MAX_RETRIES ]]; then
    echo "ERROR: Could not connect after ${MAX_RETRIES} attempts."
    exit 1
  fi
  echo "Waiting for database (attempt ${attempt}/${MAX_RETRIES}) ..."
  sleep "${RETRY_INTERVAL}"
done

echo "Applying schema and replication SQL ..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/01-schema.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/02-replication.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/03-views.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/04-seed.sql"

echo "Database initialization complete."
