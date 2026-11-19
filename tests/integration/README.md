# tests/integration/ — SDK & API conformance

Real `@supabase/supabase-js` calls against a running Lumo Base stack. **No mocks, no stubs.** If the stack is not configured, every test SKIPS — a skip is never reported as a pass.

## Setup

```bash
cd tests/integration
npm ci
export LUMO_SUPABASE_URL="https://your-domain.example.com"
export LUMO_PUBLISHABLE_KEY="..."   # SUPABASE_PUBLISHABLE_KEY from deploy/env/.env
export LUMO_SERVICE_KEY="..."       # SUPABASE_SECRET_KEY — server-side ONLY
npm test
```

The secret key must never appear in a browser, a mobile build, CI logs or this repository. Inject it from your secret store at runtime.

## What is covered

| Workflow | Test |
| --- | --- |
| Auth | sign in, `getSession`, `refreshSession`, invalid signature rejection, sign out |
| REST | select, `eq` filter, `order`/`limit`, insert, update, delete |
| RPC | `app.create_workspace` success; unauthenticated rejection |
| RLS | cross-workspace SELECT returns zero rows; cross-workspace INSERT denied |
| Storage | upload, list, download, signed URL, cross-user denial |
| Errors | PostgREST-shaped `message` / `code` / `details` / `hint` |

## Deferred / deliberately not claimed

Realtime, Edge Functions and GraphQL are **not implemented** in Stage A. There are no tests pretending otherwise. Add them in Phase 6 *before* enabling the service, then re-run this suite.

## Acceptance rule

A compatibility claim may only be entered into [`docs/COMPATIBILITY.md`](../../docs/COMPATIBILITY.md) when the corresponding test passes against the **pinned** SDK version (`2.119.1`) and the **pinned** release (`self-hosted/v0.8.4`), with the test output attached to the phase report. Claims without evidence are forbidden.
