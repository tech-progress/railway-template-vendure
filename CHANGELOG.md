# Changelog

## [2.0.0] - 2026-11-25

- Breaking: the Vendure 3.8 migration is one-way, so this release moves to the `release-v2` channel. Read UPGRADE.md: stop the 1.x worker and API, then back up PostgreSQL and the Bucket, before deploying it.
- Upgrade every official Vendure package to 3.8.2, which fixes GHSA-37xp-mjp8-6f9x (an administrator holding only `UpdateApiKey` could rotate a higher-privileged API key and receive its secret) and the 3.8.0 and 3.8.1 advisories.
- Ship the Vendure 3.8 schema migration, including translation de-duplication and the one-time order line promotion rescale; the API applies it on its first 3.8 boot. Reverting it does not restore deleted translations or rescaled discounts.
- Refresh Node to 22.23.5 Bookworm slim, PostgreSQL to 17.12 Alpine, and Redis to 7.2.17 Alpine by digest, and re-resolve the npm lockfile.
- Add a Podman local check with a 3.7.3-to-3.8.2 upgrade test, and an API key rotation probe in the smoke test that fails on Vendure 3.7.3.
- Local Compose keeps its MinIO service, volume and variables but uses the maintained `pgsty/minio` fork, because the upstream MinIO image can no longer be pulled.
- Remove the health check strategy, which Vendure has ignored since 3.6.0; `/health` answers once the API has applied migrations.

## [1.0.3] - 2026-10-02

- Align all official Vendure packages at 3.7.3 and regenerate the npm lockfile.
- Refresh Node to 22.23.3 Bookworm slim and Redis to 7.2.16 Alpine with registry-verified immutable digests.
- Retain PostgreSQL 17, existing environment variables, and the API/worker/storage topology.

## [1.0.2] - 2026-08-03

- Declare the worker's health listener as Railway's `PORT` so private health checks target port 3020.

## [1.0.1] - 2026-08-03

- Gate worker startup on the API's database-aware health endpoint so first-boot migrations cannot race the worker initializer.

## [1.0.0] - 2026-08-03

- Initial Vendure API, Dashboard, worker, PostgreSQL, Redis, and persistent-assets template.
