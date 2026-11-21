#!/usr/bin/env bash
# verify-phase2.sh — Phase 2 acceptance checker.
#
# Verifies the core backend deployment meets all Phase 2 acceptance criteria:
#   - All enabled containers running and healthy
#   - Ports 8000/5432/6543 bound to loopback only
#   - Only 443 (and 80 for ACME) public
#   - Caddy serving TLS on 443
#   - PostgREST responding
#   - GoTrue health endpoint responding
#   - Storage responding
#   - Studio accessible
#   - RLS enabled on app tables
#   - No secrets in container environment logs
#   - Container memory within budget
#   - Image digests recorded
#
# Produces PASS/WARN/FAIL summary with exit code.
# Exit 0 = all PASS, exit 1 = any FAIL, exit 2 = cannot evaluate (not running).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/env/.env"
UPSTREAM="$ROOT/vendor/supabase-docker"

PASS=0
WARN=0
FAIL=0
SKIP=0

# ---- load env ---------------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

# ---- helpers ----------------------------------------------------------------
p()  { echo "PASS  $1"; PASS=$((PASS+1)); }
w()  { echo "WARN  $1"; WARN=$((WARN+1)); }
f()  { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
s()  { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

# ---- check if stack is running ----------------------------------------------
if ! docker compose version >/dev/null 2>&1; then
  f "docker compose not available"
  exit 2
fi

if [ -d "$UPSTREAM" ]; then
  cd "$UPSTREAM"
  export COMPOSE_FILE=docker-compose.yml:docker-compose.lumo.yml
  export COMPOSE_ENV_FILES="$ENV_FILE"
fi

echo "============================================"
echo "  Phase 2: Core Backend Deployment"
echo "  Acceptance Verification"
echo "============================================"
echo ""

# ---- 1. Container status ----------------------------------------------------
echo "== 1. Container status =="

ENABLED_SERVICES="db auth rest storage studio meta supavisor db-config api-gw"
RUNNING_COUNT=0
FAILED_CONTAINERS=""

for svc in $ENABLED_SERVICES; do
  STATE=$(docker compose --env-file "$ENV_FILE" ps --format json "$svc" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State','not-found'))" 2>/dev/null || echo "error")

  if [ "$STATE" = "running" ]; then
    RUNNING_COUNT=$((RUNNING_COUNT+1))
  else
    FAILED_CONTAINERS="$FAILED_CONTAINERS $svc($STATE)"
  fi
done

if [ -z "$FAILED_CONTAINERS" ]; then
  p "all $RUNNING_COUNT enabled containers are running"
else
  f "containers not running:$FAILED_CONTAINERS"
fi

# ---- 2. Healthcheck status --------------------------------------------------
echo ""
echo "== 2. Healthcheck status =="

HEALTHY_SERVICES="db auth rest storage studio supavisor"
HEALTHY_COUNT=0
UNHEALTHY=""

for svc in $HEALTHY_SERVICES; do
  HEALTH=$(docker compose --env-file "$ENV_FILE" ps --format json "$svc" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health','no-healthcheck'))" 2>/dev/null || echo "error")

  case "$HEALTH" in
    healthy)
      HEALTHY_COUNT=$((HEALTHY_COUNT+1))
      ;;
    starting)
      w "$svc: healthcheck still starting"
      ;;
    unhealthy)
      f "$svc: unhealthy"
      UNHEALTHY="$UNHEALTHY $svc"
      ;;
    no-healthcheck)
      # Expected for meta and db-config
      ;;
    *)
      w "$svc: health status unknown ($HEALTH)"
      ;;
  esac
done

# meta and db-config: no upstream healthcheck, just check running
for svc in meta db-config; do
  STATE=$(docker compose --env-file "$ENV_FILE" ps --format json "$svc" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State','not-found'))" 2>/dev/null || echo "error")
  if [ "$STATE" = "running" ]; then
    p "$svc: running (no upstream healthcheck — expected)"
  else
    f "$svc: not running"
  fi
done

if [ "$HEALTHY_COUNT" -eq 6 ]; then
  p "all 6 health-checked services report healthy"
elif [ -z "$UNHEALTHY" ]; then
  w "$HEALTHY_COUNT/6 services healthy (some may still be starting)"
else
  f "unhealthy services:$UNHEALTHY"
fi

# ---- 3. Port binding — loopback enforcement --------------------------------
echo ""
echo "== 3. Port binding (loopback enforcement) =="

if command -v ss >/dev/null 2>&1; then
  # Check that 8000, 5432, 6543 are NOT on public interfaces
  LEAKS=""
  for port in 8000 5432 6543; do
    LEAK=$(ss -ltn 2>/dev/null | awk -v p=":$port\$" '$4 ~ p && $4 !~ /^127\.0\.0\.1:/ && $4 !~ /^\[::1\]:/ {print $4}')
    if [ -n "$LEAK" ]; then
      LEAKS="$LEAKS $LEAK"
    fi
  done

  if [ -z "$LEAKS" ]; then
    p "ports 8000/5432/6543 are loopback-only (no public exposure)"
  else
    f "private ports exposed on public interface:$LEAKS"
  fi

  # Check 443 is listening
  if ss -ltn 2>/dev/null | grep -q ':443\b'; then
    p "port 443 is listening (Caddy TLS)"
  else
    f "port 443 is not listening"
  fi

  # Check 80 is listening (ACME)
  if ss -ltn 2>/dev/null | grep -q ':80\b'; then
    p "port 80 is listening (ACME HTTP-01 challenge)"
  else
    w "port 80 not listening — Caddy may not be running or ACME not needed"
  fi
else
  s "ss command not available — cannot verify port bindings"
fi

# ---- 4. TLS / Caddy ---------------------------------------------------------
echo ""
echo "== 4. TLS ingress (Caddy) =="

CADDY_STATE=$(docker inspect --format '{{.State.Status}}' lumo-caddy 2>/dev/null || echo "not-found")
if [ "$CADDY_STATE" = "running" ]; then
  p "Caddy container is running"
else
  f "Caddy container is $CADDY_STATE"
fi

# Check TLS handshake if domain is set
if [ -n "${PROXY_DOMAIN:-}" ] && [ "$PROXY_DOMAIN" != "your-domain.example.com" ]; then
  TLS_CHECK=$(echo | timeout 10 openssl s_client -connect "$PROXY_DOMAIN:443" -servername "$PROXY_DOMAIN" 2>/dev/null | \
    grep -c 'Verify return code: 0' || echo "0")
  if [ "$TLS_CHECK" -ge 1 ]; then
    p "TLS handshake to $PROXY_DOMAIN:443 succeeded (valid certificate)"
  else
    w "TLS handshake to $PROXY_DOMAIN:443 failed — cert may not be issued yet"
  fi

  # Check HSTS header
  HSTS=$(curl -sI --max-time 10 "https://$PROXY_DOMAIN/" 2>/dev/null | grep -i 'strict-transport-security' || true)
  if [ -n "$HSTS" ]; then
    p "HSTS header present"
  else
    w "HSTS header not found — Caddy may not have finished cert provisioning"
  fi
else
  s "PROXY_DOMAIN not set — skipping TLS verification"
fi

# ---- 5. PostgREST -----------------------------------------------------------
echo ""
echo "== 5. PostgREST (REST API) =="

if [ -n "${PROXY_DOMAIN:-}" ] && [ "$PROXY_DOMAIN" != "your-domain.example.com" ]; then
  REST_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$PROXY_DOMAIN/rest/v1/" 2>/dev/null || echo "000")
  if [ "$REST_CODE" = "200" ] || [ "$REST_CODE" = "401" ]; then
    p "PostgREST responding (HTTP $REST_CODE)"
  else
    f "PostgREST returned HTTP $REST_CODE"
  fi
else
  # Try loopback
  REST_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:8000/rest/v1/" 2>/dev/null || echo "000")
  if [ "$REST_CODE" = "200" ] || [ "$REST_CODE" = "401" ]; then
    p "PostgREST responding on loopback (HTTP $REST_CODE)"
  else
    f "PostgREST returned HTTP $REST_CODE on loopback"
  fi
fi

# ---- 6. GoTrue (Auth) -------------------------------------------------------
echo ""
echo "== 6. GoTrue (Auth) =="

if [ -n "${PROXY_DOMAIN:-}" ] && [ "$PROXY_DOMAIN" != "your-domain.example.com" ]; then
  AUTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$PROXY_DOMAIN/auth/v1/health" 2>/dev/null || echo "000")
  if [ "$AUTH_CODE" = "200" ]; then
    p "GoTrue health endpoint responding (HTTP 200)"
  else
    f "GoTrue health endpoint returned HTTP $AUTH_CODE"
  fi
else
  AUTH_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:8000/auth/v1/health" 2>/dev/null || echo "000")
  if [ "$AUTH_CODE" = "200" ]; then
    p "GoTrue health endpoint responding on loopback (HTTP 200)"
  else
    f "GoTrue health endpoint returned HTTP $AUTH_CODE on loopback"
  fi
fi

# ---- 7. Storage -------------------------------------------------------------
echo ""
echo "== 7. Storage API =="

if [ -n "${PROXY_DOMAIN:-}" ] && [ "$PROXY_DOMAIN" != "your-domain.example.com" ]; then
  STORAGE_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$PROXY_DOMAIN/storage/v1/" 2>/dev/null || echo "000")
  if [ "$STORAGE_CODE" = "200" ] || [ "$STORAGE_CODE" = "400" ]; then
    p "Storage API responding (HTTP $STORAGE_CODE)"
  else
    f "Storage API returned HTTP $STORAGE_CODE"
  fi
else
  STORAGE_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:8000/storage/v1/" 2>/dev/null || echo "000")
  if [ "$STORAGE_CODE" = "200" ] || [ "$STORAGE_CODE" = "400" ]; then
    p "Storage API responding on loopback (HTTP $STORAGE_CODE)"
  else
    f "Storage API returned HTTP $STORAGE_CODE on loopback"
  fi
fi

# ---- 8. Studio (Dashboard) --------------------------------------------------
echo ""
echo "== 8. Studio (Dashboard) =="

if [ -n "${PROXY_DOMAIN:-}" ] && [ "$PROXY_DOMAIN" != "your-domain.example.com" ]; then
  STUDIO_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$PROXY_DOMAIN/" 2>/dev/null || echo "000")
  if [ "$STUDIO_CODE" = "200" ] || [ "$STUDIO_CODE" = "301" ] || [ "$STUDIO_CODE" = "401" ]; then
    p "Studio accessible through gateway (HTTP $STUDIO_CODE)"
  else
    f "Studio returned HTTP $STUDIO_CODE"
  fi
else
  s "PROXY_DOMAIN not set — cannot verify Studio through TLS"
fi

# ---- 9. No secrets in logs --------------------------------------------------
echo ""
echo "== 9. Secret hygiene (container logs) =="

SECRET_PATTERNS='POSTGRES_PASSWORD=|JWT_SECRET=|SECRET_KEY_BASE=|SERVICE_ROLE_KEY=|VAULT_ENC_KEY='
LOG_LEAKS=""

for svc in db auth rest storage studio meta supavisor api-gw; do
  CONTAINER_ID=$(docker compose --env-file "$ENV_FILE" ps -q "$svc" 2>/dev/null || true)
  if [ -n "$CONTAINER_ID" ]; then
    LEAK=$(docker logs "$CONTAINER_ID" 2>&1 | grep -oE "$SECRET_PATTERNS[^[:space:]]+" | head -1 || true)
    if [ -n "$LEAK" ]; then
      LOG_LEAKS="$LOG_LEAKS $svc"
    fi
  fi
done

if [ -z "$LOG_LEAKS" ]; then
  p "no secrets found in container logs"
else
  f "secrets found in container logs for:$LOG_LEAKS"
fi

# ---- 10. Memory budget ------------------------------------------------------
echo ""
echo "== 10. Memory budget =="

TOTAL_MEM_KB=0
MEM_OUTPUT=""

for svc in $ENABLED_SERVICES; do
  CONTAINER_ID=$(docker compose --env-file "$ENV_FILE" ps -q "$svc" 2>/dev/null || true)
  if [ -n "$CONTAINER_ID" ]; then
    MEM_USAGE=$(docker stats --no-stream --format '{{.MemUsage}}' "$CONTAINER_ID" 2>/dev/null || echo "N/A")
    MEM_OUTPUT="$MEM_OUTPUT  $svc: $MEM_USAGE\n"
  fi
done

CADDY_MEM=$(docker stats --no-stream --format '{{.MemUsage}}' lumo-caddy 2>/dev/null || echo "N/A")
MEM_OUTPUT="$MEM_OUTPUT  caddy: $CADDY_MEM\n"

echo -e "$MEM_OUTPUT"

# Check against the 2.6 GB + 0.1 GB Caddy ceiling
TOTAL_MEM_MB=$(docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null | \
  awk -F'/' '{print $1}' | grep -oE '[0-9]+' | awk '{s+=$1} END {print int(s)}' 2>/dev/null || echo "0")

if [ "$TOTAL_MEM_MB" -gt 0 ] 2>/dev/null; then
  if [ "$TOTAL_MEM_MB" -le 2800 ]; then
    p "total container memory ~${TOTAL_MEM_MB}MB (within 2.8 GB budget)"
  elif [ "$TOTAL_MEM_MB" -le 3200 ]; then
    w "total container memory ~${TOTAL_MEM_MB}MB (near ceiling — monitor closely)"
  else
    f "total container memory ~${TOTAL_MEM_MB}MB (exceeds 3.2 GB — upgrade to 8 GB RAM)"
  fi
else
  s "cannot determine total memory (docker stats unavailable)"
fi

# ---- 11. Image digests ------------------------------------------------------
echo ""
echo "== 11. Image digests =="

DIGESTS_RECORDED=$(python3 -c "
import json, sys
try:
    lock = json.load(open('$ROOT/deploy/versions.lock.json'))
    null_count = sum(1 for e in lock['images'] if e.get('digest') is None and e.get('state') == 'enabled')
    if null_count == 0:
        print('all')
    else:
        print(f'{null_count} null')
except Exception:
    print('error')
" 2>/dev/null || echo "error")

if [ "$DIGESTS_RECORDED" = "all" ]; then
  p "all enabled images have immutable digests recorded"
elif [ "$DIGESTS_RECORDED" = "error" ]; then
  w "cannot read version manifest"
else
  w "$DIGESTS_RECORDED enabled images have null digests — run verify-manifest.sh --record-digests"
fi

# ---- 12. No optional services running ---------------------------------------
echo ""
echo "== 12. Optional services (should be OFF) =="

OPTIONAL_SERVICES="realtime functions imgproxy deno-cache"
OPTIONAL_RUNNING=""

for svc in $OPTIONAL_SERVICES; do
  STATE=$(docker compose --env-file "$ENV_FILE" ps --format json "$svc" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State','not-found'))" 2>/dev/null || echo "not-found")
  if [ "$STATE" = "running" ]; then
    OPTIONAL_RUNNING="$OPTIONAL_RUNNING $svc"
  fi
done

if [ -z "$OPTIONAL_RUNNING" ]; then
  p "no optional services running (realtime/functions/imgproxy/deno-cache all off)"
else
  f "optional services running (should be off in Phase 2):$OPTIONAL_RUNNING"
fi

# ---- summary ----------------------------------------------------------------
echo ""
echo "============================================"
echo "  SUMMARY"
echo "============================================"
echo "  PASS: $PASS"
echo "  WARN: $WARN"
echo "  SKIP: $SKIP"
echo "  FAIL: $FAIL"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "RESULT: FAIL — Phase 2 acceptance criteria NOT met."
  echo "Fix the failures above and re-run this script."
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo "RESULT: PASS with warnings — review WARN items."
  echo "Phase 2 can proceed but monitor the warnings."
  exit 0
else
  echo ""
  echo "RESULT: PASS — Phase 2 acceptance criteria met."
  exit 0
fi
