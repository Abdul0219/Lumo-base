#!/usr/bin/env bash
# Disk-capacity guard. Disk-full is the most likely failure on a 40 GB VPS.
set -uo pipefail
THRESHOLD="${LUMO_DISK_ALERT_PCT:-80}"
ROOT_FS="${LUMO_DISK_PATH:-/}"

PCT="$(df -P "$ROOT_FS" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
FREE="$(df -Ph "$ROOT_FS" | awk 'NR==2 {print $4}')"

echo "disk: $ROOT_FS used=${PCT}% free=${FREE} threshold=${THRESHOLD}%"
if [ "${PCT:-0}" -ge "$THRESHOLD" ]; then
  echo "ALERT disk usage ${PCT}% >= ${THRESHOLD}%"
  echo "      prune old logs/backups, check database growth, then consider the 80 GB upgrade path."
  exit 1
fi
echo "OK    disk headroom sufficient"
exit 0
