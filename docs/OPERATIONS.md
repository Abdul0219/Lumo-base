# Operations runbook

## Start / stop (phase-gated)

```bash
sh scripts/sync-upstream.sh                 # fetch pinned upstream docker/ config
sh scripts/lumo.sh plan                    # NO changes; prints resolved services
LUMO_PHASE_APPROVED=phase2 sh scripts/lumo.sh start
sh scripts/lumo.sh status
LUMO_PHASE_APPROVED=phase2 sh scripts/lumo.sh stop
```

`scripts/lumo.sh` refuses mutating commands unless `LUMO_PHASE_APPROVED` matches the phase. Optional services need `LUMO_PHASE_APPROVED=phase6`. DNS changes, migrations that may lose data, production changes and spending money always require explicit approval from the owner.

## Everyday checks

```bash
sh scripts/verify-manifest.sh              # pinned versions consistent
sh scripts/check-secrets.sh                # no secrets tracked
sh ops/monitoring/healthcheck.sh           # health, exposure, disk, backup freshness
docker compose --env-file deploy/env/.env ps
docker stats --no-stream                  # measured memory/CPU, not ceilings
```

## Patch and upgrade

1. Read the upstream release notes for the target `self-hosted/*` tag.
2. `sh scripts/sync-upstream.sh <tag>` → review the diff against `deploy/compose/upstream.docker-compose.yml`.
3. If accepted: `sh scripts/sync-upstream.sh <tag> --accept-upstream`, then update `deploy/versions.lock.json`, `docs/VERSIONS.md`, `docs/COMPATIBILITY.md` and `web/index.html` **together**.
4. `docker compose pull`, then `sh scripts/verify-manifest.sh --record-digests` to pin immutable `sha256:` digests.
5. Take a verified restore point; record the previous tag as the rollback target.
6. Apply in staging; re-run `tests/integration` and `tests/security`.
7. Only then roll into production, with the phase gate signed off.

## Rollback

- **Config rollback:** restore the previous `deploy/versions.lock.json` + vendored compose, `docker compose up -d` with the previous pinned tags.
- **Data rollback:** restore the verified logical backup into an isolated environment, verify records and objects, then switch. Never `DROP` live objects in place.
- **TLS rollback:** keep the previous Caddyfile; revert `PROXY_DOMAIN` configuration only after the DNS change is approved.

## Key rotation

See `docs/SECURITY.md` §4. Generate with upstream helpers, add new key, verify all services accept it, then revoke the old one. Record key IDs and dates. Rotation/revocation are production changes requiring approval.

## Secret rotation and revocation

Rotate `POSTGRES_PASSWORD`, `JWT_SECRET`, `SUPABASE_SECRET_KEY`, `DASHBOARD_PASSWORD`, `VAULT_ENC_KEY`, `PG_META_CRYPTO_KEY` and the backup encryption key on a schedule or after exposure. Invalidate old credentials, check logs for use of revoked credentials, and document the incident. Never paste secrets into logs, issues or chat.

## Certificate renewal

Caddy manages Let's Encrypt certificates automatically. `ops/monitoring/healthcheck.sh` checks the HTTPS endpoint. If ACME fails, check port 80, DNS for `PROXY_DOMAIN`, and Caddy logs. DNS changes need approval.

## Disk-full recovery

Alert at 80% (`LUMO_DISK_ALERT_PCT`). Prune rotated logs, check Postgres WAL growth and Storage object growth, archive old backups off-VPS, then consider the 8 GB / 80 GB upgrade path. Do not delete database files to free space.

## Incident response

1. Contain (stop affected service, revoke credentials, block port).
2. Preserve logs and the last known-good restore point.
3. Diagnose with `docker compose logs` and health checks.
4. Restore from a verified backup into an isolated environment.
5. Post-mortem: root cause, timeline, rotation performed, gate that should have caught it.

## Known operational gaps (documented, not hidden)

`meta` and `db-config` have no upstream healthcheck in `self-hosted/v0.8.4`. No log aggregation, no paging, no query-latency monitoring yet. All are deferred until VPS capacity and operational need justify them.
