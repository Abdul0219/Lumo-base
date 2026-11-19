# database/policies/

Authorization is two independent layers. **Both are required** — RLS is not a substitute for privileges, and GRANTs are not a substitute for RLS.

| File | Layer | What it does |
| --- | --- | --- |
| `001_roles_grants.sql` | Privileges | Explicit `GRANT`/`REVOKE` on schema, tables, sequences and functions for `anon`, `authenticated`, `service_role` |
| `002_rls_policies.sql` | Row Level Security | Per-command (`SELECT`/`INSERT`/`UPDATE`/`DELETE`) policies derived from `auth.uid()` and `app.is_workspace_member()` |

## Trust model

- `auth.uid()` comes from the **verified JWT claim** `sub`. It is never read from a request body, header or query parameter.
- Workspace membership is looked up in `app.memberships` by a `SECURITY DEFINER` function owned by the migration role, so RLS on `memberships` cannot recurse.
- `anon` receives **zero** grants and **zero** policies: RLS-enabled tables with no policy deny all rows.
- `service_role` bypasses RLS by design. It is for server-side migrations, seeding and restore drills only. **Never** ship `SUPABASE_SECRET_KEY` or `SERVICE_ROLE_KEY` to a browser or a mobile app.
- `app.create_workspace()` is the only write path into `app.workspaces` / `app.memberships`, so a client cannot create an orphan workspace or self-assign the `owner` role.

## Mandatory test coverage

`tests/security/rls_isolation.sql` proves, with real sessions:

| Attempt | Expected |
| --- | --- |
| User A reads own document | allowed |
| User A reads User B's document (same workspace) | allowed (workspace members) |
| User A updates/deletes User B's document | denied |
| User A inserts a document with `owner_id = B` | denied |
| User C (different workspace) reads A's document | denied |
| User C inserts into A's workspace | denied |
| User C reads A's workspace / memberships | denied |
| `anon` reads anything in `app` | denied |
| `service_role` reads everything | allowed (server-side only) |

Also test Storage object-level access and any RPC path added later. **All CRUD verbs and every RPC must be covered.** A passing "SELECT is blocked" test is not evidence that INSERT/UPDATE/DELETE are.

## Review checklist (use `lumo-rls-audit`)

1. Is RLS enabled on every table exposed to PostgREST / Storage?
2. Does each command have a policy, or is its absence documented and reviewed?
3. Are `USING` and `WITH CHECK` both present on `UPDATE`?
4. Are explicit GRANTs consistent with the policies (no over-grant)?
5. Is any `SECURITY DEFINER` function `SET search_path = ''` and revoked from `PUBLIC`?
6. Did the negative tests actually run against two distinct users and two distinct workspaces?
