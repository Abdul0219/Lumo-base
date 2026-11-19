#!/usr/bin/env bash
# Logical PostgreSQL backup -> encrypt -> external destination.
# A successful backup job is NOT acceptance. Run ops/backup/restore-drill.sh.
set -euo pipefail

: "${POSTGRES_PASSWORD:?inject at runtime, never store in this repo}"
: "${LUMO_BACKUP_DESTINATION:?e.g. rclone remote:lumo-base/db}"
: "${LUMO_BACKUP_ENCRYPTION_KEY:?age recipient or gpg key id}"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/lumo-db-$STAMP.dump"

echo "[backup-db] dumping"
docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" supabase-db \
  pg_dump -U postgres -d postgres -Fc --no-owner --no-privileges -f /tmp/lumo.dump
docker cp supabase-db:/tmp/lumo.dump "$OUT"
docker exec supabase-db rm -f /tmp/lumo.dump
test -s "$OUT" || { echo "empty dump" >&2; exit 1; }

echo "[backup-db] encrypting"
if command -v age >/dev/null 2>&1; then
  age -r "$LUMO_BACKUP_ENCRYPTION_KEY" -o "$OUT.age" "$OUT"
  PAYLOAD="$OUT.age"
else
  gpg --batch --yes --trust-model always -e -r "$LUMO_BACKUP_ENCRYPTION_KEY" -o "$OUT.gpg" "$OUT"
  PAYLOAD="$OUT.gpg"
fi

echo "[backup-db] shipping off-VPS"
rclone copyto "$PAYLOAD" "$LUMO_BACKUP_DESTINATION/lumo-db-$STAMP.${PAYLOAD##*.}" \
  --checksum --retries 3

echo "[backup-db] OK $(basename "$PAYLOAD") bytes=$(wc -c < "$PAYLOAD")"
echo "[backup-db] NEXT: sh ops/backup/restore-drill.sh (a backup is only proven by a restore)"
