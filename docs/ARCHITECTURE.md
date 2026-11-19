# Phase 0 — Architecture audit and proposal

**Status:** discovery only. No code deployed, no packages installed, no cloud resources created, no DNS changed, no money spent. **Stopping at the Phase 0 gate for approval.**

## 1. Current-state findings

- No VPS has been provisioned. No Docker Compose stack is running. No domain or TLS certificate exists yet.
- The repository contains configuration, SQL, tests, scripts, docs and the offline console. It contains **no running services** and no real secrets.
- Upstream source of truth is the official Supabase `docker/` directory at tag `self-hosted/v0.8.4`. One compose file and the env reference are vendored; the rest is fetched by `scripts/sync-upstream.sh` into a gitignored `vendor/`.
- Client SDK verified against the npm registry: `@supabase/supabase-js` `2.119.1`.

## 2. Recommended architecture and request path

```
Client (supabase-js)
   │  HTTPS :443
   ▼
Caddy (TLS termination, security headers, log rotation)
   │  127.0.0.1:8000
   ▼
Envoy api-gw (official upstream config; publishable/secret API keys)
   ├── /auth/v1/*        → GoTrue auth          :9999  (internal)
   ├── /rest/v1/*        → PostgREST rest       :3000  (internal)
   ├── /storage/v1/*     → Storage API          :5000  (internal)
   └── /                 → Studio               :3000  (basic auth, private admin)
                                  │
                    postgres-meta :8080 (internal)
                                  ▼
                    PostgreSQL db :5432 (loopback only)
                    Supavisor     :5432 / :6543 (loopback only)
                    Storage objects → local filesystem volume → external backup
```

**Public endpoints:** `https://<PROXY_DOMAIN>/` only. Studio is reached through the same gateway and protected by `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`; it is **not** a separate public host.

**Internal services:** all ports listed in `docs/VERSIONS.md` stay on the private Docker network or on `127.0.0.1`. The upstream compose binds 8000/5432/6543 on all interfaces; `docker-compose.lumo.yml` replaces those with loopback bindings using `!override`.

## 3. Service inventory

| Service | Image | v1 | Why |
| --- | --- | --- | --- |
| `db` | `supabase/postgres:17.6.1.136` | ON | Authoritative data + authorization |
| `api-gw` | `envoyproxy/envoy:v1.39.6` | ON | Official gateway, supported key handling |
| `auth` | `supabase/gotrue:v2.197.0` | ON | Sessions, JWTs |
| `rest` | `postgrest/postgrest:v14.18` | ON | REST over roles/grants/RLS |
| `storage` | `supabase/storage-api:v1.89.12` | ON | Filesystem backend |
| `studio` | `supabase/studio:2026.11.02-sha-a05e7ec` | ON | Private admin only |
| `meta` | `supabase/postgres-meta:v0.100.0` | ON | Required by this Studio release |
| `supavisor` | `supabase/supavisor:2.9.13` | ON | Default upstream pooler |
| `realtime` | `supabase/realtime:v2.148.3` | **OFF** | Optional; no app requires it yet |
| `functions` | `supabase/edge-runtime:v1.77.9` | **OFF** | Optional |
| `imgproxy` | `darthsim/imgproxy:v4.0.21` | **OFF** | Image transforms not required |
| Analytics / Vector / Logflare | — | **OFF** | Increases resource needs materially |
| `pg_graphql` | — | **OFF** | No workflow requires GraphQL |

Dependency map verified from the pinned compose: no enabled service depends on a deferred one, so gating them behind the `optional` compose profile is safe.

## 4. VPS sizing and per-service memory estimate

Target: **2 vCPU / 4 GB RAM / 40 GB SSD** (constrained). Upstream documents 4 GB / 2 CPU / 40 GB as the minimum for *all* components and recommends 8 GB / 4 CPU / 80 GB. Our minimal set fits only because optional services are off.

| Container | Ceiling |
| --- | --- |
| db | 1024 MiB |
| studio | 384 MiB |
| supavisor / storage | 256 MiB each |
| auth / rest / api-gw | 192 MiB each |
| meta | 128 MiB |
| db-config | 64 MiB |
| **Enabled total** | **~2688 MiB** |
| OS + Caddy + backup jobs | ~800 MiB |
| **Headroom** | **~500 MiB** |

This is a **ceiling, not a forecast**. Measure with `docker stats` and `free -m` under real load. If sustained usage exceeds ~3.2 GB, disable more services or move to **8 GB / 4 CPU / 80 GB**. Do not hide the constraint by removing the limits. Disk needs monitoring (40 GB fills quickly with Postgres WAL + Storage objects + logs); `ops/monitoring/disk-alert.sh` alerts at 80%.

## 5. Security and RLS strategy

RLS enabled on every user-exposed table at creation time; explicit `GRANT`s alongside it; trusted `auth.uid()` claims only; `SECURITY DEFINER` membership helper with `search_path = ''`; `anon` has zero grants and zero policies; `service_role` is server-side only. See `docs/SECURITY.md` and `database/policies/`.

## 6. Authentication and signing-key strategy

GoTrue at the pinned release. One controlled signing-key lifecycle with key IDs, rotation and revocation. **API keys (`SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SECRET_KEY`, legacy `ANON_KEY` / `SERVICE_ROLE_KEY`) are distinct from JWT signing keys (`JWT_SECRET`, `JWT_KEYS`, `JWT_JWKS`).** Configure each service using its documented mechanism for this release — do not assume one shared JWKS endpoint. See `docs/SECURITY.md`.

## 7. Storage and backup strategy

Local filesystem backend initially; **no MinIO** on the VPS. Two independent encrypted backups (Postgres logical dump + Storage objects) to an external destination. Acceptance = a verified restore drill, not a job log. See `docs/RECOVERY.md`.

## 8. SDK compatibility test scope

Real `supabase-js@2.119.1`: auth (sign in / refresh / expiry / invalid signature / logout), REST (select / filters / insert / update / delete), RPC, Storage (upload / download / signed URL), error formats, and cross-user/cross-tenant denial. See `docs/COMPATIBILITY.md`.

## 9. Risks, unknowns and decisions needed from the owner

| # | Item | Decision needed |
| --- | --- | --- |
| 1 | RPO / RTO targets | Must be agreed **before** backup frequency is finalized |
| 2 | Domain + DNS | `PROXY_DOMAIN`; DNS change needs explicit approval |
| 3 | External backup destination + credentials | Provider and retention |
| 4 | SMTP / email delivery | GoTrue mailer settings, or disable signup |
| 5 | First internal application | Determines whether Realtime / Edge Functions are ever needed |
| 6 | 4 GB vs 8 GB VPS | Measured load will decide; start small, upgrade on evidence |
| 7 | Signing-key rotation window | Agree rotation/revocation procedure before go-live |
| 8 | Studio exposure | Confirm basic-auth-only access is acceptable |

**Known gaps:** `meta` and `db-config` have no upstream healthcheck in this release (reported honestly, not invented). Image digests are not yet recorded — they are filled after `docker compose pull`. Realtime / Edge Functions / GraphQL are untested and claimed as *Not implemented*.

## 10. Estimated monthly recurring cost (operator, informational)

> Lumo Base itself is **free** — there is no user billing, pricing or plans. The figures below are what the **operator** pays providers. These are planning estimates with explicit assumptions, not quotes; verify against the chosen provider before spending anything.

| Item | Assumption | Estimated / month |
| --- | --- | --- |
| VPS 2 vCPU / 4 GB / 40 GB SSD | single provider, annual billing, unmanaged | ~$5–12 |
| VPS 8 GB / 4 CPU / 80 GB (upgrade path) | only if measured demand requires | ~$20–40 |
| External backup storage | ~20–50 GB encrypted, object storage + egress | ~$1–5 |
| Domain name | one `.com`-class domain / 12 months | ~$1–2 |
| TLS certificates | Caddy + Let's Encrypt | $0 |
| SMTP / transactional email | low-volume internal use; may be $0 on a free tier | ~$0–10 |
| **Total (Stage A)** | **one VPS, minimal services** | **~$7–29 / month** |

Excluded and deliberately not budgeted: Kubernetes, multiple VPS, HA Postgres, dedicated object storage cluster, Prometheus/Grafana/Loki, Logflare, paid monitoring, commercial control plane. **No commercial billing system is being built.**

## 11. Phased plan with acceptance gates

See `docs/ROADMAP.md`. Phase 0 ends here. **No further phase starts without explicit approval.**

## 12. Files expected in later phases

`deploy/env/.env` (untracked, operator-only) · `vendor/supabase-docker/` (fetched) · TLS certificates managed by Caddy · backup artifacts off-VPS · restore-drill logs · recorded image digests in `deploy/versions.lock.json` · conformance test output · phase gate reports in `docs/`.
