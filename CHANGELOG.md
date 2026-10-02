# Changelog

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
