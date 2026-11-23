#!/usr/bin/env bash
# verify-phase3.sh — Phase 3 acceptance checker.
#
# Verifies the database and authorization layer meets all Phase 3 acceptance
# criteria:
#   - Migrations applied (app schema, tables, indexes exist)
#   - RLS enabled on every app table
#   - GRANTs correct (anon has nothing, authenticated has limited, service_role has all)
#   - SECURITY DEFINER functions have search_path = '' and are revoked from PUBLIC
#   - RLS policies exist for all required commands
#   - Positive + negative isolation tests pass
#
# Produces PASS/WARN/FAIL summary with exit code.
# Exit 0 = all PASS, exit 1 = any FAIL, exit 2 = cannot evaluate.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/deploy/env/.env"

PASS=0
WARN=0
FAIL=0
SKIP=0

p()  { echo "PASS  $1"; PASS=$((PASS+1)); }
w()  { echo "WARN  $1"; WARN=$((WARN+1)); }
f()  { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
s()  { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

# ---- load env ---------------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

: "${LUMO_DB_URL:?LUMO_DB_URL must be set (postgres superuser connection)}"

echo "============================================"
echo "  Phase 3: Database & Authorization"
echo "  Acceptance Verification"
echo "============================================"
echo ""

# ---- 1. Schema exists -------------------------------------------------------
echo "== 1. Application schema =="

SCHEMA_EXISTS=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM pg_namespace WHERE nspname = 'app';
" 2>/dev/null || echo "error")

if [ "$SCHEMA_EXISTS" = "1" ]; then
  p "app schema exists"
else
  f "app schema not found — migrations not applied"
  echo "  Run: bash deploy/database/apply-migrations.sh" >&2
  exit 2
fi

# ---- 2. Tables exist with RLS enabled --------------------------------------
echo ""
echo "== 2. Tables and RLS =="

RLS_RESULTS=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT relname, relrowsecurity, relforcerowsecurity
  FROM pg_class
  WHERE relnamespace = 'app'::regnamespace AND relkind = 'r'
  ORDER BY relname;
" 2>/dev/null || echo "error")

EXPECTED_TABLES="workspaces memberships documents"

for tbl in $EXPECTED_TABLES; do
  ROW=$(echo "$RLS_RESULTS" | grep "^${tbl}|" || true)
  if [ -z "$ROW" ]; then
    f "table app.$tbl not found"
  else
    RLS_ENABLED=$(echo "$ROW" | cut -d'|' -f2)
    FORCE_RLS=$(echo "$ROW" | cut -d'|' -f3)
    if [ "$RLS_ENABLED" = "t" ]; then
      p "app.$tbl: RLS enabled"
    else
      f "app.$tbl: RLS NOT enabled"
    fi
    # FORCE RLS should be false — service_role must bypass RLS
    if [ "$FORCE_RLS" = "f" ]; then
      p "app.$tbl: FORCE RLS is off (service_role can bypass — correct)"
    else
      w "app.$tbl: FORCE RLS is on — service_role cannot bypass (may break migrations)"
    fi
  fi
done

# ---- 3. Indexes -------------------------------------------------------------
echo ""
echo "== 3. Indexes =="

INDEX_COUNT=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM pg_indexes WHERE schemaname = 'app';
" 2>/dev/null || echo "0")

if [ "$INDEX_COUNT" -ge 3 ]; then
  p "$INDEX_COUNT indexes exist on app tables (expected ≥ 3)"
else
  f "only $INDEX_COUNT indexes found (expected ≥ 3)"
fi

# ---- 4. SECURITY DEFINER functions ------------------------------------------
echo ""
echo "== 4. SECURITY DEFINER functions =="

FUNC_RESULTS=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT p.proname,
         p.prosecdef,
         pg_get_functiondef(p.oid) ~ 'set search_path = ''''' as has_safe_search,
         (SELECT count(*) FROM pg_proc p2
          JOIN pg_namespace n2 ON p2.pronamespace = n2.oid
          WHERE n2.nspname = 'app' AND p2.proname = p.proname
          AND has_function_privilege('public', p2.oid, 'EXECUTE')) as public_can_exec
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'app' AND p.prosecdef = true
  ORDER BY p.proname;
" 2>/dev/null || echo "error")

if [ -z "$FUNC_RESULTS" ] || [ "$FUNC_RESULTS" = "error" ]; then
  f "cannot query SECURITY DEFINER functions"
else
  echo "$FUNC_RESULTS" | while IFS='|' read -r name definer safe_search public_exec; do
    if [ "$safe_search" = "t" ]; then
      p "$name: search_path = '' (safe)"
    else
      f "$name: no safe search_path — SQL injection risk"
    fi

    if [ "$public_exec" = "0" ]; then
      p "$name: not executable by PUBLIC (revoked)"
    else
      f "$name: still executable by PUBLIC — should be revoked"
    fi
  done
fi

# ---- 5. GRANTs verification -------------------------------------------------
echo ""
echo "== 5. GRANTs =="

# anon should have ZERO privileges on app tables
ANON_GRANTS=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM information_schema.role_table_grants
  WHERE table_schema = 'app' AND grantee = 'anon';
" 2>/dev/null || echo "error")

if [ "$ANON_GRANTS" = "0" ]; then
  p "anon has ZERO table privileges on app (correct)"
else
  f "anon has $ANON_GRANTS table grants on app — should be zero"
fi

# authenticated should have limited privileges
AUTH_GRANTS=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT table_name, privilege_type
  FROM information_schema.role_table_grants
  WHERE table_schema = 'app' AND grantee = 'authenticated'
  ORDER BY table_name, privilege_type;
" 2>/dev/null || echo "error")

echo "  Authenticated user grants:"
echo "$AUTH_GRANTS" | while IFS='|' read -r tbl priv; do
  echo "    $tbl: $priv"
done

# Check no direct write access to workspaces/memberships
WS_WRITE=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM information_schema.role_table_grants
  WHERE table_schema = 'app'
    AND grantee = 'authenticated'
    AND table_name IN ('workspaces', 'memberships')
    AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE');
" 2>/dev/null || echo "error")

if [ "$WS_WRITE" = "0" ]; then
  p "authenticated has NO direct write to workspaces/memberships (RPC-only — correct)"
else
  f "authenticated has direct write to workspaces/memberships — should be RPC-only"
fi

# service_role should have all privileges
SR_GRANTS=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(DISTINCT privilege_type)
  FROM information_schema.role_table_grants
  WHERE table_schema = 'app' AND grantee = 'service_role';
" 2>/dev/null || echo "0")

if [ "$SR_GRANTS" -ge 4 ]; then
  p "service_role has all CRUD privileges on app (server-side bypass — correct)"
else
  f "service_role has only $SR_GRANTS privilege types — expected ≥ 4"
fi

# ---- 6. RLS policies --------------------------------------------------------
echo ""
echo "== 6. RLS policies =="

POLICY_COUNT=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM pg_policies WHERE schemaname = 'app';
" 2>/dev/null || echo "error")

if [ "$POLICY_COUNT" -ge 6 ]; then
  p "$POLICY_COUNT RLS policies defined (expected ≥ 6)"
else
  f "only $POLICY_COUNT RLS policies found (expected ≥ 6)"
fi

# Check each required policy exists
REQUIRED_POLICIES="workspaces_select_members memberships_select_own_workspaces documents_select_members documents_insert_owner documents_update_owner documents_delete_owner"

for pol in $REQUIRED_POLICIES; do
  FOUND=$(psql "$LUMO_DB_URL" -t -A -c "
    SELECT count(*) FROM pg_policies WHERE schemaname = 'app' AND policyname = '$pol';
  " 2>/dev/null || echo "0")

  if [ "$FOUND" = "1" ]; then
    p "policy '$pol' exists"
  else
    f "policy '$pol' missing"
  fi
done

# Check no policies exist for anon
ANON_POLICIES=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM pg_policies WHERE schemaname = 'app' AND 'anon' = ANY(roles);
" 2>/dev/null || echo "error")

if [ "$ANON_POLICIES" = "0" ]; then
  p "zero anon policies (deny-by-default — correct)"
else
  f "$ANON_POLICIES anon policies exist — should be zero"
fi

# ---- 7. Update policies have USING + WITH CHECK -----------------------------
echo ""
echo "== 7. UPDATE policy structure =="

UPDATE_USING=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM pg_policies
  WHERE schemaname = 'app' AND cmd = 'UPDATE' AND qual IS NOT NULL;
" 2>/dev/null || echo "0")

UPDATE_WITH_CHECK=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*) FROM pg_policies
  WHERE schemaname = 'app' AND cmd = 'UPDATE' AND with_check IS NOT NULL;
" 2>/dev/null || echo "0")

if [ "$UPDATE_USING" -ge 1 ] && [ "$UPDATE_WITH_CHECK" -ge 1 ]; then
  p "UPDATE policies have both USING and WITH CHECK expressions"
else
  f "UPDATE policies missing USING ($UPDATE_USING) or WITH CHECK ($UPDATE_WITH_CHECK)"
fi

# ---- 8. Default privileges revoked ------------------------------------------
echo ""
echo "== 8. Default privileges =="

DEFAULT_PRIVS=$(psql "$LUMO_DB_URL" -t -A -c "
  SELECT count(*)
  FROM pg_default_acl a
  JOIN pg_namespace n ON a.defnamespace = n.oid
  WHERE n.nspname = 'app'
    AND a.defaclrole IN (
      SELECT oid FROM pg_roles WHERE rolname IN ('anon', 'public')
    );
" 2>/dev/null || echo "error")

if [ "$DEFAULT_PRIVS" = "0" ]; then
  p "no default privileges granted to anon/public on app schema"
else
  w "found $DEFAULT_PRIVS default ACL entries for anon/public — review"
fi

# ---- 9. RLS isolation tests -------------------------------------------------
echo ""
echo "== 9. RLS isolation tests =="

if [ -z "${LUMO_TEST_USER_A:-}" ] || [ -z "${LUMO_TEST_USER_B:-}" ] || [ -z "${LUMO_TEST_USER_C:-}" ]; then
  w "test user UUIDs not set — run deploy/database/create-test-users.sh first"
  s "RLS isolation suite not run"
else
  if sh "$ROOT/tests/security/run-security-tests.sh" >/tmp/lumo-phase3-rls.log 2>&1; then
    p "RLS isolation suite: ALL CHECKS PASSED"
    # Show key assertions
    grep '^PASS:' /tmp/lumo-phase3-rls.log | head -12
  else
    f "RLS isolation suite: FAILED"
    cat /tmp/lumo-phase3-rls.log >&2
  fi
fi

# ---- summary ----------------------------------------------------------------
echo ""
echo "============================================"
echo "  SUMMARY"
echo "============================================"
echo "  PASS: $PASS"
echo "  WARN: $WARN"
echo "  SKIP: $SKIP"
echo "  FAIL: $FAIL"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "RESULT: FAIL — Phase 3 acceptance criteria NOT met."
  echo "Fix the failures above and re-run this script."
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo ""
  echo "RESULT: PASS with warnings — review WARN items."
  exit 0
else
  echo ""
  echo "RESULT: PASS — Phase 3 acceptance criteria met."
  exit 0
fi
