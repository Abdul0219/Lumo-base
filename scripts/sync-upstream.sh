#!/usr/bin/env bash
# Fetch the OFFICIAL upstream docker/ configuration at the pinned release tag.
# This never starts containers, changes DNS or deploys anything.
set -euo pipefail

TAG="${1:-self-hosted/v0.8.4}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/vendor/supabase-docker"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[sync] pinned tag: $TAG"
echo "[sync] sparse-cloning https://github.com/supabase/supabase"
git clone --filter=blob:none --no-checkout --depth=1 --quiet --branch "$TAG" \
  https://github.com/supabase/supabase "$TMP/upstream"
cd "$TMP/upstream"
git sparse-checkout init --cone
git sparse-checkout set docker
git checkout --quiet
cd - >/dev/null

mkdir -p "$DEST"
cp -rf "$TMP/upstream/docker/." "$DEST/"
rm -rf "$DEST/.git"
echo "[sync] fetched docker/ -> $DEST"

# Verify the vendored compose still matches upstream. Never silently diverge.
VENDORED="$ROOT/deploy/compose/upstream.docker-compose.yml"
if [ -f "$VENDORED" ]; then
  if tail -n +9 "$VENDORED" | diff -q - "$DEST/docker-compose.yml" >/dev/null 2>&1; then
    echo "[sync] OK: vendored compose matches $TAG"
  else
    echo "[sync] WARNING: upstream compose differs from the vendored copy."
    echo "[sync] Review the diff, then run: sh scripts/sync-upstream.sh $TAG --accept-upstream"
    echo "[sync] No files were overwritten in deploy/compose/."
  fi
fi

if [ "${2:-}" = "--accept-upstream" ]; then
  { printf '# VENDORED UPSTREAM FILE - DO NOT EDIT BY HAND\n# Source: https://github.com/supabase/supabase/tree/%s/docker/docker-compose.yml\n# Pinned release: %s (fetched %s)\n# License: Apache-2.0 (c) Supabase. See NOTICE.md.\n# This file is the source of truth for service definitions. Lumo Base changes\n# belong in docker-compose.lumo.yml (override) and scripts/lumo.sh.\n# To refresh: sh scripts/sync-upstream.sh\n#\n' "$TAG" "$TAG" "$(date -u +%Y-%m-%d)"; cat "$DEST/docker-compose.yml"; } > "$VENDORED"
  cp "$DEST/.env.example" "$ROOT/deploy/upstream/env.example.reference"
  echo "[sync] vendored copies updated. Now update deploy/versions.lock.json and docs/VERSIONS.md."
fi

# Place our override next to the upstream compose so upstream's relative
# ./volumes/... paths resolve correctly.
cp "$ROOT/deploy/compose/docker-compose.lumo.yml" "$DEST/docker-compose.lumo.yml"
echo "[sync] override staged at vendor/supabase-docker/docker-compose.lumo.yml"
echo "[sync] NEXT: fill deploy/env/.env, then sh scripts/verify-manifest.sh"
