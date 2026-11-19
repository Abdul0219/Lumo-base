# deploy/proxy/ — TLS ingress

`Caddyfile` is the only ingress configuration. It terminates TLS on **443** and reverse-proxies to the Envoy gateway bound on `127.0.0.1:8000`.

## Public attack surface

| Port | Purpose | Public? |
| --- | --- | --- |
| 443 | HTTPS ingress (Caddy) | **yes** |
| 80 | ACME HTTP-01 challenge only, redirects to 443 | yes |
| 22 | SSH, restricted to operator IPs | yes |
| 8000 | Envoy `api-gw` | no — 127.0.0.1 |
| 5432 | Postgres session pool (supavisor) | no — 127.0.0.1 |
| 6543 | Postgres transaction pool (supavisor) | no — 127.0.0.1 |
| 3000 / 8080 / 9999 / 5000 / 4000 | studio / meta / auth / storage / supavisor health | Docker network only |

Studio is **not** a separate public hostname. It is reached through the gateway at `https://{$PROXY_DOMAIN}/` and protected by `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` HTTP basic auth, as configured in the upstream Envoy config. Keep those credentials out of git.

## Container example

```bash
docker run -d --name lumo-caddy \
  --network host \
  --env-file deploy/env/.env \
  -v "$PWD/deploy/proxy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v caddy_data:/data \
  -v caddy_logs:/var/log/caddy \
  --restart unless-stopped \
  caddy:2
```

Pin the Caddy image tag in `deploy/versions.lock.json` before production. `scripts/lumo.sh` does not start Caddy automatically — TLS ingress is a Phase 2 acceptance item and needs explicit approval.

## Operational notes

- HSTS is set in the Caddyfile; confirm TLS works before enabling `includeSubDomains` permanently on a domain with other subdomains.
- Certificate renewal is automatic in Caddy; `ops/monitoring/healthcheck.sh` verifies the HTTPS endpoint responds.
- Log rotation is configured inside the Caddyfile (10 MiB × 3), matching the container log policy.
- DNS changes require explicit approval (see `lumo-phase-gate`).
