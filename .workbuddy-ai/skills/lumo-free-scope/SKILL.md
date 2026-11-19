---
name: lumo-free-scope
description: Scope guard for Lumo Base. Load before adding any feature that could introduce billing, pricing, plans, tiers, quotas, metering, subscriptions or a commercial control plane.
---

# Lumo Base — Free scope guard

**Purpose:** every capability in Stage A is free for every internal user. Monetization is explicitly **deferred to a later phase** and must not be scaffolded "just in case".

## Trigger
Any proposal involving: billing, invoicing, pricing, plans, tiers, payment providers, checkout, subscriptions, invoices, free-vs-paid gating, usage metering, quotas, per-customer accounts, multi-project provisioning, tenant quotas, a SaaS control plane, or gating any feature behind account state.

## Rules
1. **Do not add it.** Stage A serves the owner's internal applications on one VPS. There is no charge to any user.
2. The only permitted mentions are short *deferral notes*: "free for all internal use", "billing and monetization are deliberately deferred to a later phase", and the scope table in `docs/DEFERRED.md`. There must be **no billing/pricing section**, no pricing table, no plan comparison, no "upgrade" CTA.
3. Phase 10 of `docs/ROADMAP.md` is a design placeholder. It requires a **new proposal and explicit approval** before any work.
4. Do not introduce per-tenant quotas or metering "for later". Do not add a `plan` / `tier` / `subscription` column to any table. Do not add a commercial control plane as a dependency of ordinary database/API traffic.
5. RLS isolation between workspaces **is still required** — it is a security boundary, not commercial tenancy. Keep it.
6. CI enforces the guard: `.github/workflows/ci.yml` fails if a billing/pricing section appears in `docs/`, `web/` or `README.md`.

## Cost clarification
"Free" means no user billing. The **operator** still pays for the VPS, domain and external backup storage; that is documented as an operating expense in `docs/ARCHITECTURE.md` §10, not as product pricing.

## Done condition
The change contains zero commerce code, zero commerce UI, and CI's free-scope guard passes.

Complementary skills: `ecc-architecture-decision-records`, `ecc-cost-tracking`.
