#!/usr/bin/env bash
# Verify every pinned image tag in deploy/versions.lock.json matches the
# vendored upstream compose. No floating `latest` allowed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/deploy/versions.lock.json"
COMPOSE="$ROOT/deploy/compose/upstream.docker-compose.yml"
FAILED=0

echo "== JSON validity =="
python3 -c 'import json,sys; json.load(open(sys.argv[1],encoding="utf-8")); print("OK  deploy/versions.lock.json")' "$LOCK"

echo "== image tag parity =="
python3 - "$LOCK" "$COMPOSE" <<'PY' || FAILED=1
import json, re, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
compose = open(sys.argv[2], encoding="utf-8").read()
found = dict(re.findall(r'^\s*image:\s*([^\s:]+):([^\s]+)\s*$', compose, flags=re.M))
ok = True
for entry in lock["images"]:
    image, tag = entry["image"], entry["tag"]
    actual = found.get(image)
    state = "OK " if actual == tag else "FAIL"
    print(f"{state} {image}:{tag} (vendored: {actual})")
    if actual != tag: ok = False
    if not entry.get("digest"):
        print(f"NOTE {image}: digest not recorded yet (run --record-digests after docker compose pull)")
for image, tag in found.items():
    if image not in {e["image"] for e in lock["images"]}:
        print(f"FAIL untracked image in vendored compose: {image}:{tag}"); ok = False
if not ok:
    sys.exit(1)
PY

echo "== floating tags =="
if grep -nE '^\s*image:.*:latest\s*$' "$COMPOSE"; then
  echo "FAIL floating latest tag found"; FAILED=1
else
  echo "OK  no :latest tags"
fi

echo "== SDK version =="
python3 - "$ROOT" <<'PY' || FAILED=1
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
lock = json.load(open(root / "deploy/versions.lock.json", encoding="utf-8"))
pkg = json.load(open(root / "tests/integration/package.json", encoding="utf-8"))
want = lock["client_sdk"]["version"]
got = pkg["dependencies"]["@supabase/supabase-js"]
print(("OK  " if got == want else "FAIL ") + f"supabase-js lock={want} package={got}")
if got != want: sys.exit(1)
PY

if [ "${1:-}" = "--record-digests" ]; then
  echo "== recording digests =="
  python3 - "$LOCK" "$COMPOSE" <<'PY'
import json, re, subprocess, sys
p = sys.argv[1]
lock = json.load(open(p, encoding="utf-8"))
compose = open(sys.argv[2], encoding="utf-8").read()
found = dict(re.findall(r'^\s*image:\s*([^\s:]+):([^\s]+)\s*$', compose, flags=re.M))
for e in lock["images"]:
    ref = f"{e['image']}:{e['tag']}"
    try:
        out = subprocess.check_output(["docker", "image", "inspect", "--format", "{{index .RepoDigests 0}}", ref], text=True).strip()
        e["digest"] = out or None
        print(f"{'OK ' if out else 'MISS'} {ref} -> {out or 'pull the image first'}")
    except Exception as ex:
        print(f"MISS {ref}: {ex}")
        e["digest"] = None
json.dump(lock, open(p, "w", encoding="utf-8"), indent=2)
open(p, "a", encoding="utf-8").write("\n")
PY
fi

[ "$FAILED" -eq 0 ] && echo "== PASS: version manifest consistent ==" || { echo "== FAIL ==" >&2; exit 1; }
