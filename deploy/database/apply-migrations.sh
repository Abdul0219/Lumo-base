#!/usr/bin/env bash
# apply-migrations.sh — Phase 3 database migration runner.
#
# Applies all Lumo Base SQL migrations and policies to the live Postgres
# in the correct order, with ON_ERROR_STOP so any failure halts immediately.
#
# Prerequisites:
#   - Phase 2 complete (stack running, Postgres healthy)
#   - LUMO_DB_URL set (postgres superuser connection, injected at runtime)
#
# Usage:
#   LUMO_DB_URL='postgres://postgres:...' \
#     bash deploy/database/apply-migrations.sh
#
# Order (forward-only, never re-order):
#   1. database/migrations/20261118000100_app_schema.sql   (tables + RLS enabled)
#   2. database/migrations/20261118000200_functions.sql     (SECURITY DEFINER functions)
#   3. database/policies/001_roles_grants.sql               (GRANTs)
#   4. database/policies/002_rls_policies.sql               (RLS policies)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${LUMO_DB_URL:?LUMO_DB_URL must be set (postgres superuser connection, injected at runtime)}"

# ---- files in order ---------------------------------------------------------
MIGRATIONS=(
  "$ROOT/database/migrations/20261118000100_app_schema.sql"
  "$ROOT/database/migrations/20261118000200_functions.sql"
  "$ROOT/database/policies/001_roles_grants.sql"
  "$ROOT/database/policies/002_rls_policies.sql"
)

# ---- verify all files exist -------------------------------------------------
echo "== Phase 3: Applying database migrations and policies =="
echo "  connection: LUMO_DB_URL (superuser, injected at runtime)"
echo ""

for f in "${MIGRATIONS[@]}"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: migration file not found: $f" >&2
    exit 1
  fi
done

# ---- apply each file --------------------------------------------------------
for f in "${MIGRATIONS[@]}"; do
  BASENAME="$(basename "$f")"
  echo "== applying: $BASENAME =="

  # Dry-run check: psql --dry-run is not a thing, but we can validate syntax
  # by running in a transaction that we roll back. However, the migrations
  # contain CREATE POLICY with DROP IF EXISTS which is idempotent.
  # We apply directly with ON_ERROR_STOP=1.
  psql "$LUMO_DB_URL" \
    -v ON_ERROR_STOP=1 \
    --single-transaction \
    -f "$f"

  echo "OK: $BASENAME applied"
  echo ""
done

# ---- post-apply verification ------------------------------------------------
echo "== post-apply verification =="

# Check RLS is enabled on all app tables
RLS_CHECK=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT relname, relrowsecurity
  FROM pg_class
  WHERE relnamespace = 'app'::regnamespace
    AND relkind = 'r'
  ORDER BY relname;
")

echo "  RLS status per table:"
echo "$RLS_CHECK" | while IFS='|' read -r tbl rls; do
  if [ "$rls" = "t" ]; then
    echo "    OK   $tbl: RLS enabled"
  else
    echo "    FAIL $tbl: RLS NOT enabled"
  fi
done

# Check SECURITY DEFINER functions have safe search_path
FUNC_CHECK=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT p.proname, p.prosecdef, pg_get_functiondef(p.oid) ~ 'set search_path = '''
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'app'
    AND p.prosecdef = true
  ORDER BY p.proname;
")

echo ""
echo "  SECURITY DEFINER functions:"
if [ -z "$FUNC_CHECK" ]; then
  echo "    (none found — expected at least 2)"
else
  echo "$FUNC_CHECK" | while IFS='|' read -r name definer safe_search; do
    if [ "$safe_search" = "t" ]; then
      echo "    OK   $name: SECURITY DEFINER, search_path = ''"
    else
      echo "    FAIL $name: SECURITY DEFINER but no safe search_path"
    fi
  done
fi

# Check GRANTs summary
GRANT_CHECK=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT table_name, grantee, string_agg(privilege_type, ',')
  FROM information_schema.role_table_grants
  WHERE table_schema = 'app'
  GROUP BY 1, 2
  ORDER BY 1, 2;
")

echo ""
echo "  GRANTs summary:"
echo "$GRANT_CHECK" | while IFS='|' read -r tbl grantee privs; do
  echo "    $tbl → $grantee: $privs"
done

echo ""
echo "== migrations and policies applied successfully =="
echo "Next: create test users and run tests/security/run-security-tests.sh"
