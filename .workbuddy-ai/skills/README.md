# Project-local skills

These skills live **in the repository**, so any coding agent opening `D:/projects/lumo base` gets Lumo Base-specific rules automatically. They are thin, focused guards that point to the deeper installed `ecc-*` skills.

| Skill | Trigger | Complementary installed skill |
| --- | --- | --- |
| `lumo-phase-gate` | Any deploy / destructive / DNS / spend decision | `ecc-delivery-gate` |
| `lumo-version-pin` | Any image, SDK or upstream release change | `ecc-docker-patterns`, `ecc-deployment-patterns`, `ecc-architecture-decision-records` |
| `lumo-rls-audit` | Any table, policy, GRANT, RPC or Storage policy | `ecc-postgres-patterns`, `ecc-database-migrations`, `ecc-agent-security-hardening` |
| `lumo-secret-hygiene` | `.env`, compose `environment:`, CI, logs, keys | `ecc-security-scan`, `ecc-security-review` |
| `lumo-restore-drill` | Backup changes, "backups work" claims | `ecc-deployment-patterns` |
| `lumo-compat-matrix` | SDK-facing changes, compatibility claims | `ecc-e2e-testing`, `ecc-ai-regression-testing`, `ecc-agent-eval` |
| `lumo-free-scope` | Anything that could introduce pricing/tiers/billing | `ecc-architecture-decision-records`, `ecc-cost-tracking` |

## Required workflow skill

`ecc-agentic-engineering` was explicitly requested for this project. Apply it to every unit of work: define completion criteria first, decompose into independently verifiable ~15-minute units, run a capability eval + regression eval baseline, implement, re-run and compare. Route model tiers by complexity (classification/boilerplate → lite, implementation → mid, architecture/root-cause → high). Track model, token estimate, retries, wall-clock time and success/failure per task.

## How to use

Load the relevant `lumo-*` skill **first**; it states the non-negotiable constraints and names the matching `ecc-*` skill for depth. Then consult `AGENTS.md` for the phase → expert + skill map.

## Adding a skill

1. Create `.workbuddy-ai/skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`).
2. State: purpose, trigger, numbered rules, done condition, anti-patterns, complementary skill.
3. Add a row above and a row in `AGENTS.md`'s phase map.
4. Keep it short enough to load without bloating context. No secrets, no invented env vars.
