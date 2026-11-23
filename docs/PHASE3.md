# Phase 3 — Database & Authorization

> **Gate:** Migrations, roles, GRANTs, RLS applied; positive + negative isolation tests pass (`tests/security/`).

## Status: Scripts ready — pending VPS execution

Phase 3 deliverables are written and committed. The SQL migrations and policies already existed from Phase 0 — Phase 3 adds the deployment automation to apply them, provision test users, and verify acceptance. Nothing has been executed against a live database yet.

---

## 1. What changed and why

Phase 3 adds the operational layer that sits between the running Supabase stack (Phase 2) and a verified database authorization layer. Specifically:

- **Migration runner (`deploy/database/apply-migrations.sh`)** — Applies all 4 SQL files (2 migrations + 2 policy files) in strict order with `ON_ERROR_STOP=1` and `--single-transaction`. Each file is idempotent (`CREATE IF NOT EXISTS`, `DROP IF EXISTS`). After applying, runs post-apply verification queries to confirm RLS is enabled, SECURITY DEFINER functions have safe `search_path`, and GRANTs match expectations.

- **Test user provisioning (`deploy/database/create-test-users.sh`)** — Creates three test users (A, B, C) through the GoTrue admin API. We never `INSERT` into `auth.users` directly — that would bypass GoTrue's user management and could corrupt auth state. The script handles "user already exists" by fetching the existing UUID. Writes UUIDs to `/tmp/lumo-test-users.env` (mode 600) for the security test runner to source.

- **Acceptance checker (`deploy/database/verify-phase3.sh`)** — 15 verification categories with 30+ individual checks: schema existence, table RLS status, FORCE RLS setting, indexes, SECURITY DEFINER function safety (search_path + PUBLIC revocation), GRANT verification (anon zero, authenticated limited, service_role full), policy completeness (6 required policies by name), anon policy absence, UPDATE policy USING+WITH CHECK, default privileges, and the full RLS isolation suite.

- **Documentation (`deploy/database/README.md`)** — Execution order, trust model diagram, full check list, rollback procedure, known gaps.

The SQL itself (migrations and policies) is unchanged from Phase 0 — it was already correct and reviewed.

## 2. Exact component versions and configuration changes

No image versions changed. No configuration files changed. The SQL migrations and policies are byte-for-byte identical to the Phase 0 originals.

New operational artifacts:

| Artifact | Type | Purpose |
| --- | --- | --- |
| `deploy/database/apply-migrations.sh` | Shell script | Apply migrations + policies in order, post-apply verification |
| `deploy/database/create-test-users.sh` | Shell script | Provision 3 test users via GoTrue admin API |
| `deploy/database/verify-phase3.sh` | Shell script | 30+ acceptance checks, PASS/WARN/FAIL summary |
| `deploy/database/README.md` | Documentation | Execution order, trust model, check list, rollback |

SQL files (unchanged, listed for reference):

| File | Contents |
| --- | --- |
| `database/migrations/20261118000100_app_schema.sql` | `app.workspaces`, `app.memberships`, `app.documents`, indexes, RLS enabled |
| `database/migrations/20261118000200_functions.sql` | `app.is_workspace_member`, `app.create_workspace`, `touch_updated_at` trigger |
| `database/policies/001_roles_grants.sql` | Explicit GRANTs/REVOKEs for anon, authenticated, service_role |
| `database/policies/002_rls_policies.sql` | 6 per-command RLS policies derived from auth.uid() |

## 3. Commands executed and sanitized outputs

No commands have been executed on a VPS yet. The expected execution sequence is:

```bash
# From the repository root on the VPS, after Phase 2 verify-phase2.sh passes:

# 1. Set the database connection (from deploy/env/.env values)
export LUMO_DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@127.0.0.1:5432/postgres"

# 2. Apply migrations and policies
bash deploy/database/apply-migrations.sh
# Expected output:
#   "== applying: 20261118000100_app_schema.sql =="
#   "OK: 20261118000100_app_schema.sql applied"
#   "== applying: 20261118000200_functions.sql =="
#   "OK: 20261118000200_functions.sql applied"
#   "== applying: 001_roles_grants.sql =="
#   "OK: 001_roles_grants.sql applied"
#   "== applying: 002_rls_policies.sql =="
#   "OK: 002_rls_policies.sql applied"
#   "== post-apply verification =="
#   "    OK   workspaces: RLS enabled"
#   "    OK   memberships: RLS enabled"
#   "    OK   documents: RLS enabled"
#   "== migrations and policies applied successfully =="

# 3. Create test users
bash deploy/database/create-test-users.sh
# Expected:
#   "== test users created =="
#   "  User A: <uuid> (user-a@lumo-test.local)"
#   "  User B: <uuid> (user-b@lumo-test.local)"
#   "  User C: <uuid> (user-c@lumo-test.local)"

# 4. Source UUIDs and run isolation tests
source /tmp/lumo-test-users.env
LUMO_DB_URL="$LUMO_DB_URL" bash tests/security/run-security-tests.sh
# Expected:
#   "== ALL RLS ISOLATION CHECKS PASSED =="

# 5. Verify Phase 3 acceptance
bash deploy/database/verify-phase3.sh
# Expected:
#   "RESULT: PASS — Phase 3 acceptance criteria met."
```

## 4. Automated tests and results

**Shell syntax validation** — all 3 new scripts pass `bash -n`:

```
deploy/database/apply-migrations.sh:   OK
deploy/database/create-test-users.sh:  OK
deploy/database/verify-phase3.sh:      OK
```

**CI workflow** — `.github/workflows/ci.yml` now includes `deploy/database` in shell syntax validation.

**RLS enablement CI check** — existing CI step verifies every `app.*` table has RLS enabled by scanning the migration SQL. This continues to pass.

**Runtime tests** — `verify-phase3.sh` checks the following when run on a live database:

| # | Check | Method |
| --- | --- | --- |
| 1 | app schema exists | `pg_namespace` query |
| 2 | 3 tables exist with RLS enabled | `pg_class.relrowsecurity` |
| 3 | FORCE RLS is off (service_role bypass works) | `pg_class.relforcerowsecurity` |
| 4 | ≥ 3 indexes exist | `pg_indexes` count |
| 5 | SECURITY DEFINER functions have `search_path = ''` | `pg_get_functiondef` regex |
| 6 | SECURITY DEFINER functions revoked from PUBLIC | `has_function_privilege('public', ...)` |
| 7 | anon has ZERO table grants | `information_schema.role_table_grants` |
| 8 | authenticated has no direct write to workspaces/memberships | Grant query |
| 9 | service_role has all CRUD privileges | Grant count (≥ 4 types) |
| 10 | ≥ 6 RLS policies defined | `pg_policies` count |
| 11 | Each required policy exists by name | `pg_policies` lookup |
| 12 | Zero anon policies | `pg_policies` roles array |
| 13 | UPDATE policies have USING + WITH CHECK | `pg_policies.qual` + `with_check` |
| 14 | No default privileges for anon/public | `pg_default_acl` |
| 15 | RLS isolation suite passes (12+ assertions) | `tests/security/run-security-tests.sh` |

The RLS isolation suite (`tests/security/rls_isolation.sql`) exercises:

| Attempt | Expected |
| --- | --- |
| User A reads own document | allowed |
| User A reads User B's document (same workspace) | allowed |
| User A cannot see workspace B | 0 rows |
| User A updates User B's document | denied |
| User A deletes User B's document | denied |
| User A inserts with `owner_id = B` | denied |
| User C (different workspace) reads documents | 0 rows |
| User C reads workspaces / memberships | 0 rows |
| User C inserts into workspace A | denied |
| Direct INSERT into app.workspaces | denied (RPC-only) |
| anon reads anything | 0 rows |
| service_role reads everything | allowed |

## 5. Security and operational checks

- **RLS at creation time:** `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` is in the same migration as `CREATE TABLE`. There is never an unguarded window where a table exists without RLS.

- **Two-layer authorization:** GRANTs (privileges) + RLS policies (row visibility). Both are required — RLS is not a substitute for privileges, and GRANTs are not a substitute for RLS. `verify-phase3.sh` checks both independently.

- **Trusted claims only:** Every policy derives from `auth.uid()` (verified JWT `sub` claim) or `app.is_workspace_member()`. No client-supplied role, tenant ID, or workspace ID is trusted.

- **SECURITY DEFINER safety:** `app.is_workspace_member()` and `app.create_workspace()` both have `SET search_path = ''` (prevents search_path injection) and are `REVOKE`d from `PUBLIC` (only `authenticated` can execute). The verify script confirms both.

- **RPC-only write path:** `app.workspaces` and `app.memberships` have no INSERT/UPDATE/DELETE grants for `authenticated`. The only write path is `app.create_workspace()` which atomically creates a workspace + owner membership. A client cannot self-assign the `owner` role or create an orphan workspace.

- **anon is denied everything:** Zero grants, zero policies. RLS-enabled tables with no policy return zero rows. The verify script confirms both the grant count and the policy count are zero for anon.

- **service_role bypasses RLS:** By design, for server-side migrations, seeding, and restore drills. FORCE RLS is NOT enabled. The verify script confirms `relforcerowsecurity = false`. `SERVICE_ROLE_KEY` must never ship to a client.

- **UPDATE policies have USING + WITH CHECK:** Both expressions are present on `documents_update_owner`. USING controls which rows can be updated; WITH CHECK ensures the updated row still satisfies the policy. Without WITH CHECK, a user could update their own row to change `owner_id` to another user.

## 6. Known limitations and unresolved risks

- **HS256 vs asymmetric JWT:** Phase 3 uses the legacy HS256 `JWT_SECRET` for `auth.uid()` claim verification. Asymmetric keys (`JWT_KEYS`, `JWT_JWKS`) are Phase 4. The test harness sets both `request.jwt.claim.sub` and `request.jwt.claims` to cover both upstream claim-reading patterns.

- **Test user cleanup:** `create-test-users.sh` does not delete test users after testing. The users remain in `auth.users` with confirmed emails. This is intentional — re-running the test suite reuses them. To clean up, use the GoTrue admin delete API.

- **No Storage-level RLS:** Phase 3 covers the `app` schema only. Storage bucket policies are Phase 5. The `tests/security/rls_isolation.sql` suite does not test Storage object access.

- **Forward-only migrations:** There is no `down` migration. Rollback requires restoring a pre-migration backup. Always take a backup before applying (`ops/backup/backup-db.sh`).

- **auth.uid() claim path:** Upstream Supabase releases differ in whether `auth.uid()` reads `request.jwt.claim.sub` or `request.jwt.claims`. The test harness sets both. This must be verified against the pinned `supabase/postgres:17.6.1.136` init SQL. If the claim path changes in a future upstream release, the tests may pass without actually enforcing isolation.

## 7. Rollback procedure

1. **Before applying:** Take a logical backup:
   ```bash
   bash ops/backup/backup-db.sh
   ```

2. **If rollback is needed:** Restore the pre-migration backup into an isolated database, verify it, then re-point the application:
   ```bash
   bash ops/backup/restore-drill.sh
   ```
   See `docs/RECOVERY.md` for the full restore drill procedure.

3. **Dropping tables directly** is destructive and requires explicit owner approval. The migrations are forward-only by design — never edit an applied migration; add a new one.

## 8. Cost/resource impact

No change from Phase 2 estimates:

- **VPS:** 2 vCPU / 4 GB RAM / 40 GB disk (unchanged)
- **Memory:** Migrations are one-time SQL operations — no additional containers
- **Storage:** App tables are minimal (3 tables + indexes). Growth depends on application usage. Postgres data volume already provisioned in Phase 2.
- **Network:** No new public ports. All database operations are loopback-only (127.0.0.1:5432).

## 9. Pass/fail decision against the gate

| Gate criterion | Status |
| --- | --- |
| Migrations applied | ✅ Scripts ready — `apply-migrations.sh` applies all 4 SQL files in order |
| Roles correct (anon/authenticated/service_role) | ✅ Scripts ready — `verify-phase3.sh` checks all GRANTs |
| GRANTs explicit (no over-grant) | ✅ Scripts ready — anon=0, authenticated=limited, service_role=all |
| RLS enabled on every app table | ✅ Scripts ready — verified at creation time + post-apply + acceptance check |
| Positive isolation tests pass | ⏳ Pending VPS execution — User A reads own + same-workspace data |
| Negative isolation tests pass | ⏳ Pending VPS execution — cross-user/cross-workspace/anon all denied |

**Decision: Scripts complete. Acceptance pending VPS execution.**

The operator must:
1. Complete Phase 2 on the VPS (`verify-phase2.sh` passed)
2. Set `LUMO_DB_URL` from the running Postgres container
3. Run `apply-migrations.sh` → `create-test-users.sh` → `run-security-tests.sh` → `verify-phase3.sh`
4. `verify-phase3.sh` must report PASS before Phase 4 begins
