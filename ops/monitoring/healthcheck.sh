#!/usr/bin/env bash
# Lightweight health check. Prometheus/Grafana/Loki are DEFERRED until the VPS
# has measured capacity for them.
set -uo pipefail
ROOT="${LUMO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT" || exit 1
FAILED=0

echo "== container health =="
if command -v docker >/dev/null 2>&1 && docker compose ps --quiet >/dev/null 2>&1; then
  docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Health}}' || FAILED=1
  # meta and db-config have NO upstream healthcheck in this release: report as
  # no-healthcheck instead of pretending they are healthy.
  for svc in meta db-config; do
    echo "NOTE  $svc: no upstream healthcheck in self-hosted/v0.8.4 (not claimed healthy)"
  done
else
  echo "SKIP  docker/compose not available or stack not running"
fi

echo "== HTTPS ingress =="
if [ -n "${PROXY_DOMAIN:-}" ]; then
  if curl -fsS --max-time 10 "https://$PROXY_DOMAIN/auth/v1/health" -o /dev/null 2>/dev/null; then
    echo "OK    https://$PROXY_DOMAIN/auth/v1/health"
  else
    echo "WARN  auth health endpoint did not return 200 (verify the pinned release's path)"
  fi
else
  echo "SKIP  PROXY_DOMAIN not set"
fi

echo "== loopback-only enforcement =="
if command -v ss >/dev/null 2>&1; then
  LEAKS="$(ss -ltn 2>/dev/null | awk '$4 ~ /:(8000|5432|6543)$/ && $4 !~ /^127\.0\.0\.1:/ && $4 !~ /^\[::1\]:/ {print $4}')"
  if [ -n "$LEAKS" ]; then
    echo "FAIL  private port exposed on a non-loopback interface: $LEAKS"; FAILED=1
  else
    echo "OK    8000/5432/6543 are loopback-only"
  fi
else
  echo "SKIP  ss not available"
fi

echo "== disk =="
sh "$ROOT/ops/monitoring/disk-alert.sh" || FAILED=1

echo "== backup freshness =="
if [ -n "${LUMO_BACKUP_DESTINATION:-}" ] && command -v rclone >/dev/null 2>&1; then
  LATEST="$(rclone lsf "$LUMO_BACKUP_DESTINATION" --files-only 2>/dev/null | grep '^lumo-db-' | sort | tail -1)"
  [ -n "$LATEST" ] && echo "OK    latest backup artifact: $LATEST" || { echo "FAIL  no backup artifact found"; FAILED=1; }
else
  echo "SKIP  backup destination not configured"
fi

echo "== container logs rotate =="
UNROTATED="$(docker compose ps --quiet 2>/dev/null | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.LogConfig.Config.max-size}}' 2>/dev/null | grep -v '10m' || true)"
[ -z "$UNROTATED" ] && echo "OK    all containers use 10m x3 rotation" || { echo "WARN  $UNROTATED"; }

exit "$FAILED"
