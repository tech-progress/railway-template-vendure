# Publishing

Maintenance baseline checked November 25, 2026: Vendure `3.8.2`, Node `22.23.5-bookworm-slim`, PostgreSQL `17.12-alpine`, and Redis `7.2.17-alpine`. The image index digests were read from Docker Hub's registry API (`Docker-Content-Digest` of the multi-platform index); object storage is unchanged.

The current template release is `v2.0.0`. Both application services build `tech-progress/railway-template-vendure` from `release-v2`; dependency images and the Node base are immutable digest pins.

Release channels: `release-v2` carries 2.0.x and is the listing's stored branch for both application services; `release-v1` stays at `v1.0.3` (Vendure 3.7.3) for existing 1.x deployments until their operators follow `UPGRADE.md`. A 2.0.x release syncs the sanitized tree to `tech-progress/railway-template-vendure`, deploys the stored graph on `release-v2` through `templateDeployV2`, tags `v2.0.x`, fast-forwards `release-v2`, reruns `scripts/sync-template-marketplace.sh vendure-commerce`, and requires `scripts/audit-template-marketplace.sh vendure-commerce` to pass.

Publish only after local verification, empty-volume bootstrap, administrator authentication, asset persistence, stopped-worker reindex recovery, initialized restart, and the exact stored Railway graph all pass.

```bash
railway templates publish TEMPLATE_ID \
  --category Other \
  --description "Vendure commerce with Dashboard, Redis workers, and durable assets." \
  --readme-file MARKETPLACE.md \
  --json
```
