# deploy/compose/

Two files, deliberately separated:

| File | Provenance | Edit? |
| --- | --- | --- |
| `upstream.docker-compose.yml` | Verbatim copy of `docker/docker-compose.yml` at Supabase tag `self-hosted/v0.8.4` (Apache-2.0). Provenance header prepended. | **No.** Refresh only via `scripts/sync-upstream.sh` + a reviewed diff. |
| `docker-compose.lumo.yml` | Lumo Base override (our code). | Yes. |

## Why an override, not a fork

The master engineering prompt forbids rewriting upstream core services. Keeping the official compose intact means `setup.sh`, `run.sh`, `update.sh`, the Envoy config and the database init SQL continue to work exactly as upstream intends. Every Lumo Base delta lives in one small, reviewable override file.

## Apply order

`COMPOSE_FILE=docker-compose.yml:docker-compose.lumo.yml` — base first, override second. `scripts/lumo.sh` copies the override next to the fetched upstream compose and runs with `--env-file deploy/env/.env` from that directory, so upstream's relative `./volumes/...` paths still resolve correctly.

## Deltas from upstream defaults

1. **Loopback binding.** Upstream exposes `8000`, `5432`, `6543` on all host interfaces. The override replaces those bindings with `127.0.0.1` using `!override`, so **443 (Caddy) is the only public port**.
2. **Optional services off.** `realtime`, `functions`, `imgproxy`, `deno-cache` are behind the `optional` compose profile. Verified from the upstream dependency graph: no enabled service depends on them, so gating is safe.
3. **Memory ceilings.** Per-service `mem_limit` summing to ~2.6 GB for the 2 vCPU / 4 GB VPS target.
4. **Log rotation.** `json-file` with 10 MiB × 3 files on every long-running service.
5. **Project name.** `lumo-base`.

## Known gaps (do not paper over them)

- `meta` (postgres-meta) and `db-config` have no upstream healthcheck in this release. We deliberately do **not** invent a health endpoint. `ops/monitoring/healthcheck.sh` reports them as `no-healthcheck` rather than claiming health.
- Image tags are pinned; immutable `sha256:` digests are recorded only after `docker compose pull` via `scripts/verify-manifest.sh --record-digests`. See `deploy/versions.lock.json`.
- `!override` requires Docker Compose >= 2.24.4. Pin this in the VPS preparation phase.

## Validation (no deployment required)

```bash
sh scripts/verify-manifest.sh
# after sync-upstream.sh, with a filled .env:
docker compose --env-file deploy/env/.env config --quiet
docker compose --env-file deploy/env/.env config | grep -E 'published|target'  # confirm loopback
```
