# Publishing

Maintenance baseline checked October 2, 2026: Vendure `3.7.3`, Node `22.23.3-bookworm-slim`, and Redis `7.2.16-alpine`. The Node and Redis multi-platform digests were verified with `docker buildx imagetools inspect`; PostgreSQL and object storage pins are unchanged.

The current template release is `v1.0.3`. Both application services build `tech-progress/railway-template-vendure` from `release-v1`; dependency images and the Node base are immutable digest pins.

Publish only after local verification, empty-volume bootstrap, administrator authentication, asset persistence, stopped-worker reindex recovery, initialized restart, and the exact stored Railway graph all pass.

```bash
railway templates publish TEMPLATE_ID \
  --category Other \
  --description "Vendure commerce with Dashboard, Redis workers, and durable assets." \
  --readme-file MARKETPLACE.md \
  --json
```
