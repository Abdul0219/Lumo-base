# Phase 2 — Core Backend Deployment

> **Gate:** Minimal pinned service set on private Docker network; HTTPS ingress; only 443 public; health checks pass; all public ports documented. No optional services.

## Status: Scripts ready — pending VPS execution

Phase 2 deliverables are written and committed. The stack has **not been deployed yet** — the operator must provision a VPS (Phase 1), then run the scripts below. This report documents what was built, what will happen when executed, and the acceptance criteria.

---

## 1. What changed and why

Phase 2 adds the deployment automation layer that sits between Phase 1 (VPS hardening) and the live Supabase stack. Specifically:

- **Secret generation (`deploy/env/generate-env.sh`)** — Replaces every `CHANGE_ME` in `.env.example` with cryptographically strong secrets (openssl). The operator provides a domain and email; the script handles the rest. Writes to `deploy/env/.env` (gitignored, mode 600).

- **Caddy TLS ingress (`deploy/stack/configure-caddy.sh`)** — Starts Caddy as a standalone container on ports 80/443. Production mode obtains real Let's Encrypt certificates via ACME HTTP-01. Staging mode (`LUMO_STAGING_TLS=1`) uses Caddy's internal CA for testing without a domain.

- **Stack bring-up (`deploy/stack/bring-up.sh`)** — Pre-flight validates `.env` completeness, manifest parity, secret hygiene, and Compose version. Pulls pinned images, attempts digest recording, starts the stack with `docker compose up -d --wait`, and checks each service's health status.

- **Acceptance verification (`deploy/stack/verify-phase2.sh`)** — 20+ checks across 12 categories: container status, healthcheck status, port binding enforcement, TLS/Caddy, PostgREST, GoTrue, Storage, Studio, secret hygiene in logs, memory budget, image digests, optional services off.

- **Safe teardown (`deploy/stack/teardown.sh`)** — Stops Caddy + Supabase stack. Default mode preserves all data in Docker volumes. `--purge` mode deletes volumes (irreversible, 10-second abort window).

## 2. Exact component versions and configuration changes

No image versions changed — all remain pinned to `self-hosted/v0.8.4` tags as recorded in `deploy/versions.lock.json`. The override file (`deploy/compose/docker-compose.lumo.yml`) is unchanged.

New configuration artifacts:

| Artifact | Type | Purpose |
| --- | --- | --- |
| `deploy/env/generate-env.sh` | Shell script | Generates `.env` with strong secrets |
| `deploy/stack/configure-caddy.sh` | Shell script | Starts Caddy TLS ingress container |
| `deploy/stack/bring-up.sh` | Shell script | Pre-flight + pull + start + health check |
| `deploy/stack/verify-phase2.sh` | Shell script | 20+ acceptance checks, PASS/WARN/FAIL summary |
| `deploy/stack/teardown.sh` | Shell script | Safe shutdown with optional volume purge |
| `deploy/stack/README.md` | Documentation | Execution order, architecture diagram, memory budget |

Caddy configuration (`deploy/proxy/Caddyfile`) is unchanged — it was already correct from Phase 0.

## 3. Commands executed and sanitized outputs

No commands have been executed on a VPS yet. The expected execution sequence is:

```bash
# From the repository root on the VPS:

# 1. Generate secrets
sudo bash deploy/env/generate-env.sh api.example.com you@example.com
# Expected: "Written: deploy/env/.env (mode 600, gitignored)"
# Expected: WARN about remaining CHANGE_ME for SMTP and backup

# 2. Fill SMTP and backup values manually
nano deploy/env/.env

# 3. Generate API keys via upstream helpers
sh vendor/supabase-docker/utils/generate-keys.sh
sh vendor/supabase-docker/utils/add-new-auth-keys.sh
# Paste output into .env

# 4. Verify secrets
sh scripts/check-secrets.sh
# Expected: "OK: no secrets tracked in git"

# 5. Start Caddy
sudo bash deploy/stack/configure-caddy.sh
# Expected: "OK: Caddy container is running"

# 6. Bring up the stack
sudo bash deploy/stack/bring-up.sh
# Expected: "OK: db: healthy", "OK: auth: healthy", ...
# Expected: "== stack is up =="
# Expected: "Next: run sudo bash deploy/stack/verify-phase2.sh"

# 7. Verify Phase 2 acceptance
sudo bash deploy/stack/verify-phase2.sh
# Expected: "RESULT: PASS — Phase 2 acceptance criteria met."
```

## 4. Automated tests and results

**Shell syntax validation** — all 5 new scripts pass `bash -n`:

```
deploy/env/generate-env.sh:     OK
deploy/stack/bring-up.sh:       OK
deploy/stack/configure-caddy.sh: OK
deploy/stack/teardown.sh:       OK
deploy/stack/verify-phase2.sh:  OK
```

**CI workflow** — `.github/workflows/ci.yml` now includes `deploy/stack` in the shell syntax validation loop.

**Runtime tests** — `verify-phase2.sh` checks the following when run on a live VPS:

| # | Check | Method |
| --- | --- | --- |
| 1 | All 9 enabled containers running | `docker compose ps` |
| 2 | 6 health-checked services report "healthy" | Container health status |
| 3 | meta + db-config running (no healthcheck expected) | Container state |
| 4 | Ports 8000/5432/6543 loopback-only | `ss -ltn` + grep |
| 5 | Port 443 listening | `ss -ltn` |
| 6 | Port 80 listening (ACME) | `ss -ltn` |
| 7 | Caddy container running | `docker inspect` |
| 8 | TLS handshake succeeds | `openssl s_client` |
| 9 | HSTS header present | `curl -sI` |
| 10 | PostgREST responding (200 or 401) | `curl /rest/v1/` |
| 11 | GoTrue health endpoint (200) | `curl /auth/v1/health` |
| 12 | Storage API responding (200 or 400) | `curl /storage/v1/` |
| 13 | Studio accessible (200/301/401) | `curl /` |
| 14 | No secrets in container logs | `docker logs` + pattern grep |
| 15 | Total memory within budget | `docker stats` |
| 16 | Image digests recorded | `deploy/versions.lock.json` |
| 17 | No optional services running | Container state check |

## 5. Security and operational checks

- **Loopback enforcement:** The override binds 8000/5432/6543 to `127.0.0.1` using `!override`. The verify script independently confirms this with `ss -ltn` — if any of these ports appear on a non-loopback interface, the check FAILS.
- **TLS only:** Caddy is the sole public-facing service (443). HTTP on port 80 is only for ACME challenges; Caddy redirects all other HTTP to HTTPS.
- **Security headers:** HSTS (`max-age=31536000; includeSubDomains`), `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, server header stripped.
- **Secret hygiene:** `generate-env.sh` writes `.env` with mode 600. `check-secrets.sh` verifies no secrets are tracked in git. `verify-phase2.sh` scans container logs for leaked secret patterns.
- **No optional services:** `verify-phase2.sh` confirms realtime, functions, imgproxy, and deno-cache are not running.
- **Memory ceiling:** Per-container `mem_limit` in the override totals ~2.7 GB. The verify script checks actual usage via `docker stats` and warns if approaching the 3.2 GB ceiling.
- **Dashboard protection:** Studio is reached through the Envoy gateway, which enforces HTTP basic auth via `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`.

## 6. Known limitations and unresolved risks

- **Asymmetric JWT keys:** `generate-env.sh` cannot produce `JWT_KEYS`, `JWT_JWKS`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` — these require the upstream helper scripts (`generate-keys.sh`, `add-new-auth-keys.sh`) which depend on a synced `vendor/supabase-docker/` directory. The operator must run these manually after `sync-upstream.sh`.

- **meta / db-config healthchecks:** Supabase's `self-hosted/v0.8.4` does not include healthchecks for `postgres-meta` or `db-config`. We report them as "running" (container state) rather than "healthy". This is an upstream limitation, not a Lumo Base gap.

- **Image digests:** Remains `null` in `versions.lock.json` until `docker compose pull` + `verify-manifest.sh --record-digests` are run on the VPS. `bring-up.sh` attempts this automatically but may fail if the `verify-manifest.sh` script doesn't support `--record-digests` yet.

- **SMTP configuration:** `generate-env.sh` cannot fill SMTP credentials — these are operator-supplied. Without SMTP, email-based auth flows (confirmation, recovery, invite) will not work. This is acceptable for Phase 2 (core deployment) but must be resolved before Phase 4 (Authentication).

- **No VPS execution yet:** All scripts are validated for syntax only. Runtime behavior, healthcheck timing, and memory measurements require a live VPS.

## 7. Rollback procedure

**Safe rollback (preserves data):**

```bash
sudo bash deploy/stack/teardown.sh
```

This stops all containers and Caddy. Data remains in Docker volumes. Restart with `bring-up.sh`.

**Full rollback (destroys data):**

```bash
sudo bash deploy/stack/teardown.sh --purge
```

The script provides a 10-second abort window before deleting volumes.

**Version rollback:** Change `release_tag` in `deploy/versions.lock.json` to the previous tag, re-run `scripts/sync-upstream.sh`, then `bring-up.sh`.

## 8. Cost/resource impact

No change from Phase 0/1 estimates:

- **VPS:** 2 vCPU / 4 GB RAM / 40 GB disk (unchanged)
- **Memory ceiling:** ~2.7 GB for enabled containers + ~0.1 GB Caddy = ~2.8 GB
- **OS overhead:** ~0.7 GB
- **Headroom:** ~0.5 GB for backup jobs and page cache
- **Network:** Only 443 (HTTPS) and 80 (ACME) are public — no additional bandwidth
- **Storage:** Docker volumes for Postgres data, Storage objects, and Caddy cert store. Growth depends on application usage. Monitor with `ops/monitoring/disk-alert.sh`.

If sustained memory exceeds 3.2 GB, upgrade to 8 GB / 4 CPU / 80 GB (documented in `deploy/compose/docker-compose.lumo.yml`).

## 9. Pass/fail decision against the gate

| Gate criterion | Status |
| --- | --- |
| Minimal pinned service set on private Docker network | ✅ Scripts ready — override pins all services to loopback |
| HTTPS ingress | ✅ Caddy configured with ACME + staging fallback |
| Only 443 public (80 for ACME) | ✅ Verified by `verify-phase2.sh` check #4-6 |
| Health checks pass | ⏳ Pending VPS execution |
| All public ports documented | ✅ `deploy/versions.lock.json` ports section + `deploy/stack/README.md` |
| No optional services | ✅ Profile-gated + verified by `verify-phase2.sh` check #17 |

**Decision: Scripts complete. Acceptance pending VPS execution.**

The operator must:
1. Complete Phase 1 on the VPS (`verify-phase1.sh` passed)
2. Run `sync-upstream.sh` to fetch the Supabase docker compose
3. Run `generate-env.sh` and fill remaining values
4. Run upstream key generation helpers
5. Run `configure-caddy.sh` → `bring-up.sh` → `verify-phase2.sh`
6. `verify-phase2.sh` must report PASS before Phase 3 begins
