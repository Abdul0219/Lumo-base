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
