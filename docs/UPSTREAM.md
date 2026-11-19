# Upstream provenance and sync policy

**Rule:** prefer official upstream Supabase components and documented configuration. Do not rewrite GoTrue, PostgREST, Storage, Envoy, Studio or postgres-meta. Custom code is isolated, documented and tested.

## Pinned release

| Field | Value |
| --- | --- |
| Repository | `https://github.com/supabase/supabase` |
| Tag | `self-hosted/v0.8.4` |
| Config directory | `docker/` |
| Fetched | 2026-11-18 |
| License | Apache-2.0 (c) Supabase |

## What lives in this repo

| File | Origin |
| --- | --- |
| `deploy/compose/upstream.docker-compose.yml` | Verbatim `docker/docker-compose.yml` at the pinned tag + a 7-line provenance header |
| `deploy/upstream/env.example.reference` | Verbatim `docker/.env.example` at the pinned tag (read-only reference) |
| `deploy/compose/docker-compose.lumo.yml` | **Our** override |
| `deploy/env/.env.example` | **Our** sanitized example, using only verified variable names |
| `vendor/supabase-docker/` | Full upstream `docker/` tree fetched by `scripts/sync-upstream.sh`; **gitignored** |

Everything else (SQL, tests, scripts, docs, web console, skills, agents) is original Lumo Base work.

## Sync procedure

```bash
sh scripts/sync-upstream.sh                       # fetch + verify parity (no overwrite)
sh scripts/sync-upstream.sh self-hosted/v0.8.5 --accept-upstream   # after reviewing the diff
```

The script sparse-clones only the `docker/` directory, detects any divergence from the vendored compose, and stages our override next to the upstream compose so `./volumes/...` paths resolve. It never starts containers.

After `--accept-upstream`, update together: `deploy/versions.lock.json`, `docs/VERSIONS.md`, `docs/COMPATIBILITY.md`, `docs/ARCHITECTURE.md` and `web/index.html`. A version change that leaves documentation stale is a failed change.

## Verification against upstream

Never invent environment variables, API endpoints, database schemas, JWT claims or gateway behavior. Check:

1. `deploy/upstream/env.example.reference` — authoritative variable names.
2. `deploy/compose/upstream.docker-compose.yml` — service names, image tags, ports, healthchecks.
3. Official docs for the pinned tag:
   - https://supabase.com/docs/guides/self-hosting/docker
   - https://supabase.com/docs/guides/self-hosting/self-hosted-envoy
   - https://supabase.com/docs/guides/self-hosting/self-hosted-auth-keys
   - https://supabase.com/docs/guides/self-hosting/self-hosted-s3
   - https://supabase.com/docs/guides/self-hosting

## Trademark

"Supabase" is a trademark of Supabase Inc. Lumo Base is an independent, unofficial self-hosted configuration. It claims compatibility only where conformance tests provide evidence.
