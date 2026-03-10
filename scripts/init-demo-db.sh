#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL is required. Example:"
  echo "  export DATABASE_URL='postgresql://pgadmin:***@<host>:5432/appdb?sslmode=require'"
  exit 1
fi

echo "Applying schema and replication SQL to ${DATABASE_URL%%:*}://..."
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/01-schema.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/02-replication.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/03-views.sql"
psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -f "${ROOT_DIR}/db/init/04-seed.sql"

echo "Database initialization complete."
