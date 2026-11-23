# Changelog

All notable changes to Lumo Base. Format follows Keep a Changelog; versions are release-manifest tags, not marketing releases.

## [0.1.0] - 2026-11-18 — Stage A repository scaffold (Phase 0)

Created the complete repository scaffold from the architecture + master engineering prompt. **Nothing deployed.**

### Added
- Pinned release manifest for Supabase `self-hosted/v0.8.4` (`deploy/versions.lock.json`, `docs/VERSIONS.md`) with verified image tags and ports.
- Vendored upstream `docker-compose.yml` (verbatim + provenance header) and a Lumo Base override that binds 8000/5432/6543 to loopback, gates optional services behind the `optional` profile, sets memory ceilings and log rotation.
- Sanitized `deploy/env/.env.example` using only verified upstream variable names; `scripts/check-secrets.sh` guard.
- Caddy TLS ingress with security headers; 443 as the only public port.
- Application schema + roles/GRANTs/RLS with a SECURITY DEFINER membership helper and RPC-only workspace creation.
- Real `supabase-js@2.119.1` conformance suite and SQL RLS isolation suite.
- Logical DB + Storage object backup scripts and an isolated restore drill.
- Lightweight health / disk / backup-freshness monitoring.
- Phase 0 architecture audit, security baseline, compatibility contract, recovery, operations, roadmap and upstream provenance docs.
- Standalone offline project console (`web/index.html`), Vercel (Geist) design system, quality-reviewed and WCAG AA compliant.
- Project-local experts (`.codebuddy/agents/`) and skills (`.workbuddy-ai/skills/`) plus `AGENTS.md` phase routing.
- Phase-gated runner `scripts/lumo.sh`; upstream sync + manifest verification scripts.
- CI workflow validating JSON/YAML, secret hygiene, manifest parity and console constraints.

### Deliberately not included
Billing, pricing, plans, tiers, payment, subscriptions, invoices, quotas, metering, commercial control plane, multi-project provisioning. Deferred — see `docs/DEFERRED.md`.

### Known gaps
- Image digests not yet recorded (filled after `docker compose pull`).
- `meta` and `db-config` have no upstream healthcheck in this release.
- All compatibility rows are `untested — not claimed` until the conformance suite runs against a live stack.
- RPO/RTO targets await owner decision.

## [0.4.0] - 2026-11-23 — Phase 3 database & authorization (scripts ready, not yet executed)

### Added
- **`deploy/database/apply-migrations.sh`** — Applies all 4 SQL files (2 migrations + 2 policy files) in strict order with `ON_ERROR_STOP=1` and `--single-transaction`. Post-apply verification queries RLS status, SECURITY DEFINER function safety, and GRANT summary.
- **`deploy/database/create-test-users.sh`** — Creates 3 test users (A, B, C) via GoTrue admin API. Never INSERTs into auth.users directly. Handles existing users by fetching UUID. Writes to `/tmp/lumo-test-users.env` (mode 600).
- **`deploy/database/verify-phase3.sh`** — 30+ acceptance checks across 15 categories: schema, tables+RLS, FORCE RLS, indexes, SECURITY DEFINER safety (search_path + PUBLIC revocation), GRANT verification (anon=0, authenticated=limited, service_role=all), policy completeness (6 by name), anon policy absence, UPDATE USING+WITH CHECK, default privileges, RLS isolation suite.
- **`deploy/database/README.md`** — Execution order, trust model diagram, full check list, rollback procedure, known gaps.

### Changed
- `docs/ROADMAP.md` updated: Phase 2 marked scripts-ready, Phase 3 marked ← current position.
- CI workflow includes `deploy/database` scripts in shell syntax validation.

### Status
Scripts are ready to execute on a VPS after Phase 2 is verified. The SQL migrations and policies are unchanged from Phase 0 — Phase 3 adds deployment automation and acceptance verification.

### Known gaps
- HS256 JWT only — asymmetric keys (JWT_KEYS, JWT_JWKS) are Phase 4.
- Test users are not auto-cleaned — they persist in auth.users for re-use.
- No Storage-level RLS — bucket policies are Phase 5.
- auth.uid() claim path must be verified against pinned supabase/postgres init SQL.

## [0.3.0] - 2026-11-21 — Phase 2 core backend deployment (scripts ready, not yet executed)

### Added
- **`deploy/env/generate-env.sh`** — Generates all required secrets (POSTGRES_PASSWORD, JWT_SECRET, SECRET_KEY_BASE, VAULT_ENC_KEY, PG_META_CRYPTO_KEY, DASHBOARD_USERNAME/PASSWORD) using openssl. Writes `deploy/env/.env` with mode 600. Operator provides domain and email; script fills the rest. Reports remaining manual steps (SMTP, backup destination, upstream key generation).
- **`deploy/stack/configure-caddy.sh`** — Starts Caddy as a standalone TLS ingress container on ports 80/443. Production mode obtains real Let's Encrypt certificates via ACME HTTP-01. Staging mode (`LUMO_STAGING_TLS=1`) uses Caddy's internal CA for testing without a domain. Idempotent — stops and recreates if already running.
- **`deploy/stack/bring-up.sh`** — Pre-flight: validates `.env` (no CHANGE_ME), manifest parity, secret hygiene, Compose version ≥ 2.24.4. Pulls pinned images, attempts digest recording, starts stack with `docker compose up -d --wait`, checks each service health. Reports OK/WARN/FAIL per service.
- **`deploy/stack/verify-phase2.sh`** — Comprehensive acceptance checker with 20+ checks across 12 categories: container status (9 services), healthcheck status (6 + 2 no-healthcheck), port binding enforcement (loopback only), TLS handshake, HSTS header, PostgREST, GoTrue, Storage, Studio, secret hygiene in container logs, memory budget, image digests, optional services off. Produces PASS/WARN/FAIL summary with exit code.
- **`deploy/stack/teardown.sh`** — Safe shutdown: stops Caddy + Supabase stack. Default mode preserves all data in Docker volumes. `--purge` mode deletes volumes with a 10-second abort window.
- **`deploy/stack/README.md`** — Execution order guide, architecture diagram, memory budget table, staging mode instructions, rollback procedure.

### Changed
- `docs/ROADMAP.md` updated: Phase 1 marked as scripts ready, Phase 2 marked ← current position.
- CI workflow includes `deploy/stack` scripts in shell syntax validation.

### Status
Scripts are configuration-first and ready to execute on a target VPS. The operator must complete Phase 1 on the VPS first, then run the Phase 2 scripts in order. No stack has been deployed yet.

### Known gaps
- Asymmetric JWT keys (JWT_KEYS, JWT_JWKS, SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY) require upstream helper scripts — cannot be generated by `generate-env.sh` alone.
- Image digests remain null until `docker compose pull` + `verify-manifest.sh --record-digests` are run on the VPS.
- SMTP configuration is operator-supplied — `generate-env.sh` cannot fill it.
- `meta` and `db-config` have no upstream healthcheck — verified as "running" but not "healthy".

## [0.2.0] - 2026-11-21 — Phase 1 VPS preparation (scripts ready, not yet executed)

### Added
- **`deploy/vps/harden-os.sh`** — OS hardening: apt update/upgrade, unattended security updates, fail2ban, SSH key-only auth (no root, max 3 tries), NTP time sync, kernel sysctls (IP forwarding off, RP filter, syncookies, source routing off, dmesg restrict, kptr restrict).
- **`deploy/vps/setup-operator.sh`** — Creates non-root operator user (`lumo`), grants sudo, installs SSH key from `LUMO_OPERATOR_SSH_KEY` env var.
- **`deploy/vps/configure-firewall.sh`** — UFW: default deny incoming, allow 22 (optionally restricted to operator IPs), 80 (ACME), 443 (HTTPS). Explicitly verifies 8000/5432/6543 are NOT open.
- **`deploy/vps/install-docker.sh`** — Docker Engine + Compose plugin from official Docker APT repo. Verifies Compose ≥ 2.24.4 (`!override` support). Hardens daemon: log rotation, live-restore, no userland-proxy, no-new-privileges, `icc: false`.
- **`deploy/vps/verify-phase1.sh`** — Comprehensive acceptance check: OS, updates, SSH hardening (4 checks), fail2ban, UFW (8 checks incl. denied ports), Docker, Compose version, NTP, operator user (4 checks), kernel hardening, no app containers/ports. Produces PASS/WARN/FAIL summary with exit code.
- **`deploy/vps/README.md`** — Execution order guide, per-script summary, security deltas table, rollback procedure.
- **`docs/PHASE1.md`** — Phase 1 gate report with all 9 required items: what changed, versions, commands, tests, security checks, limitations, rollback, cost impact, pass/fail decision.
- CI workflow now includes `deploy/vps` scripts in shell syntax validation.

### Changed
- `docs/ROADMAP.md` updated: Phase 0 marked ✅ approved, Phase 1 marked ← current position.

### Status
Scripts are configuration-first and ready to execute on a target Ubuntu LTS VPS. The operator must provision the VPS and run the scripts before Phase 1 acceptance can be verified. No VPS has been provisioned yet.

### Known gaps
- Same as prior phases: image digests pending `docker compose pull`; `meta`/`db-config` healthcheck gap; compatibility rows untested; RPO/RTO await owner decision.
- Phase 1 scripts are written but not yet executed against a real VPS — `verify-phase1.sh` must pass on the target host before Phase 2 begins.

## [0.1.1] - 2026-11-21 — Phase 0 scaffold hardening

### Added
- Caddy image (`caddy:2.8.4`) pinned in `deploy/versions.lock.json` and `docs/VERSIONS.md` — previously referenced in docs but missing from the version manifest.
- `.editorconfig` for consistent formatting across editors and CI.
- CI step verifying the Caddy image is pinned and not using a floating `latest` tag.

### Changed
- Web console design-system comment corrected: "Phase 2" → "Phase 0 scaffold" (the console was built as part of the Phase 0 scaffold, not a Phase 2 deliverable).
- `web/dist/lumo-base-console.html` updated to match `web/index.html`.

### Known gaps
- Same as 0.1.0: image digests pending `docker compose pull`; `meta`/`db-config` healthcheck gap; compatibility rows untested; RPO/RTO await owner decision.
