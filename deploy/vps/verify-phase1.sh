#!/usr/bin/env bash
# Phase 1 — Verification script
# Run as the operator user after all Phase 1 scripts have been executed.
#
# Verifies every Phase 1 acceptance gate criterion and produces a report
# suitable for the phase gate document.
#
set -uo pipefail

PASS=0
FAIL=0
WARN=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN+1)); }

echo "=========================================================="
echo "  Lumo Base — Phase 1 Verification Report"
echo "  Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  Host: $(hostname) ($(hostname -I 2>/dev/null || echo 'no-IP'))"
echo "=========================================================="
echo ""

# ---------------------------------------------------------------- OS
echo "== OS and packages =="
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "  OS: $PRETTY_NAME"
    case "$VERSION_CODENAME" in
        noble|jammy|focal) ok "Ubuntu LTS ($VERSION_CODENAME)" ;;
        *) fail "Not Ubuntu LTS (codename: $VERSION_CODENAME)" ;;
    esac
else
    fail "Cannot determine OS (no /etc/os-release)"
fi

echo ""
echo "== Package updates =="
if command -v apt >/dev/null 2>&1; then
    UPDATES="$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)"
    if [ "${UPDATES:-0}" -eq 0 ] 2>/dev/null; then
        ok "All packages up to date"
    else
        warn "$UPDATES packages have pending updates"
    fi
fi

echo ""
echo "== Automatic security updates =="
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    AUTO="$(grep 'APT::Periodic::Unattended-Upgrade' /etc/apt/apt.conf.d/20auto-upgrades | grep -o '[01]')"
    [ "$AUTO" = "1" ] && ok "Automatic security updates enabled" || fail "Automatic security updates NOT enabled"
else
    fail "20auto-upgrades config missing"
fi

echo ""
echo "== SSH hardening =="
if command -v sshd >/dev/null 2>&1; then
    SSHD_T="$(sshd -T 2>/dev/null)"
    echo "$SSHD_T" | grep -q '^passwordauthentication no' && ok "SSH password auth disabled" || fail "SSH password auth still enabled"
    ROOT_LOGIN="$(echo "$SSHD_T" | grep '^permitrootlogin' | awk '{print $2}')"
    case "$ROOT_LOGIN" in
        no) ok "SSH root login fully disabled" ;;
        prohibit-password|without-password) ok "SSH root login key-only ($ROOT_LOGIN)" ;;
        yes) fail "SSH root login fully enabled (should be restricted)" ;;
        *) fail "SSH root login unknown state: $ROOT_LOGIN" ;;
    esac
    echo "$SSHD_T" | grep -q '^pubkeyauthentication yes' && ok "SSH pubkey auth enabled" || fail "SSH pubkey auth not enabled"
    echo "$SSHD_T" | grep -q '^maxauthtries 3' && ok "SSH max auth tries = 3" || warn "SSH max auth tries not set to 3"
else
    warn "sshd not found (not on the VPS?)"
fi

echo ""
echo "== fail2ban =="
if command -v fail2ban-client >/dev/null 2>&1; then
    if fail2ban-client status sshd >/dev/null 2>&1; then
        ok "fail2ban sshd jail active"
        fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' | head -1 | xargs echo "  "
    else
        fail "fail2ban sshd jail not active"
    fi
else
    warn "fail2ban not installed"
fi

echo ""
echo "== Firewall (UFW) =="
if command -v ufw >/dev/null 2>&1; then
    STATUS="$(ufw status verbose 2>/dev/null)"
    echo "$STATUS" | grep -q 'Status: active' && ok "UFW firewall active" || fail "UFW firewall not active"
    echo "$STATUS" | grep -qE '22/tcp.*ALLOW' && ok "SSH (22) allowed" || fail "SSH (22) not allowed"
    echo "$STATUS" | grep -qE '80/tcp.*ALLOW' && ok "HTTP (80) allowed for ACME" || warn "HTTP (80) not allowed (needed for ACME)"
    echo "$STATUS" | grep -qE '443/tcp.*ALLOW' && ok "HTTPS (443) allowed" || warn "HTTPS (443) not allowed (needed for Phase 2)"
    echo "$STATUS" | grep -q 'Default: deny (incoming)' && ok "Default deny incoming" || fail "Default policy not deny incoming"
    # Verify private ports are NOT open
    for port in 8000 5432 6543; do
        echo "$STATUS" | grep -qE "^${port}/tcp" && fail "Port $port is open (should be denied)" || ok "Port $port denied"
    done
else
    warn "UFW not installed"
fi

echo ""
echo "== Docker Engine =="
if command -v docker >/dev/null 2>&1; then
    ok "Docker installed"
    DOCKER_VER="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unavailable')"
    echo "  Server: $DOCKER_VER"
    DOCKER_INFO="$(docker info 2>/dev/null || true)"
    echo "$DOCKER_INFO" | grep -q 'Logging Driver: json-file' && ok "Log driver: json-file" || warn "Log driver not json-file"
    echo "$DOCKER_INFO" | grep -q 'Live Restore Enabled: true' && ok "Live restore enabled" || warn "Live restore not enabled"
else
    fail "Docker not installed"
fi

echo ""
echo "== Docker Compose =="
if docker compose version >/dev/null 2>&1; then
    COMPOSE_VER="$(docker compose version --short 2>/dev/null | tr -d 'v')"
    COMPOSE_MAJOR="$(echo "$COMPOSE_VER" | cut -d. -f1)"
    COMPOSE_MINOR="$(echo "$COMPOSE_VER" | cut -d. -f2)"
    # Compose v2.24.4+ supports !override; v5.x+ obviously does too
    if [ "$COMPOSE_MAJOR" -gt 2 ] || { [ "$COMPOSE_MAJOR" -eq 2 ] && [ "$COMPOSE_MINOR" -ge 24 ]; }; then
        ok "Docker Compose $COMPOSE_VER (>= 2.24.4, !override supported)"
    else
        fail "Docker Compose $COMPOSE_VER (< 2.24.4, !override NOT supported)"
    fi
else
    fail "Docker Compose not installed"
fi

echo ""
echo "== Time synchronization =="
if command -v timedatectl >/dev/null 2>&1; then
    timedatectl status | grep -q 'NTP service: active' && ok "NTP time sync active" || warn "NTP time sync not active"
    timedatectl status | grep -q 'synchronized: yes' && ok "Time synchronized" || warn "Time not yet synchronized"
    echo "  $(timedatectl status | grep 'Time zone' | xargs)"
else
    warn "timedatectl not available"
fi

echo ""
echo "== Operator user =="
OPERATOR="${LUMO_OPERATOR:-lumo}"
if id "$OPERATOR" &>/dev/null; then
    ok "Operator user '$OPERATOR' exists"
    groups "$OPERATOR" | grep -q docker && ok "Operator in docker group" || warn "Operator not in docker group (log out/in may be needed)"
    sudo -l -U "$OPERATOR" 2>/dev/null | grep -q 'ALL' && ok "Operator has sudo" || warn "Operator sudo access not verified"
    [ -s "$(getent passwd "$OPERATOR" | cut -d: -f6)/.ssh/authorized_keys" ] && ok "Operator SSH key installed" || fail "Operator SSH key MISSING"
else
    fail "Operator user '$OPERATOR' does not exist"
fi

echo ""
echo "== Kernel hardening =="
if [ -f /etc/sysctl.d/99-lumo-hardening.conf ]; then
    ok "Kernel hardening sysctl file present"
    sysctl net.ipv4.ip_forward 2>/dev/null | grep -q '= 1' && ok "IP forwarding enabled (Docker requirement)" || warn "IP forwarding not enabled"
    sysctl net.ipv4.conf.all.rp_filter 2>/dev/null | grep -q '1' && ok "Reverse path filtering enabled" || warn "RP filter not set"
else
    warn "Kernel hardening config missing (run harden-os.sh)"
fi

echo ""
echo "== No application services exposed =="
if command -v docker >/dev/null 2>&1; then
    RUNNING="$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)"
    if [ "$RUNNING" -eq 0 ]; then
        ok "No application containers running"
    else
        warn "$RUNNING Docker containers running (should be 0 in Phase 1)"
        docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    fi
else
    ok "Docker not available — no containers can be running"
fi

# Check no app services are listening
if command -v ss >/dev/null 2>&1; then
    APP_PORTS="$(ss -ltn 2>/dev/null | awk '$4 ~ /:(8000|5432|6543|3000|8080|9999|5000)$/' || true)"
    if [ -z "$APP_PORTS" ]; then
        ok "No application ports listening (8000/5432/6543/3000/8080/9999/5000)"
    else
        fail "Application ports are listening:"
        echo "$APP_PORTS"
    fi
fi

echo ""
echo "=========================================================="
echo "  Phase 1 Verification Summary"
echo "  PASS: $PASS  WARN: $WARN  FAIL: $FAIL"
echo "=========================================================="
if [ "$FAIL" -gt 0 ]; then
    echo "  RESULT: FAIL — fix the failures above before proceeding to Phase 2"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo "  RESULT: PASS WITH WARNINGS — review warnings before proceeding"
    exit 0
else
    echo "  RESULT: PASS — Phase 1 acceptance gate met"
    echo "  Ready for Phase 2 (core backend deployment) upon approval"
    exit 0
fi
