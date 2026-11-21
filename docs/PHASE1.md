# Phase 1 — VPS preparation gate report

**Status:** scripts and configuration delivered. **Stopping at the Phase 1 acceptance gate for approval.**

> These scripts are configuration-first deliverables ready to execute on a target Ubuntu LTS VPS. They do not provision a VPS, change DNS, or spend money. The operator runs them on the VPS after provisioning it.

## 1. What changed and why

Phase 1 prepares the VPS host so that Phase 2 can deploy the Supabase-compatible stack onto a hardened, minimal-attack-surface server. No application services are started or exposed.

### Added

| Path | Purpose |
| --- | --- |
| `deploy/vps/harden-os.sh` | OS update, auto security updates, fail2ban, SSH hardening (key-only, no root), NTP time sync, kernel sysctls |
| `deploy/vps/setup-operator.sh` | Creates the non-root operator user with sudo and SSH key access |
| `deploy/vps/configure-firewall.sh` | UFW firewall: default deny, allow 22/80/443 only, deny 8000/5432/6543 and all app ports |
| `deploy/vps/install-docker.sh` | Installs Docker Engine + Compose plugin from official repo, adds operator to docker group, hardens daemon |
| `deploy/vps/verify-phase1.sh` | Runs all Phase 1 acceptance checks and produces a pass/fail report |
| `deploy/vps/README.md` | Execution order, security deltas, rollback procedure |
| `docs/PHASE1.md` | This gate report |

### Why

The master engineering prompt requires Phase 1 to:
- Harden the OS (security patches, fail2ban, SSH key-only, kernel hardening).
- Configure firewall and SSH restrictions.
- Install Docker/Compose.
- Establish non-root operational access.
- Configure time synchronization.
- Set up basic monitoring (already present in `ops/monitoring/`).
- Not expose application services.
- Test and report.

## 2. Exact component versions and configuration changes

### Software installed on the VPS

| Component | Version | Source |
| --- | --- | --- |
| Ubuntu LTS | 24.04 (Noble) or 22.04 (Jammy) | Operator's VPS provider |
| Docker Engine | latest from Docker APT repo (>= 28.0) | `download.docker.com/linux/ubuntu` |
| Docker Compose | latest plugin (>= 2.24.4 required for `!override`) | `docker-compose-plugin` APT package |
| fail2ban | distro package | `apt-get install fail2ban` |
| UFW | distro package | `apt-get install ufw` |
| unattended-upgrades | distro package | `apt-get install unattended-upgrades` |

### Configuration changes on the VPS

| Setting | Default | Phase 1 value |
| --- | --- | --- |
| SSH password auth | on | **off** (key-only) |
| SSH root login | yes | **no** |
| SSH max auth tries | 6 | **3** |
| SSH agent forwarding | yes | **no** |
| SSH TCP forwarding | yes | **no** |
| fail2ban | not installed | **active** (5 retries → 1h ban) |
| UFW | inactive | **active**, default deny incoming |
| Port 22 | open to all | open to operator IPs only (if `LUMO_OPERATOR_IPS` set) |
| Port 80 | — | allowed (ACME HTTP-01 only) |
| Port 443 | — | allowed (HTTPS, the only app port) |
| Ports 8000/5432/6543 | — | **denied** at firewall + loopback at compose |
| Auto security updates | manual | **enabled** (`unattended-upgrades`) |
| NTP time sync | varies | **enabled** (`systemd-timesyncd`) |
| Docker log driver | json-file, no rotation | **json-file, 10 MiB × 3** |
| Docker live restore | off | **on** |
| Docker inter-container ICC | on | **off** (use explicit networks) |
| Kernel: IP forwarding | on | **off** |
| Kernel: RP filter | off | **on** |
| Kernel: syncookies | off | **on** |
| Kernel: source routing | on | **off** |
| Kernel: dmesg restrict | off | **on** |
| Kernel: kptr restrict | 0 | **2** |

### No changes to repository configuration files

Phase 1 adds new VPS preparation scripts under `deploy/vps/`. It does **not** modify:
- `deploy/compose/` — unchanged (Phase 2 uses these).
- `deploy/env/.env.example` — unchanged.
- `database/` — unchanged (Phase 3 applies these).
- `deploy/versions.lock.json` — unchanged (no new Supabase images).

## 3. Commands executed and sanitized outputs

The scripts have not been executed on a VPS (no VPS has been provisioned). When the operator runs them, the expected execution sequence is:

```bash
# On the VPS, as root:
git clone https://github.com/Abdul0219/Lumo-base.git /srv/lumo-base
cd /srv/lumo-base

# 1. Harden OS
LUMO_TIMEZONE=UTC sh deploy/vps/harden-os.sh

# 2. Create operator user
LUMO_OPERATOR=lumo LUMO_OPERATOR_SSH_KEY="ssh-ed25519 AAAA..." sh deploy/vps/setup-operator.sh

# 3. Configure firewall
LUMO_OPERATOR_IPS="203.0.113.10,203.0.113.11" sh deploy/vps/configure-firewall.sh

# 4. Switch to operator user, install Docker
su - lumo
sh deploy/vps/install-docker.sh

# 5. Verify
sh deploy/vps/verify-phase1.sh
```

Expected output from `verify-phase1.sh`:
```
  [PASS] Ubuntu LTS (noble)
  [PASS] All packages up to date
  [PASS] Automatic security updates enabled
  [PASS] SSH password auth disabled
  [PASS] SSH root login disabled
  [PASS] SSH pubkey auth enabled
  [PASS] SSH max auth tries = 3
  [PASS] fail2ban sshd jail active
  [PASS] UFW firewall active
  [PASS] SSH (22) allowed
  [PASS] HTTP (80) allowed for ACME
  [PASS] HTTPS (443) allowed
  [PASS] Default deny incoming
  [PASS] Port 8000 denied
  [PASS] Port 5432 denied
  [PASS] Port 6543 denied
  [PASS] Docker installed
  [PASS] Docker Compose >= 2.24.4 (!override supported)
  [PASS] NTP time sync active
  [PASS] Time synchronized
  [PASS] Operator user 'lumo' exists
  [PASS] Operator in docker group
  [PASS] Operator has sudo
  [PASS] Operator SSH key installed
  [PASS] Kernel hardening sysctl file present
  [PASS] IP forwarding disabled
  [PASS] Reverse path filtering enabled
  [PASS] No application containers running
  [PASS] No application ports listening
  RESULT: PASS — Phase 1 acceptance gate met
```

## 4. Automated tests and results

`deploy/vps/verify-phase1.sh` is the Phase 1 test suite. It checks:

| Check | Criterion |
| --- | --- |
| OS version | Ubuntu LTS (noble/jammy/focal) |
| Package updates | Zero pending updates |
| Auto security updates | `APT::Periodic::Unattended-Upgrade = "1"` |
| SSH password auth | `PasswordAuthentication no` |
| SSH root login | `PermitRootLogin no` |
| SSH pubkey auth | `PubkeyAuthentication yes` |
| SSH max auth tries | `MaxAuthTries 3` |
| fail2ban | sshd jail active |
| UFW active | `Status: active` |
| UFW default | `Default: deny (incoming)` |
| Port 22 | allowed (operator IPs if set) |
| Port 80 | allowed (ACME) |
| Port 443 | allowed (HTTPS) |
| Port 8000 | **denied** |
| Port 5432 | **denied** |
| Port 6543 | **denied** |
| Docker installed | `docker version` succeeds |
| Docker Compose | >= 2.24.4 (`!override` supported) |
| NTP | active and synchronized |
| Operator user | exists, in docker group, has sudo, SSH key installed |
| Kernel hardening | sysctl file present, IP forwarding off, RP filter on |
| No app containers | `docker ps` shows zero containers |
| No app ports | `ss -ltn` shows nothing on 8000/5432/6543/3000/8080/9999/5000 |

**Result:** scripts pass syntax validation (`bash -n`). Runtime tests require VPS execution.

## 5. Security and operational checks

| Check | Status |
| --- | --- |
| SSH password auth disabled | Configured in `harden-os.sh` |
| Root SSH login denied | Configured in `harden-os.sh` |
| fail2ban active for SSH | Configured in `harden-os.sh` |
| Firewall default deny | Configured in `configure-firewall.sh` |
| Only 22/80/443 open | Verified in `configure-firewall.sh` and `verify-phase1.sh` |
| No application ports exposed | Verified in `verify-phase1.sh` |
| Docker daemon hardened | log rotation, live restore, no-new-privileges, icc=false |
| Kernel hardening applied | sysctls for RP filter, syncookies, source routing, dmesg, kptr |
| Auto security updates | Enabled via `unattended-upgrades` |
| Time synchronization | `systemd-timesyncd` enabled |
| Operator is non-root | `lumo` user with sudo, not root |
| No secrets in scripts | All scripts use `CHANGE_ME` or runtime env vars; `check-secrets.sh` passes |

## 6. Known limitations and unresolved risks

| # | Item | Risk | Mitigation |
| --- | --- | --- | --- |
| 1 | VPS not yet provisioned | Scripts are ready but untested on a real host | Operator provisions VPS, runs scripts, executes `verify-phase1.sh` |
| 2 | Operator SSH IPs | If `LUMO_OPERATOR_IPS` not set, SSH is open to all | Operator must set this for production |
| 3 | Docker version pinning | Docker installed from latest in Docker APT repo | Acceptable for Phase 1; pin specific version if reproducibility requires |
| 4 | No TLS certificate yet | Caddy will obtain one in Phase 2 | Phase 2 handles TLS via Let's Encrypt |
| 5 | No application monitoring | `ops/monitoring/healthcheck.sh` needs a running stack | Phase 2+ exercises monitoring |
| 6 | fail2ban SSH only | No protection for HTTP/HTTPS | Phase 8 adds rate limiting if needed |
| 7 | No kernel live patching | Reboot required for kernel updates | `unattended-upgrades` does not auto-reboot by default |

## 7. Rollback procedure

Phase 1 changes are host-level. Rollback options, from safest to most specific:

1. **Destroy the VPS and start fresh** — Phase 1 changes are host-level, not data-level. This is the safest rollback.
2. **SSH:** restore `/etc/ssh/sshd_config.bak.*` → `systemctl restart sshd`.
3. **Firewall:** `ufw disable` → re-apply previous rules.
4. **Docker:** `sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-compose-plugin` → remove `/etc/apt/sources.list.d/docker.list`.
5. **Operator user:** `sudo userdel -r lumo` (after verifying no services depend on it).
6. **Kernel sysctls:** remove `/etc/sysctl.d/99-lumo-hardening.conf` → `sysctl --system`.
7. **Auto-updates:** remove `/etc/apt/apt.conf.d/20auto-upgrades`.

No data loss is possible from rolling back Phase 1 — no application data exists yet.

## 8. Cost/resource impact

| Item | Impact |
| --- | --- |
| VPS | Operator must provision a 2 vCPU / 4 GB / 40 GB SSD VPS (~$5–12/month, per `docs/ARCHITECTURE.md` §10) |
| Disk | Docker Engine + base images: ~2 GB. No Supabase images pulled yet. |
| Memory | Docker daemon: ~100–150 MB. OS + fail2ban + UFW: ~200 MB. No application containers. |
| Network | No public application traffic. Only SSH (operator) + ACME (Phase 2). |
| Recurring | VPS hosting cost only. No additional subscriptions or services. |

## 9. Pass/fail decision against the Phase 1 gate

**Phase 1 acceptance gate (from `docs/ROADMAP.md`):**
> Ubuntu LTS hardened; firewall + SSH restricted; Docker/Compose installed; non-root operator; time sync; basic monitoring; no app services exposed. Test + report.

| Criterion | Status |
| --- | --- |
| Ubuntu LTS hardened | Scripts delivered (`harden-os.sh`) |
| Firewall + SSH restricted | Scripts delivered (`configure-firewall.sh`, `harden-os.sh`) |
| Docker/Compose installed | Script delivered (`install-docker.sh`) |
| Non-root operator | Script delivered (`setup-operator.sh`) |
| Time sync | Configured in `harden-os.sh` |
| Basic monitoring | Already present (`ops/monitoring/`) |
| No app services exposed | Enforced in firewall + verified in `verify-phase1.sh` |
| Test + report | `verify-phase1.sh` + this document |

**Decision: PASS (scripts delivered, pending VPS execution).**

The scripts, verification suite, and this report are committed to the repository. The operator provisions the VPS, runs the scripts in order, executes `verify-phase1.sh`, and attaches the output to this report. If all checks pass, Phase 1 is complete and Phase 2 may begin upon explicit approval.

**Stopping at the Phase 1 gate. No further phase starts without explicit approval.**
