# ops/backup/ — backup, restore, acceptance

Two independent backup halves, by design:

| Artifact | Script | Contains |
| --- | --- | --- |
| `lumo-db-<ts>.dump.{age|gpg}` | `backup-db.sh` | Logical PostgreSQL backup (`pg_dump -Fc`) |
| `lumo-storage-<ts>.tar.zst.{age|gpg}` | `backup-storage.sh` | Storage objects (local filesystem backend) |

PostgreSQL metadata alone cannot reconstruct uploaded objects, and objects alone cannot reconstruct bucket/ACL metadata. **Both must succeed and both must be restorable.**

## Hard rules

1. **Off-VPS.** Encrypted backups go to an external destination (`LUMO_BACKUP_DESTINATION`). Never keep the only copy on the same VPS as the live database.
2. **Encrypted.** `age` is preferred; GPG is the fallback. Backup credentials are injected at runtime and are restricted.
3. **Restore is the acceptance test.** A successful job log proves nothing. `restore-drill.sh` decrypts, restores into an isolated database, verifies `app` tables and record counts, and verifies the object archive. Duration is recorded for RTO tracking.
4. **Separate host for production.** The drill script restores into an isolated *database* on one host (smoke drill). Production acceptance requires repeating it on a separate host/VPS.
5. **RPO/RTO first.** Agree on Recovery Point Objective and Recovery Time Objective with the owner *before* finalizing backup frequency. See `docs/RECOVERY.md`.
6. **Logical first.** Start with `pg_dump`. Add physical backups / WAL archiving / PITR (WAL-G or pgBackRest) only when the agreed RPO/RTO justifies the complexity.

## Runtime configuration (never in git)

```bash
export POSTGRES_PASSWORD=...              # from the secret store
export LUMO_BACKUP_DESTINATION='remote:lumo-base'
export LUMO_BACKUP_ENCRYPTION_KEY=...     # age recipient / gpg key id
export LUMO_STORAGE_PATH=./volumes/storage
```

## Schedule (see `ops/monitoring/crontab.example`)

```cron
15 2 * * *  sh /srv/lumo-base/ops/backup/backup-db.sh
40 2 * * *  sh /srv/lumo-base/ops/backup/backup-storage.sh
30 3 * * 1  sh /srv/lumo-base/ops/backup/restore-drill.sh
```

## Rollback / incident

On a bad backup: keep the previous artifact, do not overwrite it, and fail the Phase 8 gate. Retention and credential revocation are documented in `docs/OPERATIONS.md`.
