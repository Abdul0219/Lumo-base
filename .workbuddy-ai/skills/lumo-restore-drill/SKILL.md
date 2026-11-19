---
name: lumo-restore-drill
description: Use before claiming Lumo Base backups work. Enforces off-VPS encrypted backups, both backup halves, and a verified isolated restore as the only acceptance criterion.
---

# Lumo Base — Restore drill

**Purpose:** a backup is not proven by a successful job log. Acceptance is a successful, verified restore.

## Trigger
Changing `ops/backup/*`, changing RPO/RTO, or any statement that "backups are working".

## Rules
1. **Two independent halves:** logical Postgres dump (`backup-db.sh`) AND Storage objects (`backup-storage.sh`). Metadata alone cannot reconstruct objects; objects alone cannot reconstruct ACLs.
2. **Off-VPS and encrypted.** `age` preferred, GPG fallback. Backup credentials restricted and injected at runtime. Never keep the only copy on the same VPS as the live DB.
3. **RPO/RTO first.** Agree the targets with the owner *before* setting backup frequency. Add physical backups / WAL archiving / PITR only when the targets justify the complexity.
4. **Restore into isolation.** `ops/backup/restore-drill.sh` creates a separate drill database, restores with `--exit-on-error`, verifies `app` tables exist and reports record counts, verifies the object archive (`zstd -t` + listing), records duration and drops the drill DB.
5. **Production acceptance needs a separate host.** The in-repo script is a same-host smoke drill and says so explicitly. Do not claim production readiness from it alone.
6. Log the restore duration and validation results against the agreed RTO. A failed drill fails the Phase 8 gate; keep the previous good artifact, never overwrite it.

## Done condition
A recorded drill with: artifact name, decryption success, verified record count, verified object listing, duration, RPO/RTO comparison, and an explicit pass/fail.

Complementary skills: `ecc-deployment-patterns`, `ecc-delivery-gate`.
