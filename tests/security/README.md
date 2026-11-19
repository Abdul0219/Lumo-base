# tests/security/ — authorization and isolation

Proves that one user cannot read or modify another user's records, and one workspace cannot reach another workspace's data.

## Prerequisites

- Stack running with `database/migrations/*.sql` and `database/policies/*.sql` applied.
- Three test users created through the **GoTrue admin API** (we never `INSERT` into `auth.users` directly).
- Environment:
  ```bash
  export LUMO_DB_URL='postgres://...'      # superuser connection, injected at runtime
  export LUMO_TEST_USER_A='<uuid>'
  export LUMO_TEST_USER_B='<uuid>'
  export LUMO_TEST_USER_C='<uuid>'
  ```

```bash
sh tests/security/run-security-tests.sh
```

The runner seeds two workspaces, three memberships and two documents, then invokes `rls_isolation.sql` and cleans up fixtures on exit (including on failure).

## Coverage

| Attempt | Expected |
| --- | --- |
| A reads own document | allowed |
| A reads B's document in the same workspace | allowed |
| A cannot see workspace B | 0 rows |
| A updates B's document | denied |
| A deletes B's document | denied |
| A inserts with `owner_id = B` | denied |
| C (different workspace) reads documents / workspaces / memberships | 0 rows |
| C inserts into workspace A | denied |
| Direct `INSERT INTO app.workspaces` | denied (RPC-only write path) |
| `anon` reads anything in `app` | 0 rows |
| `service_role` reads everything | allowed (server-side only) |

Complementary SDK-level checks (Storage, RPC, error formats) are in `tests/integration/supabase-compat.test.mjs`.

## Important implementation note

`auth.uid()` reads JWT claims. Upstream releases differ in whether they use `request.jwt.claim.sub` or `request.jwt.claims`. The harness sets **both** and comments that this must be verified against the pinned `supabase/postgres:17.6.1.136` init SQL. Do not change it without checking upstream.

A passing SELECT check is not evidence that INSERT/UPDATE/DELETE are safe. Every verb must be tested. A passing positive test is not evidence that isolation works — the negative tests are the point.
