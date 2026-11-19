#!/usr/bin/env bash
# Fail if secret-shaped material or a real .env is tracked in git.
# CHANGE_ME placeholders are intentional and explicitly allowed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
FAILED=0

echo "== tracked env files =="
TRACKED_ENV="$(git ls-files | grep -E '(^|/)\.env(\..*)?$' | grep -v '\.env\.example$' || true)"
if [ -n "$TRACKED_ENV" ]; then
  echo "FAIL real env file tracked:"; echo "$TRACKED_ENV"; FAILED=1
else
  echo "OK  only .env.example is tracked"
fi

echo "== private keys / tokens =="
BAD="$(git grep -nIE '(BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY|sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})' -- . ':!*.md' 2>/dev/null || true)"
if [ -n "$BAD" ]; then echo "FAIL secret-shaped content:"; echo "$BAD"; FAILED=1; else echo "OK  no private keys or API tokens"; fi

echo "== hardcoded legacy demo JWTs =="
# deploy/upstream/env.example.reference is a VERBATIM upstream artifact kept only
# for verifying env var names (see NOTICE.md). It legitimately contains the
# well-known upstream DEMO keys. It is never used at runtime. Our own example
# (deploy/env/.env.example) must never contain them.
DEMO="$(git grep -nIE 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.' -- . ':(exclude)deploy/upstream/env.example.reference' 2>/dev/null || true)"
if [ -n "$DEMO" ]; then echo "FAIL upstream demo JWT committed:"; echo "$DEMO"; FAILED=1; else echo "OK  no demo JWTs (upstream reference excluded by provenance)"; fi

echo "== CHANGE_ME placeholders (expected in examples) =="
COUNT="$(git grep -ho 'CHANGE_ME' -- deploy/env/.env.example 2>/dev/null | wc -l)"
echo "OK  $COUNT placeholder values in the sanitized example"

echo "== ignored files are actually ignored =="
if git check-ignore -q deploy/env/.env 2>/dev/null; then echo "OK  deploy/env/.env is ignored";
else echo "FAIL deploy/env/.env is NOT ignored"; FAILED=1; fi

[ "$FAILED" -eq 0 ] && echo "== PASS: secret hygiene ==" || { echo "== FAIL: secret hygiene ==" >&2; exit 1; }
