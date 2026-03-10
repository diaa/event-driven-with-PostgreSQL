#!/usr/bin/env bash
set -euo pipefail

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-edp-postgres}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-appdb}"

echo "Resetting benchmark table ..."
docker exec -i "${POSTGRES_CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -c "TRUNCATE TABLE benchmark_events;"

echo "Dropping demo slots if they exist ..."
docker exec -i "${POSTGRES_CONTAINER}" psql -U "${PGUSER}" -d "${PGDATABASE}" -c "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name IN ('wal2json_slot','debezium_slot','drasi_slot');"

echo "Reset complete."
