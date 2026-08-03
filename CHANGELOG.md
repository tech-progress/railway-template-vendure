# Changelog

## [1.0.2] - 2026-08-03

- Declare the worker's health listener as Railway's `PORT` so private health checks target port 3020.

## [1.0.1] - 2026-08-03

- Gate worker startup on the API's database-aware health endpoint so first-boot migrations cannot race the worker initializer.

## [1.0.0] - 2026-08-03

- Initial Vendure API, Dashboard, worker, PostgreSQL, Redis, and persistent-assets template.
