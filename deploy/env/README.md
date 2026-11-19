# deploy/env/

| File | Tracked? | Purpose |
| --- | --- | --- |
| `.env.example` | **yes** | Sanitized example. All variable names verified against upstream `self-hosted/v0.8.4`. All secret values are `CHANGE_ME` placeholders. |
| `.env` | **no** (gitignored) | Real operator secrets. Created by copying the example. |

```bash
cp deploy/env/.env.example deploy/env/.env
sh scripts/check-secrets.sh    # must pass
```

## Rules

1. **Never commit `deploy/env/.env`.** `scripts/check-secrets.sh` fails the build if a real env file is tracked.
2. **Never invent variable names.** Copy them from `deploy/upstream/env.example.reference` or `docs/VERSIONS.md`. A made-up name silently becomes an empty string in Compose — the most common cause of broken self-hosted deployments.
3. Generate all secrets with the upstream helpers after `scripts/sync-upstream.sh`:
   ```bash
   sh vendor/supabase-docker/utils/generate-keys.sh
   sh vendor/supabase-docker/utils/add-new-auth-keys.sh
   openssl rand -base64 48
   ```
4. `SUPABASE_PUBLISHABLE_KEY` is client-side; `SUPABASE_SECRET_KEY` / `SERVICE_ROLE_KEY` are **server-side only** and bypass RLS.
5. `JWT_SECRET` / `JWT_KEYS` / `JWT_JWKS` are **JWT signing keys**, not API keys. Separate lifecycles — see `docs/SECURITY.md`.
6. Set `DISABLE_SIGNUP=true` for Stage A unless the first internal app needs public signup.
7. Set `SUPABASE_PUBLIC_URL` / `API_EXTERNAL_URL` to the **HTTPS** Caddy host, not `:8000`.
8. `LUMO_BACKUP_*` are consumed by `ops/backup/*.sh` and injected at runtime.

`scripts/lumo.sh` passes this file with `--env-file` from the upstream compose directory. Use `COMPOSE_FILE=docker-compose.yml:docker-compose.lumo.yml` so the override is applied.
