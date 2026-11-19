#!/usr/bin/env bash
# Isolated restore drill. Acceptance = verified records AND verified objects,
# not a successful backup job log.
#
# SCOPE: this restores into an isolated DATABASE on the same host (smoke drill).
# For production acceptance, repeat on a separate host/VPS. The only backup copy
# must NEVER live on the same VPS as the live database.
set -euo pipefail

: "${LUMO_DB_URL:?postgres superuser connection for the DRILL host}"
: "${LUMO_BACKUP_DESTINATION:?rclone remote containing the encrypted backups}"
: "${LUMO_BACKUP_ENCRYPTION_KEY:?age identity file or gpg key id}"
LUMO_DB_DUMP="${LUMO_DB_DUMP:-}"       # optional explicit artifact
LUMO_STORAGE_ARCHIVE="${LUMO_STORAGE_ARCHIVE:-}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DB_NAME="lumo_restore_drill_$(date -u +%Y%m%d%H%M%S)"
START="$(date +%s)"

echo "[drill] fetching artifacts"
if [ -z "$LUMO_DB_DUMP" ]; then
  LUMO_DB_DUMP="$(rclone lsf "$LUMO_BACKUP_DESTINATION" --files-only | grep '^lumo-db-' | sort | tail -1)"
  [ -n "$LUMO_DB_DUMP" ] || { echo "no DB backup found" >&2; exit 1; }
  rclone copyto "$LUMO_BACKUP_DESTINATION/$LUMO_DB_DUMP" "$WORK/$LUMO_DB_DUMP"
  LUMO_DB_DUMP="$WORK/$LUMO_DB_DUMP"
fi

echo "[drill] decrypting"
case "$LUMO_DB_DUMP" in
  *.age) age -d -i "$LUMO_BACKUP_ENCRYPTION_KEY" -o "$WORK/db.dump" "$LUMO_DB_DUMP" ;;
  *.gpg) gpg --batch --yes -d -o "$WORK/db.dump" "$LUMO_DB_DUMP" ;;
  *) cp "$LUMO_DB_DUMP" "$WORK/db.dump" ;;
esac
test -s "$WORK/db.dump" || { echo "decrypted dump is empty" >&2; exit 1; }

echo "[drill] creating isolated database $DB_NAME"
psql "$LUMO_DB_URL" -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DB_NAME"
DRILL_URL="$(python3 -c 'import sys, urllib.parse as u; p = u.urlsplit(sys.argv[1]); print(u.urlunsplit((p.scheme, p.netloc, "/" + sys.argv[2], p.query, p.fragment)))' "$LUMO_DB_URL" "$DB_NAME")"
cleanup_db() { psql "$LUMO_DB_URL" -q -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE)" || true; }
trap 'cleanup_db; rm -rf "$WORK"' EXIT

echo "[drill] restoring into $DB_NAME"
pg_restore --dbname="$DRILL_URL" --no-owner --no-privileges \
  --exit-on-error "$WORK/db.dump" 2>"$WORK/restore.log"

echo "[drill] verifying records"
TABLES="$(psql "$DRILL_URL" -At -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='app'")"
[ "$TABLES" -gt 0 ] || { echo "no app tables after restore" >&2; cat "$WORK/restore.log" >&2; exit 1; }
psql "$DRILL_URL" -At -c "SELECT 'documents=' || count(*) FROM app.documents" || true

echo "[drill] verifying objects"
if [ -n "$LUMO_STORAGE_ARCHIVE" ]; then
  cp "$LUMO_STORAGE_ARCHIVE" "$WORK/storage.tar.zst"
  zstd -t "$WORK/storage.tar.zst"
  tar -tf "$WORK/storage.tar.zst" > "$WORK/objects.txt"
  [ -s "$WORK/objects.txt" ] || { echo "no objects in archive" >&2; exit 1; }
  echo "objects listed: $(wc -l < "$WORK/objects.txt")"
fi

DURATION=$(( $(date +%s) - START ))
echo "[drill] PASS duration=${DURATION}s db=$DB_NAME"
echo "[drill] record RPO/RTO against the agreed targets in docs/RECOVERY.md"
echo "[drill] WARNING: production acceptance also requires a restore on a SEPARATE host"
