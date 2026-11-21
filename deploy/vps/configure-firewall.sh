#!/usr/bin/env bash
# Phase 1 — UFW firewall configuration
# Run as root after setup-operator.sh.
#
# Rules:
#   - Default deny incoming, default allow outgoing.
#   - Allow SSH (22) — restricted to operator IPs if LUMO_OPERATOR_IPS is set.
#   - Allow HTTP (80) — ACME HTTP-01 challenge only.
#   - Allow HTTPS (443) — the only public application port.
#   - DENY everything else, including 8000, 5432, 6543.
#
set -euo pipefail

OPERATOR_IPS="${LUMO_OPERATOR_IPS:-}"

echo "== Phase 1: firewall configuration =="

# ---------------------------------------------------------------- defaults
echo "[1/5] setting default policies"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward

# ---------------------------------------------------------------- SSH (22)
echo "[2/5] configuring SSH access (port 22)"
if [ -n "$OPERATOR_IPS" ]; then
    IFS=',' read -ra IPS <<< "$OPERATOR_IPS"
    for ip in "${IPS[@]}"; do
        ip=$(echo "$ip" | xargs)  # trim whitespace
        echo "  allowing SSH from $ip"
        ufw allow from "$ip" to any port 22 proto tcp comment 'SSH operator'
    done
else
    echo "  WARNING: LUMO_OPERATOR_IPS not set. SSH open to all."
    echo "  Set LUMO_OPERATOR_IPS=\"203.0.113.10,203.0.113.11\" and re-run"
    echo "  for production-grade SSH restriction."
    ufw allow 22/tcp comment 'SSH (unrestricted — set LUMO_OPERATOR_IPS)'
fi

# ---------------------------------------------------------------- HTTP (80) — ACME only
echo "[3/5] allowing HTTP (80) for ACME HTTP-01 challenge"
ufw allow 80/tcp comment 'ACME HTTP-01 challenge'

# ---------------------------------------------------------------- HTTPS (443) — public
echo "[4/5] allowing HTTPS (443) — the only public application port"
ufw allow 443/tcp comment 'HTTPS public ingress (Caddy)'

# ---------------------------------------------------------------- enable + report
echo "[5/5] enabling firewall"
ufw --force enable
ufw status verbose

echo ""
echo "== Explicitly denied ports (verified not open) =="
for port in 8000 5432 6543 3000 8080 9999 5000 4000; do
    if ufw status | grep -qE "^${port}/tcp"; then
        echo "  FAIL: port $port is open — should be denied"
    else
        echo "  OK:   port $port is not open"
    fi
done

echo ""
echo "NEXT: sh deploy/vps/install-docker.sh"
