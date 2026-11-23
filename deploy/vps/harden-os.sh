#!/usr/bin/env bash
# Phase 1 — VPS OS hardening
# Run as root on a fresh Ubuntu LTS VPS.
# This script is idempotent: it can be re-run safely.
#
# What it does:
#   1. Updates all system packages to latest security patches.
#   2. Installs essential utilities (curl, git, jq, ufw, fail2ban, unattended-upgrades).
#   3. Enables automatic security updates.
#   4. Configures fail2ban for SSH protection.
#   5. Disables password-based SSH login (key-only).
#   6. Disables root SSH login.
#   7. Sets timezone and enables NTP time synchronization.
#
# What it does NOT do:
#   - Does not install Docker (that is install-docker.sh).
#   - Does not create the operator user (that is setup-operator.sh).
#   - Does not open any application ports (firewall is configured separately).
#   - Does not provision the VPS, change DNS, or spend money.
#
set -euo pipefail

echo "== Phase 1: OS hardening =="

# ---------------------------------------------------------------- 1. packages
echo "[1/7] updating system packages"
apt-get update -qq
apt-get upgrade -y
apt-get install -y -qq \
  curl git jq ufw fail2ban unattended-upgrades \
  ca-certificates gnupg lsb-release zstd \
  software-properties-common

# ---------------------------------------------------------------- 2. auto security updates
echo "[2/7] enabling automatic security updates"
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}:${distro_codename}-updates";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

# ---------------------------------------------------------------- 3. fail2ban
echo "[3/7] configuring fail2ban for SSH"
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = systemd
EOF
systemctl enable fail2ban
systemctl restart fail2ban

# ---------------------------------------------------------------- 4. SSH hardening
echo "[4/7] hardening SSH (key-only, no root login)"
SSHD_CONFIG="/etc/ssh/sshd_config"
# Backup before changing
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

set_sshd() {
    local key="$1" value="$2"
    if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
        sed -i "s/^#*${key}.*/${key} ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

set_sshd PasswordAuthentication no
# Allow root via key only until operator is created; setup-operator.sh
# will switch this to 'no' after verifying operator SSH access works.
set_sshd PermitRootLogin prohibit-password
set_sshd PubkeyAuthentication yes
set_sshd MaxAuthTries 3
set_sshd LoginGraceTime 30
set_sshd AllowAgentForwarding no
set_sshd AllowTcpForwarding no
set_sshd X11Forwarding no

# Validate before restarting
sshd -t
# Ubuntu 24.04 uses 'ssh' service name; older versions use 'sshd'
systemctl restart ssh 2>/dev/null || systemctl restart sshd

# ---------------------------------------------------------------- 5. timezone + NTP
echo "[5/7] setting timezone and enabling time sync"
timedatectl set-timezone "${LUMO_TIMEZONE:-UTC}"
timedatectl set-ntp true
systemctl enable systemd-timesyncd
systemctl restart systemd-timesyncd

# ---------------------------------------------------------------- 6. kernel hardening
echo "[6/7] applying kernel hardening sysctls"
cat > /etc/sysctl.d/99-lumo-hardening.conf <<'EOF'
# IP forwarding enabled (required by Docker)
net.ipv4.ip_forward = 1
# Reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
# Ignore ICMP broadcasts (smurf attack prevention)
net.ipv4.icmp_echo_ignore_broadcasts = 1
# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
# Log martians
net.ipv4.conf.all.log_martians = 1
# Ignore ICMP redirect
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
# Protect against SYN floods
net.ipv4.tcp_syncookies = 1
# Restrict dmesg to kernel users
kernel.dmesg_restrict = 1
# Restrict kernel pointers
kernel.kptr_restrict = 2
EOF
sysctl --system

# ---------------------------------------------------------------- 7. report
echo "[7/7] hardening complete"
echo ""
echo "== Verification =="
echo "SSH config:"
sshd -T | grep -E '^(passwordauthentication|permitrootlogin|pubkeyauthentication|maxauthtries)'
echo ""
echo "fail2ban:"
fail2ban-client status sshd 2>/dev/null || echo "  (fail2ban will be active after next login attempt)"
echo ""
echo "Time sync:"
timedatectl status | grep -E '(Time zone|NTP service|synchronized)'
echo ""
echo "Auto-updates:"
cat /etc/apt/apt.conf.d/20auto-upgrades
echo ""
echo "Kernel hardening:"
sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter net.ipv4.tcp_syncookies
echo ""
echo "NEXT: sh deploy/vps/setup-operator.sh"
echo "THEN: sh deploy/vps/configure-firewall.sh"
echo "THEN: sh deploy/vps/install-docker.sh"
