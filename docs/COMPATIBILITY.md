# Compatibility contract

**Rule:** classify every SDK/API feature as **Fully compatible**, **Partially compatible** or **Not implemented**. Test against real `supabase-js` versions. **Never advertise complete Supabase compatibility without conformance evidence.**

Pinned client: `@supabase/supabase-js` `2.119.1` (verified against npm 2026-11-18).
Pinned server: Supabase `self-hosted/v0.8.4`.

## Matrix (Stage A, evidence required before each status is claimed)

| Feature | Classification | Evidence required | Status |
| --- | --- | --- | --- |
| Auth: email sign-in | Fully compatible | `tests/integration` sign-in assertion | **untested — not claimed** |
| Auth: `getSession` / `refreshSession` | Fully compatible | refresh + token assertions | **untested — not claimed** |
| Auth: expiry, invalid signature, logout | Fully compatible | negative assertions | **untested — not claimed** |
| REST: select, `eq` filter, `order`, `limit` | Fully compatible | PostgREST query tests | **untested — not claimed** |
| REST: insert / update / delete | Fully compatible | CRUD tests + RLS checks | **untested — not claimed** |
| RPC (`app.create_workspace`) | Fully compatible | success + unauthenticated denial | **untested — not claimed** |
| RLS: cross-user / cross-tenant denial | Fully compatible | `tests/security/rls_isolation.sql` | **untested — not claimed** |
| Storage: upload / download / list | Fully compatible | object round-trip tests | **untested — not claimed** |
| Storage: signed URLs | Fully compatible | `createSignedUrl` assertion | **untested — not claimed** |
| Storage: bucket/object policies | Partially compatible | cross-user denial tests | **untested — not claimed** |
| Error formats (`message`/`code`/`details`/`hint`) | Partially compatible | error-shape assertion | **untested — not claimed** |
| Realtime (`supabase/realtime:v2.148.3`) | **Not implemented** | service is behind the `optional` profile, OFF | n/a |
| Edge Functions (`supabase/edge-runtime:v1.77.9`) | **Not implemented** | service is behind the `optional` profile, OFF | n/a |
| GraphQL (`pg_graphql`) | **Not implemented** | not deployed | n/a |
| Analytics / Log Explorer | **Not implemented** | Logflare/Vector not deployed | n/a |
| Multi-project provisioning, quotas, metering | **Not implemented** | commercial control plane deferred | n/a |

> **Important:** every row above is currently `untested — not claimed`. That is deliberate. A status may only be changed to "Fully compatible" or "Partially compatible" when the corresponding test in `tests/integration/supabase-compat.test.mjs` has **passed** against the pinned versions, with output attached to the Phase 7 gate report. A green CI job that SKIPPED the tests is not evidence.

## Known limitations to document honestly

- Self-hosted Supabase is not the managed platform: no dashboard-hosted project management, no platform-level logs/analytics, no automatic upgrades.
- New-style publishable/secret API keys and legacy HS256 `anon`/`service_role` keys coexist in this release; both must be configured correctly. Do not assume key-minting behaviour.
- Optional services are **off**. Any SDK call to `.channel()` (Realtime), `.functions.invoke()` or GraphQL will fail.
- `meta` and `db-config` have no upstream healthcheck in this release — monitoring reports them as `no-healthcheck` rather than healthy.
- Image digests are recorded only after `docker compose pull`; until then tags are pinned but not immutable.

## Adding a capability

1. Enable the service only after Phase 6 approval and a measured memory check.
2. Add the SDK workflow to the integration suite **before** changing this matrix.
3. Run the suite against the pinned versions, attach output, update the row and `web/index.html`.
4. Re-run `sh scripts/verify-manifest.sh`.
