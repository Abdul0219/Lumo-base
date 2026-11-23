#!/usr/bin/env bash
# bring-up.sh — Phase 2 stack deployment.
#
# Brings the Supabase self-hosted stack online with the Lumo Base override.
# Pre-flight: validates .env, manifests, and secrets. Then starts the stack
# with docker compose up -d --wait and verifies container health.
#
# This script is the operator-friendly wrapper around scripts/lumo.sh start.
# It sets LUMO_PHASE_APPROVED=phase2 so lumo.sh does not block.
#
# Usage:
#   sudo bash deploy/stack/bring-up.sh
#
# Prerequisites:
#   - Phase 1 complete (verify-phase1.sh passed)
#   - deploy/env/.env exists and is fully filled (no CHANGE_ME)
#   - vendor/supabase-docker/ synced (scripts/sync-upstream.sh done)
#   - Caddy container running (deploy/stack/configure-caddy.sh done)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/env/.env"
UPSTREAM="$ROOT/vendor/supabase-docker"

# ---- pre-flight checks ------------------------------------------------------
echo "== Phase 2: Stack bring-up =="

# 1. Phase 1 must have been run
if [ ! -f /etc/sysctl.d/99-lumo-hardening.conf ] 2>/dev/null; then
  echo "WARN: Phase 1 hardening sysctl file not found. Did you run verify-phase1.sh?" >&2
  echo "Continuing anyway — but the VPS may not be hardened." >&2
fi

# 2. .env must exist
if [ ! -f "$ENV_FILE" ]; then
  echo "FAIL: $ENV_FILE not found." >&2
  echo "  Run: sudo bash deploy/env/generate-env.sh <your-domain>" >&2
  exit 1
fi

# 3. No CHANGE_ME placeholders
if grep -q 'CHANGE_ME' "$ENV_FILE"; then
  echo "FAIL: .env still has CHANGE_ME placeholders:" >&2
  grep -n 'CHANGE_ME' "$ENV_FILE" >&2 || true
  echo "  Edit $ENV_FILE and fill all remaining values." >&2
  exit 1
fi

# 4. Upstream must be synced
if [ ! -d "$UPSTREAM" ] || [ ! -f "$UPSTREAM/docker-compose.yml" ]; then
  echo "FAIL: upstream Supabase docker-compose.yml not found at $UPSTREAM" >&2
  echo "  Run: sh scripts/sync-upstream.sh" >&2
  exit 1
fi

# 5. Compose version check
COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "0")
COMPOSE_MAJOR=$(echo "$COMPOSE_VERSION" | cut -d. -f1 | tr -d 'v')
COMPOSE_MINOR=$(echo "$COMPOSE_VERSION" | cut -d. -f2)
if [ "$COMPOSE_MAJOR" -lt 2 ] || { [ "$COMPOSE_MAJOR" -eq 2 ] && [ "$COMPOSE_MINOR" -lt 24 ]; }; then
  echo "FAIL: Docker Compose $COMPOSE_VERSION — need >= 2.24.4 for !override tag." >&2
  exit 1
fi
echo "OK: Docker Compose $COMPOSE_VERSION"

# 6. Manifest parity
echo "== verifying manifest =="
bash "$ROOT/scripts/verify-manifest.sh" || {
  echo "FAIL: manifest verification failed." >&2
  exit 1
}

# 7. Secret hygiene
echo "== checking secrets =="
bash "$ROOT/scripts/check-secrets.sh" || {
  echo "FAIL: secret hygiene check failed." >&2
  exit 1
}

# ---- pull images ------------------------------------------------------------
echo "== pulling pinned images =="
cd "$UPSTREAM"
export COMPOSE_FILE=docker-compose.yml:docker-compose.lumo.yml
export COMPOSE_ENV_FILES="$ENV_FILE"

docker compose --env-file "$ENV_FILE" pull 2>&1 | tail -20

# ---- record digests ---------------------------------------------------------
echo "== recording image digests =="
python3 "$ROOT/scripts/verify-manifest.sh" --record-digests 2>/dev/null || {
  echo "WARN: could not record digests automatically. Run manually after bring-up:" >&2
  echo "  python3 scripts/verify-manifest.sh --record-digests" >&2
}

# ---- start the stack --------------------------------------------------------
echo "== starting stack (this may take 30-60 seconds) =="
export LUMO_PHASE_APPROVED=phase2
sh "$ROOT/scripts/lumo.sh" start

# ---- wait for health --------------------------------------------------------
echo "== waiting for healthchecks =="
sleep 5

# Check each service's health status
FAILED_SERVICES=""
for svc in db auth rest storage studio supavisor; do
  STATUS=$(docker compose --env-file "$ENV_FILE" ps --format json "$svc" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health','unknown'))" 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then
    echo "OK    $svc: healthy"
  elif [ "$STATUS" = "no-healthcheck" ] || [ "$STATUS" = "unknown" ]; then
    echo "WARN  $svc: $STATUS (may still be starting)"
  else
    echo "FAIL  $svc: $STATUS"
    FAILED_SERVICES="$FAILED_SERVICES $svc"
  fi
done

# meta and db-config have no healthcheck — just check they're running
for svc in meta db-config; do
  STATE=$(docker compose --env-file "$ENV_FILE" ps --format json "$svc" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State','unknown'))" 2>/dev/null || echo "unknown")
  if [ "$STATE" = "running" ]; then
    echo "OK    $svc: running (no upstream healthcheck)"
  else
    echo "FAIL  $svc: $STATE"
    FAILED_SERVICES="$FAILED_SERVICES $svc"
  fi
done

if [ -n "$FAILED_SERVICES" ]; then
  echo "" >&2
  echo "FAIL: services not healthy:$FAILED_SERVICES" >&2
  echo "Check logs: sh scripts/lumo.sh logs <service>" >&2
  exit 1
fi

echo ""
echo "== stack is up =="
docker compose --env-file "$ENV_FILE" ps --format 'table {{.Name}}\t{{.Status}}\t{{.Health}}'
echo ""
echo "Next: run sudo bash deploy/stack/verify-phase2.sh"
