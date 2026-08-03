# Deploy and Host Vendure commerce on Railway

Vendure is a headless commerce platform with Shop and Admin GraphQL APIs, a modern operator Dashboard, extensible catalog and order models, and asynchronous workers.

## About Hosting Vendure commerce

This template runs Vendure 3.7.2 with a public API and compiled Dashboard, a private BullMQ worker, PostgreSQL, authenticated Redis, and a private Railway Bucket for original assets and previews.

## Why Deploy Vendure commerce on Railway

Railway supplies HTTPS, generated secrets, private networking, health-gated deployments, managed service wiring, durable volumes, and S3-compatible storage. The template adds reviewed migrations, shared Redis caching, queue recovery, hardened GraphQL defaults, and explicit browser origins.

## Common Use Cases

- Build a custom storefront on Vendure's Shop API.
- Run a durable catalog, customer, promotion, and order backend for a small team.
- Evaluate Vendure's plugin model with a production-shaped worker and storage topology.

## Dependencies for Vendure commerce Hosting

The deployment uses Vendure, PostgreSQL, Redis, and a Railway Bucket.

### Deployment Dependencies

- One public Railway domain for the API and Dashboard
- One 5 GB PostgreSQL volume and one 1 GB Redis volume
- One private Railway Bucket for assets
- Generated administrator, cookie, database, and Redis secrets

Railway generates the administrator, cookie, database, and Redis secrets. Open `/dashboard` on the Vendure domain and sign in with `SUPERADMIN_USERNAME` and `SUPERADMIN_PASSWORD`.

Upstream project: [Vendure](https://www.vendure.io).
