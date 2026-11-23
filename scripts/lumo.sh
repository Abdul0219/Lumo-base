#!/usr/bin/env bash
# Phase-gated Lumo Base runner. It never deploys on its own.
# Every mutating action requires an explicit LUMO_PHASE_APPROVED acknowledgement.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/vendor/supabase-docker"
ENV_FILE="$ROOT/deploy/env/.env"
CMD="${1:-plan}"
shift || true

[ -d "$UPSTREAM" ] || { echo "upstream config missing - run: sh scripts/sync-upstream.sh" >&2; exit 1; }
[ -f "$ENV_FILE" ]  || { echo "secrets file missing - copy deploy/env/.env.example to deploy/env/.env" >&2; exit 1; }

# Stage the override beside upstream so ./volumes/... resolves correctly.
cp "$ROOT/deploy/compose/docker-compose.lumo.yml" "$UPSTREAM/docker-compose.lumo.yml"
cd "$UPSTREAM"
export COMPOSE_FILE=docker-compose.yml:docker-compose.lumo.yml
export COMPOSE_ENV_FILES="$ENV_FILE"

plan() {
  echo "== Lumo Base plan (no changes) =="
  echo "release tag : $(python3 -c 'import json;print(json.load(open("'"$ROOT"'/deploy/versions.lock.json"))["upstream"]["release_tag"])')"
  echo "compose     : $COMPOSE_FILE"
  echo "env file    : $ENV_FILE (gitignored)"
  docker compose --env-file "$ENV_FILE" config --services
  echo "public ports: 443 only (Caddy). 8000/5432/6543 are 127.0.0.1 via the override."
  echo "optional    : realtime, functions, imgproxy, deno-cache (profile 'optional', OFF)"
}

require_approval() {
  local needed="$1"
  if [ "${LUMO_PHASE_APPROVED:-}" != "$needed" ]; then
    echo "BLOCKED: this action needs LUMO_PHASE_APPROVED=$needed (got '${LUMO_PHASE_APPROVED:-}')." >&2
    echo "Phase gates: docs/ROADMAP.md. Stop and request explicit approval first." >&2
    exit 2
  fi
}

case "$CMD" in
  plan)    plan ;;
  config)  plan; echo "-- resolved config --"; docker compose --env-file "$ENV_FILE" config ;;
  status)  docker compose --env-file "$ENV_FILE" ps ;;
  logs)    docker compose --env-file "$ENV_FILE" logs --tail=100 "${1:-}" ;;
  start)
    require_approval "phase2"
    plan
    bash "$ROOT/scripts/verify-manifest.sh"
    bash "$ROOT/scripts/check-secrets.sh"
    echo "== starting (Phase 2 approved) =="
    docker compose --env-file "$ENV_FILE" up -d --wait
    docker compose --env-file "$ENV_FILE" ps
    ;;
  stop)
    require_approval "phase2"
    docker compose --env-file "$ENV_FILE" down
    ;;
  optional)
    require_approval "phase6"
    echo "== enabling optional profile (Phase 6 approved) =="
    docker compose --env-file "$ENV_FILE" --profile optional up -d --wait
    ;;
  *)
    echo "usage: sh scripts/lumo.sh {plan|config|status|logs|start|stop|optional}" >&2
    exit 1 ;;
esac
