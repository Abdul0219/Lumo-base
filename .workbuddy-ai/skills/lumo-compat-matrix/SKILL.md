---
name: lumo-compat-matrix
description: Use when changing SDK-facing behavior or making any Supabase compatibility claim. Requires real supabase-js conformance evidence before changing a matrix row.
---

# Lumo Base — Compatibility matrix

**Purpose:** never advertise complete Supabase compatibility without conformance evidence.

## Trigger
Any change to REST/Auth/Storage/RPC behaviour, enabling an optional service, bumping `@supabase/supabase-js`, or editing `docs/COMPATIBILITY.md` / the console's compatibility section.

## Rules
1. Classify every feature as **Fully compatible**, **Partially compatible** or **Not implemented**. There is no fourth state and no "probably works".
2. Evidence = a **passing** test in `tests/integration/supabase-compat.test.mjs` against the pinned SDK and pinned release, with output attached to the Phase 7 gate. A SKIPPED test is not evidence.
3. Test scope: auth (sign in, refresh, expiry, invalid signature, logout), REST (select, filters, order/limit, insert, update, delete), RPC, Storage (upload, download, signed URL), error formats, and cross-user/cross-tenant denial.
4. Realtime, Edge Functions and GraphQL remain **Not implemented** while behind the `optional` profile. Never show them as enabled in `web/index.html`.
5. Document known limitations honestly: no managed-platform features, coexisting new/legacy API keys, missing upstream healthchecks on `meta`/`db-config`.
6. On any change, re-run `sh scripts/verify-manifest.sh` and update `docs/COMPATIBILITY.md` + `web/index.html` together.

## Done condition
Every changed row cites a specific passing test name and the exact versions it ran against. No row reads "Fully compatible" with an untested status.

Complementary skills: `ecc-e2e-testing`, `ecc-ai-regression-testing`, `ecc-agent-eval`.
