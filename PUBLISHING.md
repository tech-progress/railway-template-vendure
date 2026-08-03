# Publishing

The current template release is `v1.0.0`. Both application services build `tech-progress/railway-template-vendure` from `release-v1`; dependency images and the Node base are immutable digest pins.

Publish only after local verification, empty-volume bootstrap, administrator authentication, asset persistence, stopped-worker reindex recovery, initialized restart, and the exact stored Railway graph all pass.

```bash
railway templates publish TEMPLATE_ID \
  --category Other \
  --description "Vendure commerce with Dashboard, Redis workers, and durable assets." \
  --readme-file MARKETPLACE.md \
  --json
```
