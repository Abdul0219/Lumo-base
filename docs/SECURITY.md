# Security baseline

## 1. Authorization model

PostgreSQL is authoritative. Two independent layers, both mandatory:

- **Explicit GRANTs** (`database/policies/001_roles_grants.sql`) — `anon` gets nothing, `authenticated` gets narrow table privileges, `service_role` is server-side only.
- **RLS** (`database/policies/002_rls_policies.sql`) — enabled on every user-exposed table at creation time, with per-command policies.

RLS is not a substitute for privileges. A table with RLS but an over-broad GRANT is still a mistake.

## 2. Trusted claims

- `auth.uid()` derives from the **verified JWT claim** `sub`. It is never taken from a request body, header or query string.
- Workspace membership is resolved server-side by `app.is_workspace_member()` (SECURITY DEFINER, `search_path = ''`, revoked from PUBLIC).
- Clients cannot self-assert `owner_id`, `role` or `workspace_id`: INSERT policies require `owner_id = auth.uid()` AND membership; `app.workspaces` / `app.memberships` are writable only through `app.create_workspace()`.
- Negative tests for cross-user and cross-tenant reads, inserts, updates, deletes and storage access live in `tests/security/rls_isolation.sql` and `tests/integration/supabase-compat.test.mjs`.

## 3. API keys vs JWT signing keys — distinct lifecycles

| Kind | Variables | Purpose |
| --- | --- | --- |
| Publishable / secret **API keys** | `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` | Client identification at the gateway |
| Legacy HS256 API keys | `ANON_KEY`, `SERVICE_ROLE_KEY` | Compatibility with older clients |
| **JWT signing keys** | `JWT_SECRET`, `JWT_KEYS`, `JWT_JWKS` | Signing/validating user sessions |
| Gateway-internal pre-signed keys | `ANON_KEY_ASYMMETRIC`, `SERVICE_ROLE_KEY_ASYMMETRIC` | Internal only, never in client code |

**Do not conflate them.** Do not assume every service dynamically fetches keys from one common JWKS URL — configure each service using the mechanism documented for `self-hosted/v0.8.4`. Verify against the pinned release before rotating anything.

## 4. Signing-key lifecycle

1. Generate with the upstream helpers (`utils/generate-keys.sh`, `utils/add-new-auth-keys.sh`), never by hand.
2. Record a **key ID**, creation date and the services consuming each key in `deploy/versions.lock.json` upgrade notes.
3. Distribute using each service's supported mechanism. Test login, refresh, logout, expiry, invalid signature, rotation and revoked-key behaviour.
4. Rotation: add the new key, verify all services accept it, then revoke the old key. **Rotation and revocation are production changes requiring explicit approval.**
5. Revocation/incident procedure is in `docs/OPERATIONS.md`.

## 5. Secrets

- All secrets live in `deploy/env/.env` (gitignored) or a secret manager. Never in source control, CI logs, issues or chat.
- `scripts/check-secrets.sh` blocks tracked `.env` files, private keys, tokens and upstream demo JWTs.
- `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` protect Studio. They must be strong and never shared.
- `SUPABASE_SECRET_KEY` and `SERVICE_ROLE_KEY` bypass RLS — they must never reach a browser, mobile app or public repo.
- Admin/metadata endpoints stay private. Only **443** is public (see `docs/VERSIONS.md`).

## 6. Network and TLS

Caddy terminates TLS on 443, forwards to `127.0.0.1:8000`. `docker-compose.lumo.yml` rebinds upstream's 8000/5432/6543 exposures to loopback. HSTS, nosniff, DENY frame and no-referrer headers are set in `deploy/proxy/Caddyfile`. Firewall allows 22 (operator IPs), 80 (ACME) and 443; all other ports are denied.

## 7. Audit and review

- Privileged administrative actions are audited; key rotation, credential revocation and incident response are documented.
- `ops/monitoring/healthcheck.sh` fails if a private port is exposed on a non-loopback interface.
- Before each phase gate, run the `lumo-rls-audit` skill checklist in `database/policies/README.md`.

## 8. Deferred security work

Per-project secrets across customers, tenant isolation for paying customers, commercial quotas and a customer-facing control plane are **Stage B** and are deliberately not built. See `docs/DEFERRED.md`.
