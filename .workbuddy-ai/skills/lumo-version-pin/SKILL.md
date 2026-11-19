---
name: lumo-version-pin
description: Add or upgrade any Docker image, SDK or upstream Supabase release in Lumo Base. Enforces pinned tags, immutable digests, manifest parity and documentation sync.
---

# Lumo Base — Version pinning

**Purpose:** no floating `latest`, no invented values, no stale docs after a version change.

## Trigger
Changing any image tag, `self-hosted/*` release tag, `@supabase/supabase-js` version, or adding a new service.

## Procedure
1. **Verify upstream first.** Fetch the exact tag's `docker/docker-compose.yml` and `.env.example`. Read image tags, service names, env var names and ports. Never guess them. Use `docs/UPSTREAM.md` for the canonical URLs.
2. `sh scripts/sync-upstream.sh <tag>` and read the diff. Only then `sh scripts/sync-upstream.sh <tag> --accept-upstream`.
3. Update **together**, in one change:
   - `deploy/versions.lock.json` (tags, digest reset to `null`, new `fetched_at`)
   - `docs/VERSIONS.md` (table, env groups, ports, upgrade notes)
   - `docs/ARCHITECTURE.md` (service inventory, memory budget)
   - `docs/COMPATIBILITY.md` (re-classify affected features as untested)
   - `web/index.html` (console version strings)
   - `CHANGELOG.md`
4. `sh scripts/verify-manifest.sh` — must pass. It compares every manifest entry against the vendored compose and checks the SDK version matches `tests/integration/package.json`.
5. `docker compose pull`, then `sh scripts/verify-manifest.sh --record-digests` to write immutable `sha256:` digests.
6. Re-run `tests/integration` and `tests/security` in staging before claiming compatibility.

## Done condition
`verify-manifest.sh` passes, digests recorded, every doc above agrees on the same tag, and conformance output is attached to the phase gate.

## Anti-patterns
- `:latest` in production.
- Changing one version string and leaving the console/docs stale.
- Claiming "fully compatible" without a passing SDK test.

Complementary skills: `ecc-docker-patterns`, `ecc-deployment-patterns`, `ecc-architecture-decision-records`.
