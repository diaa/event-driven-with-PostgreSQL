#!/usr/bin/env bash
set -euo pipefail

# Reset benchmark data between scenarios.
# Supports both embedded (docker exec) and external DB (DATABASE_URL or PG_* vars).
# Use SLOTS_TO_DROP to target specific slots (default: all demo slots).

SLOTS_TO_DROP="${SLOTS_TO_DROP:-wal2json_slot,debezium_slot,drasi_slot}"
RESET_APPROACH="${RESET_APPROACH:-}"

# Build a SQL-safe IN list: 'slot1','slot2','slot3'
SLOT_IN_LIST=$(echo "${SLOTS_TO_DROP}" | sed "s/[^,][^,]*/'&'/g")

if [[ -n "${DATABASE_URL:-}" ]]; then
  DB_URL="${DATABASE_URL}"
elif [[ -n "${PG_HOST:-}" ]]; then
  PG_PORT="${PG_PORT:-5432}"
  PG_USER="${PG_USER:-postgres}"
  PG_PASSWORD="${PG_PASSWORD:-postgres}"
  PG_DB="${PG_DB:-appdb}"
  PG_SSLMODE="${PG_SSLMODE:-disable}"
  DB_URL="postgresql://${PG_USER}:${PG_PASSWORD}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=${PG_SSLMODE}"
else
  DB_URL=""
fi

if [[ -n "${DB_URL}" ]]; then
  echo "Resetting via psql ..."
  if [[ -n "${RESET_APPROACH}" ]]; then
    psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "DELETE FROM benchmark_events WHERE approach = '${RESET_APPROACH}';"
  else
    psql "${DB_URL}" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE benchmark_events;"
  fi
  psql "${DB_URL}" -c \
    "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name IN (${SLOT_IN_LIST}) AND NOT active;" 2>/dev/null || true
else
  POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-edp-postgres}"
  PGUSER="${PGUSER:-postgres}"
  PGDATABASE="${PGDATABASE:-appdb}"

  echo "Resetting via docker exec on ${POSTGRES_CONTAINER} ..."
  if [[ -n "${RESET_APPROACH}" ]]; then
    docker exec -i "${POSTGRES_CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -c "DELETE FROM benchmark_events WHERE approach = '${RESET_APPROACH}';"
  else
    docker exec -i "${POSTGRES_CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -c "TRUNCATE TABLE benchmark_events;"
  fi
  docker exec -i "${POSTGRES_CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -c \
    "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name IN (${SLOT_IN_LIST}) AND NOT active;" 2>/dev/null || true
fi

echo "Reset complete."
