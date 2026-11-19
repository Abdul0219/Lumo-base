---
name: lumo-phase-gate
description: Enforce Lumo Base phase approval gates before any deployment, destructive migration, DNS change, key rotation, production change or spend. Use before running scripts/lumo.sh start/stop/optional or touching live infrastructure.
---

# Lumo Base — Phase gate

**Purpose:** stop and request explicit approval before anything irreversible. This is a non-negotiable rule from the master engineering prompt.

## Trigger
Any of: `scripts/lumo.sh start|stop|optional`, `docker compose up`, `psql` against a live DB, `ALTER/DROP/TRUNCATE`, DNS or `PROXY_DOMAIN` change, firewall change, signing-key rotation or revocation, backup credential rotation, provisioning a VPS, or spending money.

## Procedure
1. Identify the phase from `docs/ROADMAP.md`. Confirm its acceptance gate is defined.
2. Run `sh scripts/lumo.sh plan` — **no changes** — and record the resolved services, versions and public ports.
3. Verify prerequisites: `sh scripts/verify-manifest.sh`, `sh scripts/check-secrets.sh`, `sh ops/monitoring/healthcheck.sh`.
4. Take a verified restore point (`ops/backup/restore-drill.sh`) if data is involved.
5. **Stop.** Present to the owner: what changes, exact versions, commands, tests, security checks, known limitations, rollback procedure, cost/resource impact, and a clear pass/fail against the gate.
6. Only proceed after explicit approval. `scripts/lumo.sh` requires `LUMO_PHASE_APPROVED=<phase>` and will refuse otherwise.

## Done condition
An approved gate with a written report containing all nine items in `docs/ROADMAP.md` §"What every phase report must contain".

## Anti-patterns
- Silently starting containers "just to test".
- Treating a passing CI job as approval.
- Skipping the rollback plan because "it's only config".
- Assuming Phase 10 (commercial design) is authorized — it is not.

Complementary skill: `ecc-delivery-gate`.
