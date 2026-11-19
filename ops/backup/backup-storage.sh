#!/usr/bin/env bash
# Storage-object backup, INDEPENDENT of PostgreSQL metadata.
# Both halves are required: DB rows alone cannot reconstruct uploaded objects.
set -euo pipefail

: "${LUMO_BACKUP_DESTINATION:?e.g. rclone remote:lumo-base/storage}"
: "${LUMO_BACKUP_ENCRYPTION_KEY:?age recipient or gpg key id}"
LUMO_STORAGE_PATH="${LUMO_STORAGE_PATH:-./volumes/storage}"

test -d "$LUMO_STORAGE_PATH" || { echo "storage path not found: $LUMO_STORAGE_PATH" >&2; exit 1; }
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/lumo-storage-$STAMP.tar.zst"

echo "[backup-storage] archiving $LUMO_STORAGE_PATH"
tar --create --directory "$(dirname "$LUMO_STORAGE_PATH")" "$(basename "$LUMO_STORAGE_PATH")" \
  | zstd -q -T0 -o "$OUT"
test -s "$OUT" || { echo "empty archive" >&2; exit 1; }

echo "[backup-storage] encrypting"
if command -v age >/dev/null 2>&1; then
  age -r "$LUMO_BACKUP_ENCRYPTION_KEY" -o "$OUT.age" "$OUT"; PAYLOAD="$OUT.age"
else
  gpg --batch --yes --trust-model always -e -r "$LUMO_BACKUP_ENCRYPTION_KEY" -o "$OUT.gpg" "$OUT"; PAYLOAD="$OUT.gpg"
fi

echo "[backup-storage] shipping off-VPS"
rclone copyto "$PAYLOAD" "$LUMO_BACKUP_DESTINATION/lumo-storage-$STAMP.${PAYLOAD##*.}" \
  --checksum --retries 3

echo "[backup-storage] OK $(basename "$PAYLOAD") bytes=$(wc -c < "$PAYLOAD")"
