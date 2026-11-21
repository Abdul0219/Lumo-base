#!/usr/bin/env bash
# teardown.sh — Safely shut down the Supabase stack and Caddy.
#
# By default this does NOT destroy volumes — data is preserved on disk.
# Use --purge to remove volumes (irreversible — destroys all data).
#
# Usage:
#   sudo bash deploy/stack/teardown.sh          # stop, keep data
#   sudo bash deploy/stack/teardown.sh --purge  # stop + delete all volumes
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/env/.env"
UPSTREAM="$ROOT/vendor/supabase-docker"

PURGE=false
if [ "${1:-}" = "--purge" ]; then
  PURGE=true
fi

echo "== Lumo Base teardown =="
echo "  purge volumes: $PURGE"

# ---- stop Caddy -------------------------------------------------------------
if docker ps -a --filter "name=lumo-caddy" --format '{{.ID}}' | grep -q .; then
  echo "== stopping Caddy =="
  docker stop lumo-caddy 2>/dev/null || true
  docker rm lumo-caddy 2>/dev/null || true
else
  echo "SKIP: Caddy container not found"
fi

# ---- stop Supabase stack ----------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  echo "FAIL: $ENV_FILE not found — cannot determine compose project." >&2
  exit 1
fi

if [ -d "$UPSTREAM" ]; then
  cd "$UPSTREAM"
  export COMPOSE_FILE=docker-compose.yml:docker-compose.lumo.yml
  export COMPOSE_ENV_FILES="$ENV_FILE"

  echo "== stopping stack =="
  docker compose --env-file "$ENV_FILE" down --remove-orphans

  if $PURGE; then
    echo ""
    echo "WARNING: --purge will delete ALL data volumes. This is irreversible."
    echo "Press Ctrl+C within 10 seconds to abort..."
    sleep 10

    echo "== removing volumes =="
    docker compose --env-file "$ENV_FILE" down -v --remove-orphans
    echo "OK: volumes removed"
  fi
else
  echo "SKIP: upstream directory not found — stack may not have been deployed"
fi

# ---- verify no containers remain --------------------------------------------
REMAINING=$(docker ps --filter "name=lumo-base" --format '{{.Names}}' 2>/dev/null || true)
if [ -n "$REMAINING" ]; then
  echo "WARN: containers still running: $REMAINING" >&2
else
  echo "OK: no Lumo Base containers running"
fi

echo ""
if $PURGE; then
  echo "Teardown complete. All data has been destroyed."
else
  echo "Teardown complete. Data preserved in Docker volumes."
  echo "Restart with: sudo bash deploy/stack/bring-up.sh"
fi
