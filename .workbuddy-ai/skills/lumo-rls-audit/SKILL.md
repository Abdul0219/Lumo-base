---
name: lumo-rls-audit
description: Review or write any Lumo Base table, policy, GRANT, RPC or Storage policy. Enforces RLS + explicit grants, trusted claims only, and negative isolation tests.
---

# Lumo Base — RLS & authorization audit

**Purpose:** PostgreSQL is the authoritative data AND authorization layer. Never let a client self-assert a role or tenant.

## Trigger
Any change under `database/migrations/`, `database/policies/`, `tests/security/`, or a new RPC / Storage bucket policy.

## Rules
1. **RLS at creation.** `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` belongs in the same migration as `CREATE TABLE`. No unguarded window.
2. **Explicit GRANTs too.** RLS is not a substitute for privileges. `anon` gets nothing; `authenticated` gets narrow table privileges; `service_role` is server-side only and must never reach a browser.
3. **Trusted claims only.** Boundaries derive from `auth.uid()` (verified JWT `sub`) or from `app.is_workspace_member()`. Never from a request body, header or query parameter.
4. **SECURITY DEFINER must be narrow.** `SET search_path = ''`, `REVOKE ... FROM PUBLIC`, grant only to the intended role.
5. **Both clauses on UPDATE.** `USING` and `WITH CHECK` must both enforce ownership and membership.
6. **No invented schema.** Upstream roles (`anon`, `authenticated`, `service_role`) and `auth.users` come from the pinned `supabase/postgres:17.6.1.136` init SQL. Do not recreate them.

## Checklist before done
- [ ] RLS enabled on every user-exposed table?
- [ ] Every CRUD verb has a policy, or its absence is documented and reviewed?
- [ ] GRANTs consistent with policies (no over-grant)?
- [ ] Every `SECURITY DEFINER` function is `SET search_path = ''` and revoked from PUBLIC?
- [ ] `sh tests/security/run-security-tests.sh` passes with **two distinct users and two distinct workspaces**?
- [ ] Storage object-level and RPC paths also tested?
- [ ] `docs/SECURITY.md` updated if the trust model changed?

**A passing SELECT check is not evidence that INSERT/UPDATE/DELETE are safe.** Negative tests are the point.

Complementary skills: `ecc-postgres-patterns`, `ecc-database-migrations`, `ecc-agent-security-hardening`, `ecc-security-review`.
