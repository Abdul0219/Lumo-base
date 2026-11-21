# deploy/stack/

Phase 2 — Core backend deployment scripts. These bring the Supabase self-hosted
stack online behind Caddy TLS ingress, verify health, and provide safe teardown.

## Prerequisites

1. **Phase 1 complete** — `deploy/vps/verify-phase1.sh` passed on the target VPS.
2. **Upstream synced** — `scripts/sync-upstream.sh` run (creates `vendor/supabase-docker/`).
3. **`.env` generated** — `deploy/env/generate-env.sh <your-domain>` run and all
   `CHANGE_ME` values filled (including SMTP and backup destination).
4. **API keys generated** — upstream helpers run after sync:
   ```bash
   sh vendor/supabase-docker/utils/generate-keys.sh
   sh vendor/supabase-docker/utils/add-new-auth-keys.sh
   ```
   These produce `ANON_KEY`, `SERVICE_ROLE_KEY`, `SUPABASE_PUBLISHABLE_KEY`,
   `SUPABASE_SECRET_KEY`, `JWT_KEYS`, `JWT_JWKS`. Paste them into `deploy/env/.env`.

## Scripts

| Script | Purpose | Safe to re-run? |
| --- | --- | --- |
| `deploy/env/generate-env.sh` | Generate all secrets and write `deploy/env/.env` | Yes (overwrites previous `.env` — back up first) |
| `deploy/stack/configure-caddy.sh` | Start Caddy as TLS ingress container | Yes (stops and recreates the container) |
| `deploy/stack/bring-up.sh` | Pull images, start stack, wait for health | Yes |
| `deploy/stack/verify-phase2.sh` | Acceptance checker (20+ checks) | Yes |
| `deploy/stack/teardown.sh` | Stop stack + Caddy (keeps data) | Yes |
| `deploy/stack/teardown.sh --purge` | Stop stack + delete all volumes | **Irreversible** |

## Execution order

```bash
# 1. Generate secrets (from repo root)
sudo bash deploy/env/generate-env.sh api.your-domain.com you@example.com

# 2. Fill remaining CHANGE_ME values (SMTP, backup destination)
nano deploy/env/.env

# 3. Generate API keys using upstream helpers
sh vendor/supabase-docker/utils/generate-keys.sh
sh vendor/supabase-docker/utils/add-new-auth-keys.sh
# Paste output into deploy/env/.env

# 4. Verify secrets pass hygiene check
sh scripts/check-secrets.sh

# 5. Start Caddy TLS ingress
sudo bash deploy/stack/configure-caddy.sh

# 6. Bring up the stack
sudo bash deploy/stack/bring-up.sh

# 7. Verify Phase 2 acceptance
sudo bash deploy/stack/verify-phase2.sh
```

## Staging mode (no real domain)

For testing without a domain + DNS, set `LUMO_STAGING_TLS=1` in `.env` or
export it before running `configure-caddy.sh`:

```bash
LUMO_STAGING_TLS=1 sudo -E bash deploy/stack/configure-caddy.sh
```

Caddy will use its internal CA (self-signed). Browsers will show a certificate
warning — this is expected and safe for local testing only.

## What the stack looks like

```
                    ┌─────────┐
   Internet ──443──▶│  Caddy  │── TLS ingress, HSTS, security headers
                    └────┬────┘
                         │ 127.0.0.1:8000
                    ┌────▼────┐
                    │  Envoy  │── API gateway (api-gw)
                    └────┬────┘
              ┌──────────┼──────────┐
              │          │          │
         ┌────▼──┐  ┌───▼──┐  ┌───▼─────┐
         │ GoTrue│  │  REST│  │ Storage │
         └────┬──┘  └───┬──┘  └────┬────┘
              │          │          │
              └──────────┼──────────┘
                    ┌────▼────┐
                    │Postgres │── db (RLS enabled)
                    └─────────┘
                    ┌─────────┐
                    │Supavisor│── connection pooler (loopback only)
                    └─────────┘
                    ┌─────────┐
                    │ Studio  │── dashboard (behind gateway auth)
                    └─────────┘
                    ┌─────────┐
                    │  Meta   │── postgres-meta (no healthcheck)
                    └─────────┘
```

**Only 443 is public.** 80 is open for ACME challenges. 8000/5432/6543 are
bound to `127.0.0.1` by `deploy/compose/docker-compose.lumo.yml`.

## Memory budget

| Component | Limit |
| --- | --- |
| db (Postgres) | 1024 MB |
| studio | 384 MB |
| storage | 256 MB |
| supavisor | 256 MB |
| auth | 192 MB |
| rest | 192 MB |
| api-gw (Envoy) | 192 MB |
| meta | 128 MB |
| db-config | 64 MB |
| Caddy | 128 MB |
| **Total ceiling** | **~2816 MB** |

On a 4 GB VPS this leaves ~1.2 GB for OS + page cache + backup jobs.
If sustained usage exceeds ~3.2 GB, upgrade to 8 GB / 4 CPU.

## Rollback

```bash
# Stop everything, keep data
sudo bash deploy/stack/teardown.sh

# Or destroy everything (irreversible)
sudo bash deploy/stack/teardown.sh --purge
```

To roll back to a previous version, change `release_tag` in
`deploy/versions.lock.json`, re-sync upstream, and re-run `bring-up.sh`.

## Known gaps

- `meta` and `db-config` have no upstream healthcheck — verified as "running"
  but not "healthy". This is a Supabase limitation, not a Lumo Base gap.
- Image digests are `null` until `docker compose pull` + `verify-manifest.sh
  --record-digests` have been run. `bring-up.sh` attempts this automatically.
- The asymmetric JWT keys (`JWT_KEYS`, `JWT_JWKS`, `SUPABASE_PUBLISHABLE_KEY`,
  `SUPABASE_SECRET_KEY`) require the upstream helper scripts and cannot be
  generated by `generate-env.sh` alone.
