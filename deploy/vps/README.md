# deploy/vps/ — Phase 1 VPS preparation

Scripts to harden and prepare a fresh Ubuntu LTS VPS for Lumo Base. **Run in order.** Each script is idempotent and safe to re-run.

## Prerequisites

- A fresh Ubuntu 24.04 LTS (Noble) or 22.04 LTS (Jammy) VPS.
- Root access via SSH (or a user with sudo).
- Your workstation's SSH public key ready for the operator user.

## Execution order

```bash
# 1. As root: harden the OS
LUMO_TIMEZONE=UTC sh deploy/vps/harden-os.sh

# 2. As root: create the operator user
LUMO_OPERATOR=lumo LUMO_OPERATOR_SSH_KEY="ssh-ed25519 AAAA..." sh deploy/vps/setup-operator.sh

# 3. As root: configure the firewall
LUMO_OPERATOR_IPS="203.0.113.10,203.0.113.11" sh deploy/vps/configure-firewall.sh

# 4. As operator (with sudo): install Docker + Compose
sh deploy/vps/install-docker.sh

# 5. As operator: verify everything
sh deploy/vps/verify-phase1.sh
```

## What each script does

| Script | Runs as | What it does |
| --- | --- | --- |
| `harden-os.sh` | root | System update, auto security updates, fail2ban, SSH hardening (key-only, no root), NTP, kernel sysctls |
| `setup-operator.sh` | root | Creates the non-root operator user, grants sudo, installs SSH key |
| `configure-firewall.sh` | root | UFW: default deny, allow 22 (operator IPs), 80 (ACME), 443 (HTTPS). Denies 8000/5432/6543 and all app ports |
| `install-docker.sh` | operator (sudo) | Installs Docker Engine + Compose plugin from official Docker APT repo, adds operator to docker group, hardens daemon |
| `verify-phase1.sh` | operator | Runs all Phase 1 acceptance checks and produces a pass/fail report |

## What is NOT done in Phase 1

- No Supabase containers started (Phase 2).
- No application services exposed (Phase 2).
- No database migrations applied (Phase 3).
- No DNS changes or TLS certificates (Phase 2).
- No backups configured (Phase 8).

## Security deltas from upstream defaults

| Default | Lumo Base |
| --- | --- |
| SSH password auth on | **Off** (key-only) |
| Root SSH login | **Denied** |
| fail2ban | **Active** (5 retries → 1h ban) |
| UFW | **Active**, default deny |
| 8000/5432/6543 exposed | **Denied** at firewall + loopback at compose |
| Docker log rotation | **10 MiB × 3** (daemon + per-container) |
| Docker live restore | **Enabled** |
| Docker inter-container ICC | **Disabled** (use explicit networks) |
| Auto security updates | **Enabled** |

## Rollback

If Phase 1 needs to be rolled back:

1. **SSH hardening:** restore the backup at `/etc/ssh/sshd_config.bak.*` and `systemctl restart sshd`.
2. **Firewall:** `ufw disable` then re-apply the previous rules.
3. **Docker:** `sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-compose-plugin` and remove `/etc/apt/sources.list.d/docker.list`.
4. **Operator user:** `sudo userdel -r lumo` (after verifying no services depend on it).
5. **Kernel sysctls:** remove `/etc/sysctl.d/99-lumo-hardening.conf` and `sysctl --system`.

The safest rollback is to destroy the VPS and start fresh — Phase 1 changes are host-level, not data-level.
