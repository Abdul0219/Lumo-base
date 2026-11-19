# NOTICE

Lumo Base original source code, scripts, SQL, tests and documentation are
released under the MIT License (see LICENSE).

Lumo Base vendors one configuration file from the official Supabase repository:

- `deploy/compose/upstream.docker-compose.yml` — copied verbatim from
  `docker/docker-compose.yml` at tag `self-hosted/v0.8.4`
  https://github.com/supabase/supabase/tree/self-hosted/v0.8.4/docker
  Copyright (c) Supabase. Licensed under the Apache License, Version 2.0.
  A short provenance header was prepended; no other content was modified.

- `deploy/upstream/env.example.reference` — copied verbatim from
  `docker/.env.example` at the same tag, retained as a read-only reference so
  environment variable names can be verified without guessing. It is NOT used
  at runtime. The tracked runtime example is `deploy/env/.env.example`.

Additional upstream configuration (Envoy YAML, database init SQL, `run.sh`,
utility scripts) is fetched at the same pinned tag by
`scripts/sync-upstream.sh` into `vendor/supabase-docker/`, which is gitignored.
Those files remain Apache-2.0 (c) Supabase and are not redistributed in this
repository.

"Supabase" is a trademark of Supabase Inc. Lumo Base is an independent,
unofficial self-hosted deployment configuration and does not claim full
compatibility without conformance evidence (see docs/COMPATIBILITY.md).
