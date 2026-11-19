# Lumo Base

A **free**, self-hosted, Supabase-compatible backend platform for internal applications.
One economical Ubuntu LTS VPS, Docker Compose, upstream Supabase services pinned to a tested release, PostgreSQL as the authoritative data and authorization layer.

> **Status:** Stage A — repository scaffold and Phase 0 architecture audit. **Nothing is deployed.** No VPS has been provisioned, no containers started, no cloud resources created, no money spent. Deployment remains behind the phase approval gates in [docs/ROADMAP.md](docs/ROADMAP.md).

> **Free by design.** Lumo Base has no billing, pricing, plans, tiers, subscriptions, invoices, quotas or metering anywhere in this repository. Monetization and a commercial control plane are explicitly deferred — see [docs/DEFERRED.md](docs/DEFERRED.md). Nothing here charges a user.

---

## What this is

- **Stage A (now):** one isolated Supabase-compatible environment serving the owner's own applications.
- **Stage B (later):** a commercial multi-project SaaS platform with a separate control plane. Not built, not scaffolded, not simulated.

Official upstream components are used as-is. Lumo Base adds only configuration, SQL, tests, scripts and documentation — no rewrites of GoTrue, PostgREST, Storage, Envoy or Studio.

## Quickstart (operator)

```bash
# 1. Fetch the pinned upstream docker/ configuration (envoy, db init, kong, etc.)
sh scripts/sync-upstream.sh

# 2. Create your local secrets file from the sanitized example
cp deploy/env/.env.example deploy/env/.env
#    ...fill every secret, then NEVER commit deploy/env/.env

# 3. Verify the pinned version manifest matches the vendored compose
sh scripts/verify-manifest.sh

# 4. Scan for accidentally committed secrets
sh scripts/check-secrets.sh

# 5. Start only after the relevant phase gate is approved
sh scripts/lumo.sh start
```

`scripts/lumo.sh` never starts anything by itself — it prints the resolved plan and requires an explicit `LUMO_PHASE_APPROVED=<phase>` acknowledgement. See [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Repository layout

| Path | Purpose |
| --- | --- |
| `deploy/compose/` | Vendored upstream compose (pinned) + Lumo Base override |
| `deploy/env/` | Sanitized environment example **only** — real `.env` is gitignored |
| `deploy/proxy/` | Caddy TLS ingress config |
| `deploy/versions.lock.json` | Release manifest: component versions, image tags, digests, source |
| `database/migrations/` | Versioned SQL migrations (application schema) |
| `database/policies/` | Roles, explicit GRANTs, RLS policies, tenant boundaries |
| `tests/integration/` | Real `supabase-js` conformance tests |
| `tests/security/` | Cross-user / cross-tenant authorization denial tests |
| `ops/backup/` | Logical DB backup, Storage object backup, isolated restore drill |
| `ops/monitoring/` | Lightweight health, disk and uptime checks |
| `docs/` | Architecture, versions, security, recovery, compatibility, roadmap |
| `web/index.html` | Standalone offline project console (no build step) |
| `scripts/` | Upstream sync, manifest verification, secret scan, phase-gated runner |
| `.workbuddy-ai/skills/` | Project-local skills for Lumo Base workflows |
| `.codebuddy/agents/` | Project-local expert roles (architect, DBA, SRE, AppSec, QA) |
| `AGENTS.md` | Which expert + skill to use for each phase |

## Non-negotiable rules

1. Prefer official upstream Supabase self-hosted components and documented configuration.
2. Do not rewrite upstream core services. Custom code is isolated, documented and tested.
3. Never invent environment variables, API endpoints, database schemas, JWT claims or gateway behavior. Verify against the pinned release in [docs/VERSIONS.md](docs/VERSIONS.md).
4. PostgreSQL is authoritative for data and authorization: roles + explicit GRANTs + RLS.
5. One VPS, Docker Compose. No Kubernetes, no MinIO, no multi-node without measured justification.
6. All secrets stay out of source control and logs.
7. Stop and request explicit approval before destructive operations, production changes, DNS changes, lossy migrations or spending money.
8. Report trade-offs, operational risks and recurring costs honestly. Never claim full Supabase compatibility without conformance evidence — see [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Verification

```bash
sh scripts/verify-manifest.sh     # pinned images match the vendored compose
sh scripts/check-secrets.sh       # no secret-shaped material in tracked files
sh ops/monitoring/healthcheck.sh  # service health (requires a running stack)
sh tests/security/run-security-tests.sh   # RLS isolation (requires DB)
cd tests/integration && npm ci && npm test  # real supabase-js conformance
```

Open `web/index.html` in a browser for the offline project console.

## License

Lumo Base original code and documentation: MIT. Vendored upstream files remain Apache-2.0 (c) Supabase — see [NOTICE.md](NOTICE.md).
