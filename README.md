# Vendure commerce Railway template

The current template release is `v1.0.0`. It deploys Vendure `3.7.2` with the Admin Dashboard, a detached BullMQ worker, PostgreSQL 17, authenticated Redis 7.2, and durable object storage. Runtime images are pinned by digest.

Upstream project: [Vendure](https://www.vendure.io).

## Deploy on Railway

Railway generates `SUPERADMIN_PASSWORD`, `COOKIE_SECRET`, `POSTGRES_PASSWORD`, and `REDIS_PASSWORD`; the default administrator identifier is `admin`. After deployment, open `https://<vendure-domain>/dashboard` and use those values. The server runs committed migrations before accepting traffic, and the worker waits for the server's database-aware health endpoint.

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

The smoke test authenticates through the Admin API, queues a search reindex, checks the Dashboard and storefront API, and verifies worker completion. Review [SUPPORT.md](SUPPORT.md) before production use and [UPGRADE.md](UPGRADE.md) before changing pins.
