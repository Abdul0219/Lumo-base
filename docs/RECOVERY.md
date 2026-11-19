# Backup and disaster recovery

## RPO / RTO — must be agreed before finalizing the backup plan

| Target | Owner decision | Current assumption |
| --- | --- | --- |
| Recovery Point Objective (max data loss) | **TO BE AGREED** | daily logical backup ⇒ up to ~24 h loss |
| Recovery Time Objective (max downtime) | **TO BE AGREED** | measured by `ops/backup/restore-drill.sh` |

These are deliberately left open. Choosing backup frequency before agreeing RPO/RTO would be pretending to have a requirement. Add physical backups / WAL archiving / PITR (WAL-G or pgBackRest) **only** when the agreed targets justify the added complexity.

## Backup design

| Half | Script | Format | Destination |
| --- | --- | --- | --- |
| PostgreSQL | `ops/backup/backup-db.sh` | `pg_dump -Fc`, logical, portable, encrypted | external |
| Storage objects | `ops/backup/backup-storage.sh` | `tar` + `zstd`, encrypted | external |

Both halves are independent. Postgres metadata cannot reconstruct object files; object files cannot reconstruct bucket metadata and ACLs. **Encrypt** (`age` preferred, GPG fallback), restrict backup credentials, keep backups **off the VPS**, and never keep the only copy on the same host as the live database.

## Acceptance: restore, not a job log

A successful backup job log is **not** acceptance. `ops/backup/restore-drill.sh`:

1. Fetches and decrypts the latest DB artifact.
2. Creates an isolated drill database (never the live one).
3. `pg_restore --exit-on-error` into it.
4. Verifies `app` tables exist and reports record counts.
5. Verifies the Storage archive (`zstd -t`, lists objects).
6. Records restore duration for RTO tracking and drops the drill database.

Scheduled weekly. **Production acceptance requires repeating the drill on a separate host/VPS** — the in-repo script is a same-host smoke drill and is explicitly labelled as such.

## Retention and credential handling

- Retention policy: **to be agreed with the owner**; record it here once decided.
- Backup encryption keys and destination credentials are injected at runtime from a protected secret store. They are never committed.
- On credential compromise: rotate, revoke old credentials, re-encrypt retained artifacts if feasible, and document the incident.

## Failure modes and responses

| Failure | Response |
| --- | --- |
| Backup job fails | Keep previous artifact, alert, fail the Phase 8 gate. Never overwrite the last good backup. |
| Empty/truncated artifact | Scripts check `-s` and exit non-zero. |
| Restore fails | Do **not** proceed to production cutover. Preserve logs, diagnose, re-run. |
| Disk full on VPS | `ops/monitoring/disk-alert.sh` alerts at 80%; prune logs, check WAL/object growth, then consider the 80 GB upgrade path. |
| Lost VPS | Provision a new host, restore both halves, verify, then re-point DNS (DNS change requires explicit approval). |

## Rollback

Every phase that touches data records a verified restore point before starting. Rollback means restoring that point into an isolated environment, verifying it, then switching — never dropping live objects in place. See `docs/OPERATIONS.md`.
