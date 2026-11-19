# Explicitly deferred scope — Lumo Base

**Lumo Base is free.** There is no charge to any user for any feature. This file exists only to record what is deliberately *not* built, so that a future contributor does not accidentally add it while working on Stage A.

## Deferred (to be added in a later phase, only after a new proposal is approved)

| Item | Why it is out of scope now |
| --- | --- |
| Billing / invoicing | Not needed for internal applications; no billing section anywhere in the repo |
| Pricing, plans, tiers, free-vs-paid gating | Every capability in Stage A is available to every internal user |
| Payment providers, checkout, subscriptions | No money changes hands |
| Usage metering and quotas | No per-tenant commercial limits exist yet |
| Commercial SaaS control plane | Stage B work; a separate proposal is required before any code |
| Multi-project / multi-customer provisioning | Stage A serves one isolated environment |
| Customer accounts and support workflows | Stage B |
| Tenant isolation for paying customers | Stage A still enforces per-user and per-app data boundaries via RLS, but not commercial tenancy |
| Per-project secret management across customers | Single project in Stage A |
| Multi-node PostgreSQL, HA, orchestration | Requires measured demand and an SLA commitment |
| Kubernetes, multiple VPS instances | Explicitly forbidden at the outset |
| MinIO / local object-storage cluster | Storage filesystem backend is sufficient initially |
| Prometheus / Grafana / Loki | Lightweight health, disk and uptime checks only, until VPS capacity justifies more |

## What "free" does NOT mean

- It does not mean the VPS costs nothing. The **operator** still pays the hosting provider; see the cost note in `docs/ARCHITECTURE.md`. That is an operating expense, not user billing.
- It does not mean backups are free of operational effort. External backup storage may have its own provider cost.
- It does not mean the platform is unlicensed. See `LICENSE` and `NOTICE.md`.

## Scope guard

`AGENTS.md` maps any feature that could introduce pricing, tiers, quotas or billing to the project-local skill `lumo-free-scope`. Load it before adding any feature that gates access by payment or usage. Phase 10 of `docs/ROADMAP.md` is a *design* placeholder only and must not be started without explicit approval and a new proposal.
