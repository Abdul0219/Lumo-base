# Project-local expert roster

Five expert roles derived directly from the master engineering prompt's "ROLE AND RESPONSIBILITY" (senior platform architect, PostgreSQL DBA, DevOps/SRE engineer, application-security engineer, and QA). They live in the repository so the guidance travels with the code.

| Expert | Owns | Phase |
| --- | --- | --- |
| `platform-architect` | Architecture, service inventory, request path, memory budget, ADRs, trade-offs | 0, 6 |
| `postgres-dba` | Migrations, roles, GRANTs, RLS, tenant boundaries, restore verification | 3 |
| `devops-sre` | Compose overrides, TLS, resource limits, backups, monitoring, upgrades, rollback | 1, 2, 8 |
| `appsec-engineer` | JWT/API-key separation, key lifecycle, port exposure, secrets, isolation tests | 2-5 |
| `compatibility-qa` | supabase-js conformance, compatibility matrix, eval-first regression | 7 |

## How they work together

- **All cross-role information flows through the owner's review**, never silently between roles. Each role writes its output into the repo (`docs/`, `database/`, `tests/`, `deploy/`, `ops/`) where the next role can read it.
- Phase gates are enforced by `lumo-phase-gate` and `scripts/lumo.sh`. No role may start a phase without explicit approval.
- Disagreements are escalated to the owner as a written trade-off, not resolved by quietly changing a config value.

## Shared non-negotiables (every role)

1. Prefer official upstream components and documented configuration.
2. Do not rewrite upstream core services.
3. Never invent env vars, endpoints, schemas, JWT claims or gateway behaviour.
4. PostgreSQL is authoritative for data and authorization.
5. One VPS, Docker Compose.
6. Secrets never in git or logs.
7. Stop for approval before destructive / production / DNS / spend actions.
8. Honest trade-offs, risks and costs; no compatibility claims without evidence.
9. **Lumo Base is free.** No billing, pricing, plans, tiers, quotas, metering or commercial control plane.

See `AGENTS.md` for the complete phase → expert + skill map and the list of complementary installed `ecc-*` skills.
