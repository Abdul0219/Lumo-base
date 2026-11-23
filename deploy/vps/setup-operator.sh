#!/usr/bin/env bash
# Phase 1 — Create the non-root operator user
# Run as root after harden-os.sh.
#
# The operator user:
#   - Has a home directory and bash shell.
#   - Can sudo to root with a password.
#   - Has SSH key access (you must provide the public key).
#   - Is the user that runs Docker Compose and all Lumo Base operations.
#
set -euo pipefail

OPERATOR="${LUMO_OPERATOR:-lumo}"
SSH_KEY="${LUMO_OPERATOR_SSH_KEY:-}"

echo "== Phase 1: operator user setup =="

# ---------------------------------------------------------------- create user
if id "$OPERATOR" &>/dev/null; then
    echo "[1/4] user '$OPERATOR' already exists"
else
    echo "[1/4] creating operator user '$OPERATOR'"
    useradd -m -s /bin/bash "$OPERATOR"
    # Set a temporary password (operator should change it with passwd)
    TEMP_PASS="${LUMO_OPERATOR_TEMP_PASS:-$(openssl rand -base64 18)}"
    echo "$OPERATOR:$TEMP_PASS" | chpasswd
    echo "  Temporary password set for $OPERATOR (change with 'passwd $OPERATOR')"
    echo "  Temp pass: $TEMP_PASS"
fi

# ---------------------------------------------------------------- sudo access
echo "[2/4] granting sudo access"
usermod -aG sudo "$OPERATOR"
# Ensure sudo requires a password (not passwordless)
echo "$OPERATOR ALL=(ALL:ALL) ALL" > /etc/sudoers.d/"$OPERATOR"
chmod 440 /etc/sudoers.d/"$OPERATOR"
visudo -c -f /etc/sudoers.d/"$OPERATOR"

# ---------------------------------------------------------------- SSH key
echo "[3/4] configuring SSH key access"
OPERATOR_HOME="$(getent passwd "$OPERATOR" | cut -d: -f6)"
mkdir -p "$OPERATOR_HOME/.ssh"
chmod 700 "$OPERATOR_HOME/.ssh"

if [ -n "$SSH_KEY" ]; then
    echo "$SSH_KEY" > "$OPERATOR_HOME/.ssh/authorized_keys"
    chmod 600 "$OPERATOR_HOME/.ssh/authorized_keys"
    chown -R "$OPERATOR:$OPERATOR" "$OPERATOR_HOME/.ssh"
    echo "  SSH key installed."
elif [ ! -s "$OPERATOR_HOME/.ssh/authorized_keys" ]; then
    echo "  WARNING: no SSH key provided."
    echo "  Set LUMO_OPERATOR_SSH_KEY=\"ssh-ed25519 AAAA...\" and re-run,"
    echo "  or manually add your public key to ~$OPERATOR/.ssh/authorized_keys"
    echo "  You CANNOT log in as $OPERATOR until an SSH key is installed"
    echo "  (password login was disabled by harden-os.sh)."
else
    echo "  authorized_keys already populated."
fi

# ---------------------------------------------------------------- report
echo "[4/4] verification"
echo "  user:      $(id "$OPERATOR")"
echo "  home:      $OPERATOR_HOME"
echo "  shell:     $(getent passwd "$OPERATOR" | cut -d: -f7)"
echo "  sudo:      $(sudo -l -U "$OPERATOR" 2>/dev/null | tail -1)"
echo "  ssh key:   $([ -s "$OPERATOR_HOME/.ssh/authorized_keys" ] && echo 'installed' || echo 'MISSING — add before next step')"
echo ""
echo "NEXT: sh deploy/vps/configure-firewall.sh"
echo "THEN: sh deploy/vps/install-docker.sh"
echo ""
echo "IMPORTANT: Test SSH login as $OPERATOR from your workstation BEFORE closing"
echo "the root session. If you cannot log in as $OPERATOR, fix the SSH key first."
echo ""
echo "After verifying operator access, root SSH will be fully disabled."
