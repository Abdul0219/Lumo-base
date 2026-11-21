#!/usr/bin/env bash
# configure-caddy.sh — Set up Caddy as TLS ingress for the Supabase stack.
#
# Caddy runs as a standalone container (not part of the upstream compose)
# and reverse-proxies to the Envoy gateway on 127.0.0.1:8000.
#
# Two modes:
#   1. Production (default): Caddy obtains real Let's Encrypt certificates
#      via HTTP-01 challenge on port 80. Requires a real domain + DNS.
#   2. Staging (LUMO_STAGING_TLS=1): Caddy uses an internal CA
#      (self-signed) for testing without a real domain.
#
# Usage:
#   sudo bash deploy/stack/configure-caddy.sh
#
# Env vars (from deploy/env/.env):
#   PROXY_DOMAIN   — the domain Caddy serves (e.g., api.example.com)
#   CERTBOT_EMAIL  — Let's Encrypt notification email
#   API_GW_HTTP_PORT — upstream gateway port (default 8000)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/env/.env"
CADDYFILE="$ROOT/deploy/proxy/Caddyfile"

# ---- load env ---------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  echo "FAIL: $ENV_FILE not found. Run deploy/env/generate-env.sh first." >&2
  exit 1
fi

# Source env vars we need (safe subset)
set -a
. "$ENV_FILE"
set +a

if [ -z "${PROXY_DOMAIN:-}" ] || [ "$PROXY_DOMAIN" = "your-domain.example.com" ]; then
  echo "FAIL: PROXY_DOMAIN is not set or still has the placeholder value." >&2
  echo "  Set it in deploy/env/.env to your real domain." >&2
  exit 1
fi

API_PORT="${API_GW_HTTP_PORT:-8000}"
STAGING="${LUMO_STAGING_TLS:-0}"

echo "== Caddy TLS ingress configuration =="
echo "  domain  : $PROXY_DOMAIN"
echo "  gateway : 127.0.0.1:$API_PORT"
echo "  mode    : $([ "$STAGING" = "1" ] && echo "staging (internal CA)" || echo "production (Let's Encrypt)")"

# ---- create Caddy data directory --------------------------------------------
CADDY_DATA="/opt/lumo-base/caddy/data"
CADDY_CONFIG="/opt/lumo-base/caddy/config"
CADDY_LOGS="/opt/lumo-base/caddy/logs"

sudo mkdir -p "$CADDY_DATA" "$CADDY_CONFIG" "$CADDY_LOGS"
sudo chown -R "$(id -u):$(id -g)" "$CADDY_DATA" "$CADDY_CONFIG" "$CADDY_LOGS"

# ---- prepare Caddyfile with staging overrides if needed ---------------------
RUN_CADDYFILE="/tmp/lumo-caddyfile"

if [ "$STAGING" = "1" ]; then
  # In staging mode, use Caddy's internal CA (no Let's Encrypt)
  sed 's/{$PROXY_DOMAIN}/:443/' "$CADDYFILE" | \
    sed 's/email {.*}/tls internal/' > "$RUN_CADDYFILE"
  echo "  NOTE: staging mode — browser will show a cert warning. Use for testing only."
else
  cp "$CADDYFILE" "$RUN_CADDYFILE"
fi

# ---- check for existing Caddy container -------------------------------------
EXISTING=$(docker ps -a --filter "name=lumo-caddy" --format '{{.ID}}' 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  echo "== stopping existing Caddy container =="
  docker stop lumo-caddy 2>/dev/null || true
  docker rm lumo-caddy 2>/dev/null || true
fi

# ---- run Caddy --------------------------------------------------------------
echo "== starting Caddy =="
docker run -d \
  --name lumo-caddy \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v "$RUN_CADDYFILE:/etc/caddy/Caddyfile:ro" \
  -v "$CADDY_DATA:/data" \
  -v "$CADDY_CONFIG:/config" \
  -v "$CADDY_LOGS:/var/log/caddy" \
  --network host \
  --memory="128m" \
  --memory-swap="128m" \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  caddy:2.8.4 caddy run --config /etc/caddy/Caddyfile --adapter caddyfile

sleep 3

# ---- verify -----------------------------------------------------------------
CADDY_STATUS=$(docker inspect --format '{{.State.Status}}' lumo-caddy 2>/dev/null || echo "not-found")
if [ "$CADDY_STATUS" = "running" ]; then
  echo "OK: Caddy container is running"
else
  echo "FAIL: Caddy container is $CADDY_STATUS" >&2
  docker logs lumo-caddy 2>&1 | tail -20
  exit 1
fi

# Check port binding
if command -v ss >/dev/null 2>&1; then
  echo "== port bindings =="
  ss -ltn | grep -E ':(80|443)\b' || echo "WARN: 80/443 not found in ss output"
fi

echo ""
if [ "$STAGING" = "1" ]; then
  echo "Caddy is running in staging mode."
  echo "Test: curl -k https://localhost/ — expect a 502 if the stack isn't up yet."
else
  echo "Caddy is running. It will obtain certificates for $PROXY_DOMAIN on first request."
  echo "Test: curl -sI https://$PROXY_DOMAIN/ — expect TLS handshake + 200/502."
fi
echo ""
echo "Logs: docker logs -f lumo-caddy"
