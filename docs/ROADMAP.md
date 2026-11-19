# Roadmap and phase acceptance gates

Stage A only. **Every phase stops at its gate and waits for explicit approval.** The gate-command messages live in the source document; `scripts/lumo.sh` enforces the same discipline programmatically via `LUMO_PHASE_APPROVED`.

> **Scope guard:** Lumo Base is free. There is no billing, pricing, plans, tiers, payment, quotas or metering anywhere. Monetization and a commercial control plane are deferred to a later phase — see `docs/DEFERRED.md`. Phase 10 is a *design placeholder*, not work to start.

| Phase | Goal | Acceptance gate |
| --- | --- | --- |
| **0** | Discovery & architecture audit | Proposal delivered (`docs/ARCHITECTURE.md`). No code, no install, no deploy. **Stop for approval.** ← current position |
| 1 | VPS preparation | Ubuntu LTS hardened; firewall + SSH restricted; Docker/Compose installed; non-root operator; time sync; basic monitoring; no app services exposed. Test + report. |
| 2 | Core backend deployment | Minimal pinned service set on private Docker network; HTTPS ingress; only 443 public; health checks pass; all public ports documented. No optional services. |
| 3 | Database & authorization | Migrations, roles, GRANTs, RLS applied; positive + negative isolation tests pass (`tests/security/`). |
| 4 | Authentication | GoTrue configured; JWT signing keys with IDs; login, refresh, logout, expiry, invalid signature, rotation and revocation tested. |
| 5 | Storage | Filesystem backend, buckets, policies, persistence; upload/download/authorization + backup/restore tested. |
| 6 | Optional capabilities | Realtime / Edge Functions / GraphQL enabled *only* where required and only after a measured memory check; integration tests for each. |
| 7 | SDK compatibility | Real `supabase-js` suite passes; `docs/COMPATIBILITY.md` updated with evidence; unsupported behaviour documented. |
| 8 | Backup & production hardening | External encrypted backups; **restore drill passed**; monitoring/alerting; patching, rollback, key rotation and disk-full procedures; RPO/RTO verified. |
| 9 | Internal application staging | First internal app connected; functional, security, load and recovery tests; agreed observation period before production cutover. |
| **10** | Later-phase design (out of scope) | **Deferred.** A separate proposal is required. No commercial control plane, no multi-project provisioning, no billing. |

## What every phase report must contain

1. What changed and why.
2. Exact component versions and configuration changes.
3. Commands executed and sanitized outputs.
4. Automated tests and results.
5. Security and operational checks.
6. Known limitations and unresolved risks.
7. Rollback procedure.
8. Cost/resource impact.
9. A clear pass/fail decision against the gate.

## Minimum production-readiness checklist

- [ ] TLS works; HSTS confirmed
- [ ] Only intended ports public (443; 80 for ACME)
- [ ] Secrets not exposed; `scripts/check-secrets.sh` passes
- [ ] RLS + GRANTs tested, including cross-user and cross-tenant denial
- [ ] Studio and admin services protected
- [ ] Backups run externally and are encrypted
- [ ] **Restore drill passed** with records and objects verified
- [ ] Logs rotate; disk alerts work
- [ ] Container health checks work (gaps documented)
- [ ] Upgrades and rollback documented
- [ ] SDK compatibility claims match test results
- [ ] `deploy/versions.lock.json` has immutable image digests recorded

## Explicitly excluded from Stage A

Kubernetes, multiple VPS, MinIO on the VPS, multi-node Postgres/HA, Prometheus/Grafana/Loki, Logflare, paid monitoring, and any commercial SaaS control plane. See `docs/DEFERRED.md`.
