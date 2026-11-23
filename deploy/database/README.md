# deploy/database/

Phase 3 — Database migration, policy application, and authorization verification scripts.

## Prerequisites

1. **Phase 2 complete** — Stack running, Postgres healthy, GoTrue responding.
2. **`LUMO_DB_URL` set** — Postgres superuser connection string, injected at runtime.
   ```bash
   # Extract from the running container:
   LUMO_DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@127.0.0.1:5432/postgres"
   ```
3. **`SERVICE_ROLE_KEY` set** — In `deploy/env/.env` (for GoTrue admin API).

## Scripts

| Script | Purpose | Safe to re-run? |
| --- | --- | --- |
| `apply-migrations.sh` | Apply all migrations + policies in order, then verify RLS/GRANTs | Yes (idempotent — uses `CREATE IF NOT EXISTS`, `DROP IF EXISTS`) |
| `create-test-users.sh` | Create 3 test users via GoTrue admin API | Yes (fetches existing UUID if user already exists) |
| `verify-phase3.sh` | Comprehensive acceptance checker (30+ checks) | Yes |

## Execution order

```bash
# 1. Set up the database connection
export LUMO_DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@127.0.0.1:5432/postmost"

# 2. Apply migrations and policies
bash deploy/database/apply-migrations.sh

# 3. Create test users (requires GoTrue running + SERVICE_ROLE_KEY)
bash deploy/database/create-test-users.sh

# 4. Source the test user UUIDs
source /tmp/lumo-test-users.env

# 5. Run the RLS isolation suite
LUMO_DB_URL="$LUMO_DB_URL" bash tests/security/run-security-tests.sh

# 6. Verify Phase 3 acceptance
bash deploy/database/verify-phase3.sh
```

## What gets applied

```
database/
├── migrations/
│   ├── 20261118000100_app_schema.sql    ← tables, indexes, RLS enabled
│   └── 20261118000200_functions.sql     ← SECURITY DEFINER functions
└── policies/
    ├── 001_roles_grants.sql             ← GRANTs/REVOKEs
    └── 002_rls_policies.sql             ← Per-command RLS policies
```

**Order matters.** Migrations create tables with RLS enabled. Functions define
the membership check and workspace creation RPC. Policies are applied last
because they reference functions that must already exist.

## Trust model

```
                    ┌──────────────────────────────────┐
                    │         auth.uid()               │  ← from verified JWT claim
                    │         (never client-supplied)   │
                    └──────────────┬───────────────────┘
                                   │
                    ┌──────────────▼───────────────────┐
                    │  app.is_workspace_member()       │  ← SECURITY DEFINER
                    │  (checks app.memberships)        │     search_path = ''
                    └──────────────┬───────────────────┘     revoked from PUBLIC
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
     ┌────────▼──────┐   ┌────────▼──────┐   ┌────────▼──────┐
     │  SELECT       │   │  INSERT       │   │  UPDATE/      │
     │  policies     │   │  policies     │   │  DELETE       │
     │  (member)     │   │  (owner)      │   │  policies     │
     └───────────────┘   └───────────────┘   │  (owner)      │
                                             └───────────────┘

  anon         → ZERO grants, ZERO policies → denies everything
  authenticated → Limited GRANTs + RLS policies → sees only own workspace data
  service_role  → ALL GRANTs, bypasses RLS → server-side only, never in client
```

## What verify-phase3.sh checks

| # | Check | Method |
| --- | --- | --- |
| 1 | app schema exists | `pg_namespace` query |
| 2 | 3 tables exist with RLS enabled | `pg_class` query |
| 3 | FORCE RLS is off (service_role can bypass) | `pg_class` query |
| 4 | ≥ 3 indexes exist | `pg_indexes` query |
| 5 | SECURITY DEFINER functions have `search_path = ''` | `pg_get_functiondef` regex |
| 6 | SECURITY DEFINER functions revoked from PUBLIC | `has_function_privilege` |
| 7 | anon has ZERO table grants | `information_schema.role_table_grants` |
| 8 | authenticated has limited grants (no direct write to workspaces/memberships) | Grant query |
| 9 | service_role has all CRUD privileges | Grant count |
| 10 | ≥ 6 RLS policies defined | `pg_policies` count |
| 11 | Each required policy exists by name | `pg_policies` lookup |
| 12 | Zero anon policies | `pg_policies` role check |
| 13 | UPDATE policies have both USING and WITH CHECK | `pg_policies` qual/with_check |
| 14 | No default privileges for anon/public | `pg_default_acl` |
| 15 | RLS isolation suite passes (positive + negative tests) | `tests/security/run-security-tests.sh` |

## Rollback

Migrations are **forward-only**. The rollback procedure:

1. Take a pre-migration logical backup before applying:
   ```bash
   bash ops/backup/backup-db.sh
   ```
2. If rollback is needed, restore the pre-migration backup into an isolated
   database, verify it, then re-point the application.
3. See `docs/RECOVERY.md` for the full restore drill procedure.

**Dropping tables directly is destructive and requires explicit owner approval.**

## Known gaps

- The asymmetric JWT key paths (`JWT_KEYS`, `JWT_JWKS`) are Phase 4 — Phase 3
  uses the legacy HS256 `JWT_SECRET` for `auth.uid()` claim verification.
- `auth.uid()` reads JWT claims. Upstream releases differ in whether they use
  `request.jwt.claim.sub` or `request.jwt.claims`. The test harness sets both
  and must be verified against the pinned `supabase/postgres:17.6.1.136` init SQL.
