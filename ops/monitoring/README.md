# ops/monitoring/ — lightweight observability

Stage A deliberately uses **no** Prometheus / Grafana / Loki / Vector / Logflare. Those are deferred until measured operational need and VPS capacity justify them (see `docs/DEFERRED.md`).

| Check | Script | Cadence |
| --- | --- | --- |
| Container health + exposure audit | `healthcheck.sh` | every 5 min |
| Disk capacity | `disk-alert.sh` | hourly |
| Backup freshness | `healthcheck.sh` | every 5 min |
| Uptime / HTTPS | `healthcheck.sh` | every 5 min |

Install the schedule from `crontab.example`. Logs are written to `/var/log/lumo-*.log`; rotate them with the host's logrotate (10 MiB × 3), matching the container `json-file` policy.

## What is monitored

- `docker compose ps` status and health for every service.
- **Known gap:** `meta` (postgres-meta) and `db-config` have no upstream healthcheck in `self-hosted/v0.8.4`. The script reports them as `no-healthcheck` rather than inventing a health endpoint or claiming they are healthy.
- HTTPS ingress responds (with a note to verify the exact health path for the pinned GoTrue release — do not assume one).
- `8000`, `5432`, `6543` are bound to `127.0.0.1` only. Any non-loopback listener fails the check.
- Disk headroom (default alert at 80%).
- Latest encrypted backup artifact exists at the external destination.
- Container log rotation is active.

## What is NOT monitored yet (documented, not hidden)

PostgreSQL replication lag, query latency histograms, per-tenant metrics, log aggregation, on-call paging. Add only after the 4 GB VPS has been measured and the upgrade path exercised.
