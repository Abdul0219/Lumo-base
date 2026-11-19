---
name: lumo-secret-hygiene
description: Guard secrets in Lumo Base. Use when touching .env files, compose environment blocks, CI, logs, backup credentials or JWT/API keys.
---

# Lumo Base — Secret hygiene

**Purpose:** keep all secrets out of source control and logs.

## Trigger
Editing `deploy/env/*`, any `environment:` block, `.github/workflows/*`, backup scripts, or anything that handles `JWT_SECRET`, `SUPABASE_SECRET_KEY`, `SERVICE_ROLE_KEY`, `POSTGRES_PASSWORD`, `DASHBOARD_PASSWORD` or backup keys.

## Rules
1. Only `deploy/env/.env.example` is tracked. `deploy/env/.env` is gitignored. Never commit a real env file.
2. All example values are `CHANGE_ME` placeholders. Never paste a generated key, an upstream demo JWT, or a real password into a tracked file, an issue, a chat message or a log.
3. `sh scripts/check-secrets.sh` must pass. It rejects tracked env files, private keys, `sk-`/`ghp_`/AKIA tokens and the upstream demo HS256 JWTs.
4. **API keys != JWT signing keys** (see `docs/SECURITY.md` §3). Do not use one in place of the other.
5. `SUPABASE_SECRET_KEY` / `SERVICE_ROLE_KEY` bypass RLS — server-side only.
6. Generate secrets with the upstream helpers or `openssl rand`; never hand-write them.
7. Backup encryption keys and destination credentials are injected at runtime from a protected store.
8. In CI, inject secrets via environment; never echo them. Sanitize command output before attaching it to a phase report.

## Done condition
`check-secrets.sh` passes, `.gitignore` still covers `.env`, and no log line contains a secret-shaped value.

Complementary skills: `ecc-agent-security-hardening`, `ecc-security-scan`.
