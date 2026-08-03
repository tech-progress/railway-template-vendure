# Upgrades

Back up PostgreSQL and the Railway Bucket together before changing pins. Vendure database changes must be represented by a generated migration; do not enable TypeORM `synchronize` in production.

Test API login, Dashboard loading, asset readback, search reindexing, and a stopped-worker queue recovery on a disposable deployment before promoting an upgrade.
