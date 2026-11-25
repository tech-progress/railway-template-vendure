# Vendure commerce Railway template

The current template release is `v2.0.0`. It deploys Vendure `3.8.2` on Node `22.23.5` Bookworm slim with the Admin Dashboard, a detached BullMQ worker, PostgreSQL `17.12` Alpine, authenticated Redis `7.2.17` Alpine, and durable object storage. Runtime images are pinned by digest.

Upstream project: [Vendure](https://www.vendure.io).

## Deploy on Railway

Railway generates `SUPERADMIN_PASSWORD`, `COOKIE_SECRET`, `POSTGRES_PASSWORD`, and `REDIS_PASSWORD`; the default administrator identifier is `admin`. After deployment, open `https://<vendure-domain>/dashboard` and use those values. The server runs committed migrations before it starts listening, and the worker waits until the server's `/health` endpoint answers, so it never starts against a half-migrated database. `/health` reports that the API process is up; it does not query PostgreSQL.

`PUBLIC_URL` is wired to the Vendure public domain so generated asset URLs remain valid. A private Railway Bucket stores original assets and generated previews, while Vendure proxies them through `/assets`. Set storefront, SMTP, payment, and tax integrations separately before accepting real orders; the bundled dummy payment handler exists for evaluation only.

When adding a browser storefront on another domain, append its full origin to the comma-separated `ALLOWED_ORIGINS` value. Keeping this list explicit prevents credentialed Admin API requests from accepting every web origin.

## Services and persistence

- Vendure is public on port 3000 and serves `/shop-api`, `/admin-api`, `/dashboard`, `/assets`, and `/health`.
- Vendure Worker is private on port 3020 and processes BullMQ jobs from authenticated Redis.
- PostgreSQL stores catalog, customer, order, job, and search state on a 5 GB volume.
- Redis stores queues and cache data on a 1 GB append-only volume.
- Vendure Assets is a private S3-compatible Railway Bucket shared by the API and worker.

Back up PostgreSQL and the Bucket together. Redis loss can discard queued work and cache state, but PostgreSQL and object storage remain authoritative.

## Local verification

Copy `.env.example` to `.env`, replace every placeholder, then run:

```bash
docker compose up --build -d
SUPERADMIN_USERNAME=admin SUPERADMIN_PASSWORD='<password>' ./scripts/smoke.sh
```

The smoke test checks the Dashboard and storefront API, refuses anonymous Admin API access and GraphQL introspection, authenticates, queues a search reindex and waits for the worker to complete it, uploads and reads back an asset, and checks that an administrator holding only `UpdateApiKey` cannot rotate a SuperAdmin API key. It creates and then deletes one role, administrator, and API key for that check.

`./scripts/local-check.sh` builds the image and runs the whole topology with Podman (or `CONTAINER_ENGINE=docker`) on fresh volumes, then adds stopped-worker queue recovery, a restart of every service, non-root and log-secret checks. `UPGRADE_FROM=<git ref> ./scripts/local-check.sh` first boots that ref's template, stores data, and upgrades the same volumes in place. Review [SUPPORT.md](SUPPORT.md) before production use and [UPGRADE.md](UPGRADE.md) before changing pins. Deployments from 1.x must follow UPGRADE.md to move to 2.0.0: the database migration is one-way.
