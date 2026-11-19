# Lumo Base — agent & skill routing

This file tells any coding agent (human or AI) **which expert and which skill** to use for each phase of the project. It is part of the repository so the guidance travels with the code.

## Non-negotiable context

- Stage A only: one VPS, Docker Compose, upstream Supabase services, no commercial control plane.
- **Everything is free.** No billing, pricing, plans, tiers, subscriptions, invoices, quotas, metering or payment code. Deferred — see `docs/DEFERRED.md`.
- Never invent env vars, endpoints, schemas, JWT claims or gateway behavior. Check `deploy/versions.lock.json` and `docs/VERSIONS.md` first.
- Secrets never enter git or logs. Only `deploy/env/.env.example` is tracked.
- Phase gates are real. Do not deploy, migrate destructively, change DNS or spend money without explicit approval.

## Expert roster (`.codebuddy/agents/`)

| Expert | Owns | Typical trigger |
| --- | --- | --- |
| `platform-architect` | Architecture, service inventory, dependency map, request path, trade-offs, ADRs | Phase 0, any structural change |
| `postgres-dba` | Migrations, roles, GRANTs, RLS, tenant boundaries, query plans | Phase 3, `database/**` |
| `devops-sre` | Compose overrides, TLS ingress, resource limits, backups, monitoring, upgrades/rollback | Phases 1, 2, 8, `deploy/**`, `ops/**` |
| `appsec-engineer` | JWT/API-key separation, key rotation, secrets, port exposure, isolation tests | Phases 2-5, `tests/security/**` |
| `compatibility-qa` | supabase-js conformance, compatibility matrix, eval-first regression checks | Phase 7, `tests/integration/**` |

## Project-local skills (`.workbuddy-ai/skills/`)

| Skill | Use when |
| --- | --- |
| `lumo-phase-gate` | Before any change that could deploy, migrate, rotate keys or cost money |
| `lumo-version-pin` | Adding/upgrading any image, SDK or upstream release |
| `lumo-rls-audit` | Writing or reviewing any table, policy, GRANT or RPC |
| `lumo-secret-hygiene` | Touching `.env`, compose `environment:` blocks, CI or logs |
| `lumo-restore-drill` | Changing backup scripts or claiming backups work |
| `lumo-compat-matrix` | Changing any SDK-facing behavior or claiming compatibility |
| `lumo-free-scope` | Any feature that could introduce pricing, tiers, quotas or billing |

## Complementary installed skills (user-level, already available)

`ecc-agentic-engineering` (required workflow for this repo) · `ecc-docker-patterns` · `ecc-postgres-patterns` · `ecc-database-migrations` · `ecc-deployment-patterns` · `ecc-agent-security-hardening` · `ecc-security-review` · `ecc-architecture-decision-records` · `ecc-api-design` · `ecc-e2e-testing` · `ecc-ai-regression-testing` · `ecc-docs-governance` · `ecc-delivery-gate` · `ecc-cost-tracking`.

Load the relevant project-local skill first; it points to the matching `ecc-*` skill for depth.

## Phase → expert + skill map

| Phase | Expert | Skill(s) |
| --- | --- | --- |
| 0 Discovery & audit | `platform-architect` | `ecc-architecture-decision-records`, `lumo-version-pin` |
| 1 VPS prep | `devops-sre` | `lumo-phase-gate`, `ecc-deployment-patterns` |
| 2 Core backend | `devops-sre` + `appsec-engineer` | `lumo-version-pin`, `lumo-secret-hygiene`, `ecc-docker-patterns` |
| 3 Database & authorization | `postgres-dba` + `appsec-engineer` | `lumo-rls-audit`, `ecc-postgres-patterns`, `ecc-database-migrations` |
| 4 Authentication | `appsec-engineer` | `lumo-secret-hygiene`, `lumo-phase-gate` |
| 5 Storage | `devops-sre` | `lumo-rls-audit`, `lumo-restore-drill` |
| 6 Optional capabilities | `platform-architect` | `lumo-version-pin`, `lumo-free-scope` |
| 7 SDK compatibility | `compatibility-qa` | `lumo-compat-matrix`, `ecc-e2e-testing` |
| 8 Backup & hardening | `devops-sre` | `lumo-restore-drill`, `ecc-delivery-gate` |
| 9 Internal app staging | all | `lumo-phase-gate`, `ecc-ai-regression-testing` |
| 10 Future SaaS design | **deferred — do not start** | `lumo-free-scope` (scope guard only) |

## Eval-first requirement

Per `ecc-agentic-engineering`: define a capability eval and a regression eval before implementation, capture a baseline, implement, re-run and compare. For every change, name the done condition, the dominant risk, and the rollback step in the PR description.
