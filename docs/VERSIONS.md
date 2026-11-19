# Version lockfile / release manifest

Single source of truth for what Lumo Base runs. Machine-readable twin: [`deploy/versions.lock.json`](../deploy/versions.lock.json).

> Non-negotiable rule: **never invent** environment variables, API endpoints, database schemas, JWT claims or gateway behavior. Everything below was read from the official Supabase repository at the pinned tag. If a value is not here, verify it upstream before using it.

## Pinned release

| Field | Value |
| --- | --- |
| Upstream repo | `https://github.com/supabase/supabase` |
| Release tag | `self-hosted/v0.8.4` |
| Config source | `docker/docker-compose.yml` |
| Env reference | `docker/.env.example` |
| Fetched | 2026-11-18 |
| Vendored copy | `deploy/compose/upstream.docker-compose.yml` (verbatim + provenance header) |
| License | Apache-2.0 (c) Supabase — see `NOTICE.md` |
| Compose requirement | >= 2.24.4 (`!override` tag used in the Lumo Base override) |

## Pinned images

| Service | Image | Tag | State | Digest |
| --- | --- | --- | --- | --- |
| `db` | `supabase/postgres` | `17.6.1.136` | enabled | pending |
| `auth` | `supabase/gotrue` | `v2.197.0` | enabled | pending |
| `rest` | `postgrest/postgrest` | `v14.18` | enabled | pending |
| `api-gw` | `envoyproxy/envoy` | `v1.39.6` | enabled | pending |
| `storage` | `supabase/storage-api` | `v1.89.12` | enabled | pending |
| `studio` | `supabase/studio` | `2026.11.02-sha-a05e7ec` | enabled | pending |
| `meta` | `supabase/postgres-meta` | `v0.100.0` | enabled | pending |
| `supavisor` | `supabase/supavisor` | `2.9.13` | enabled | pending |
| `realtime` | `supabase/realtime` | `v2.148.3` | **deferred** | pending |
| `functions` | `supabase/edge-runtime` | `v1.77.9` | **deferred** | pending |
| `imgproxy` | `darthsim/imgproxy` | `v4.0.21` | **deferred** | pending |

**Digest policy.** Tags alone are not immutable. Before production, run `docker compose pull`, then `sh scripts/verify-manifest.sh --record-digests` to write the resolved `sha256:...` digests into `deploy/versions.lock.json`. Floating `latest` tags are forbidden. Re-record digests on every upgrade.

## Client SDK

`@supabase/supabase-js` pinned at `2.119.1` in `tests/integration/package.json` (verified against the npm registry on 2026-11-18). Compatibility claims are only made for versions that pass the conformance suite in [`docs/COMPATIBILITY.md`](COMPATIBILITY.md).

## Environment variables (verified names only)

The tracked, sanitized example is [`deploy/env/.env.example`](../deploy/env/.env.example). A verbatim upstream reference is kept at `deploy/upstream/env.example.reference` so names can be checked without guessing. Verified groups:

- **Core secrets:** `POSTGRES_PASSWORD`, `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`
- **New API keys / asymmetric JWT:** `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `JWT_KEYS`, `JWT_JWKS`, `ANON_KEY_ASYMMETRIC`, `SERVICE_ROLE_KEY_ASYMMETRIC`
- **Dashboard / service secrets:** `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD`, `SECRET_KEY_BASE`, `VAULT_ENC_KEY`, `PG_META_CRYPTO_KEY`, `REALTIME_DB_ENC_KEY`
- **URLs:** `SUPABASE_PUBLIC_URL`, `API_EXTERNAL_URL`, `SITE_URL`, `ADDITIONAL_REDIRECT_URLS`
- **Database / pooler:** `POSTGRES_HOST`, `POSTGRES_DB`, `POSTGRES_PORT`, `POOLER_PROXY_PORT_TRANSACTION`, `POOLER_TENANT_ID`, `POOLER_DEFAULT_POOL_SIZE`, `POOLER_MAX_CLIENT_CONN`, `POOLER_DB_POOL_SIZE`
- **Auth:** `JWT_EXPIRY`, `DISABLE_SIGNUP`, `ENABLE_EMAIL_SIGNUP`, `ENABLE_EMAIL_AUTOCONFIRM`, `ENABLE_ANONYMOUS_USERS`, `ENABLE_PHONE_SIGNUP`, `ENABLE_PHONE_AUTOCONFIRM`, `SMTP_ADMIN_EMAIL`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_SENDER_NAME`, `MAILER_URLPATHS_*`
- **Storage:** `GLOBAL_S3_BUCKET`, `REGION`, `STORAGE_TENANT_ID`, `S3_PROTOCOL_ACCESS_KEY_ID`, `S3_PROTOCOL_ACCESS_KEY_SECRET`
- **PostgREST:** `PGRST_DB_SCHEMAS`, `PGRST_DB_MAX_ROWS`, `PGRST_DB_EXTRA_SEARCH_PATH`
- **Gateway / proxy:** `API_GW_HTTP_PORT`, `KONG_HTTP_PORT`, `KONG_HTTPS_PORT`, `PROXY_DOMAIN`, `CERTBOT_EMAIL`
- **Wiring:** `COMPOSE_FILE`, `DOCKER_SOCKET_LOCATION`, `STUDIO_DEFAULT_ORGANIZATION`, `STUDIO_DEFAULT_PROJECT`

**API keys != JWT signing keys.** `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SECRET_KEY` (and the legacy `ANON_KEY` / `SERVICE_ROLE_KEY`) are API keys. `JWT_SECRET`, `JWT_KEYS` and `JWT_JWKS` are the signing material used to validate user sessions. They have separate lifecycles. Do not assume every service dynamically fetches keys from one common JWKS endpoint; configure each service using its documented mechanism for this release.

## Ports

| Port | Owner | Exposure |
| --- | --- | --- |
| 443 | Caddy | **only public port** |
| 8000 (`API_GW_HTTP_PORT`) | `api-gw` Envoy | 127.0.0.1 only (Lumo Base override) |
| 5432 (`POSTGRES_PORT`) | `supavisor` / Postgres | 127.0.0.1 only (Lumo Base override) |
| 6543 (`POOLER_PROXY_PORT_TRANSACTION`) | `supavisor` | 127.0.0.1 only (Lumo Base override) |
| 3000 / 8080 / 9999 / 5000 / 4000 | studio / meta / auth / storage / supavisor health | internal Docker network only |

The upstream compose binds `8000`, `5432` and `6543` on all interfaces. [`docker-compose.lumo.yml`](../deploy/compose/docker-compose.lumo.yml) replaces those bindings with loopback-only ones via the `!override` tag — this is the single most important security delta from upstream defaults.

## Upgrade procedure

1. Read the upstream release notes for the target `self-hosted/*` tag.
2. Run `sh scripts/sync-upstream.sh <tag>`, then diff the new `docker/` config against the vendored copies.
3. Update `deploy/versions.lock.json`, this file, `docs/COMPATIBILITY.md` and the console in `web/index.html` together — a version change must never leave documentation stale.
4. Run `sh scripts/verify-manifest.sh`.
5. Re-run `tests/integration` and `tests/security` in staging.
6. Record the previous tag and a verified restore point as the rollback target. See `docs/OPERATIONS.md`.
