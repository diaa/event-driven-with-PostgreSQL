#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Auto-load .env
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

# Auto-detect external database mode
COMPOSE_FILES="-f ${ROOT_DIR}/docker-compose.yml"
if [[ -f "${ROOT_DIR}/docker-compose.external-db.yml" ]] && [[ -n "${PG_HOST:-}" ]]; then
  COMPOSE_FILES="${COMPOSE_FILES} -f ${ROOT_DIR}/docker-compose.external-db.yml"
  echo "External DB mode: ${PG_HOST}"
fi
DC="docker compose ${COMPOSE_FILES}"

echo "Starting all base infrastructure ..."
${DC} up -d --build

echo ""
echo "Waiting for Kafka Connect ..."
attempt=0
until curl -sf http://localhost:8083/connectors &>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge 30 ]]; then
    echo "WARNING: Kafka Connect not ready after 150s — may need more time."
    break
  fi
  sleep 5
done
[[ $attempt -lt 30 ]] && echo "Kafka Connect ready."

echo ""
bash "${ROOT_DIR}/scripts/demo-precheck.sh"
