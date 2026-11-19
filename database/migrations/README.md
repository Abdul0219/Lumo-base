# database/migrations/

Versioned, forward-only SQL for the **Lumo Base application schema** (`app`). These are our tables, not upstream Supabase definitions — upstream roles, `auth.users`, `storage.*` and `_realtime` are created by the official `supabase/postgres:17.6.1.136` init SQL fetched by `scripts/sync-upstream.sh`.

| Order | File | Contents |
| --- | --- | --- |
| 1 | `20261118000100_app_schema.sql` | `app.workspaces`, `app.memberships`, `app.documents`, indexes, RLS enabled |
| 2 | `20261118000200_functions.sql` | `app.is_workspace_member`, `app.create_workspace`, `updated_at` trigger |

## Rules

- **Forward-only.** Never edit an applied migration; add a new one.
- **RLS at creation time.** `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` is in the same migration as `CREATE TABLE` so there is never an unguarded window.
- **No client-asserted tenancy.** `workspace_id` is checked against `app.memberships`; `owner_id` must equal `auth.uid()`.
- **SECURITY DEFINER is narrow.** Every such function sets `search_path = ''`, is `REVOKE`d from `PUBLIC`, and is granted only to `authenticated`.
- Apply policies in `database/policies/` **after** migrations, in numeric order.

## Apply (Phase 3 approval gate required)

```bash
psql "$LUMO_DB_URL" -v ON_ERROR_STOP=1 -f database/migrations/20261118000100_app_schema.sql
psql "$LUMO_DB_URL" -v ON_ERROR_STOP=1 -f database/migrations/20261118000200_functions.sql
psql "$LUMO_DB_URL" -v ON_ERROR_STOP=1 -f database/policies/001_roles_grants.sql
psql "$LUMO_DB_URL" -v ON_ERROR_STOP=1 -f database/policies/002_rls_policies.sql
sh tests/security/run-security-tests.sh
```

`LUMO_DB_URL` is injected at runtime from the operator's secret store. It is never stored in this repo.

## Rollback

Migrations are forward-only. The rollback procedure for Phase 3 is to restore the pre-migration logical backup into an isolated database, verify it, then re-point the application. See `docs/RECOVERY.md`. Dropping these tables is a destructive operation that requires explicit approval.
