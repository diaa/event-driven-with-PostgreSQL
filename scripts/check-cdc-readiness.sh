#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required."
  exit 1
fi

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
