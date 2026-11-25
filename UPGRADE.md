# Upgrades

Back up PostgreSQL and the Railway Bucket together before changing pins. Vendure database changes must be represented by a generated migration; do not enable TypeORM `synchronize` in production.

Test API login, Dashboard loading, asset readback, search reindexing, and a stopped-worker queue recovery on a disposable deployment before promoting an upgrade. `UPGRADE_FROM=<git ref> ./scripts/local-check.sh` runs that sequence locally against a database created by the older template.

## 1.x to 2.0.0 (Vendure 3.7.3 to 3.8.2)

2.0.0 fixes GHSA-37xp-mjp8-6f9x and the other advisories fixed in Vendure 3.7.4 to 3.8.2. No variables, services, volumes, or ports change, but the upgrade is one-way, so 2.0.0 is published on a new `release-v2` channel and 1.x deployments stay on `release-v1` until their operator moves them. Vendure's own notes are in the [3.8.0 migration guide](https://github.com/vendurehq/vendure/releases/tag/v3.8.0).

The API applies `V38Upgrade1795585577070` once, on its first 3.8.2 boot, before it starts listening. Reverting that migration does not give the old data back:

- Every translation table gets a unique `(languageCode, baseId)` constraint. If a table holds duplicate translations of one entity in one language, the migration keeps the most recently updated row and deletes the others. A revert drops the constraint; the deleted rows stay deleted.
- `rescaleOrderLinePromotionAdjustments` rewrites the stored promotion adjustments of order lines that were partially cancelled before 3.8. It is not idempotent: running the migration again after a revert rescales the same lines a second time. Run this query first to see which lines it would consider:

  ```sql
  SELECT ol.id, ol."orderId", ol.quantity, ol."orderPlacedQuantity"
  FROM order_line ol
  WHERE ol.quantity > 0
    AND ol.quantity < ol."orderPlacedQuantity"
    AND ol.adjustments LIKE '%"type":"PROMOTION"%';
  ```

Upgrade in this order:

1. Stop the Vendure Worker, then the Vendure API, so no 1.x process writes from here on. Railway otherwise keeps the old deployments running until the new ones are healthy. A partial cancellation made by a 3.7.3 process after the migration would never be rescaled, and the old API's `/health` would let a new worker start before the migration has run.
2. With both stopped, take the final PostgreSQL backup and the Bucket backup, and test that they restore. A backup taken while 1.x was still running would miss the orders accepted after it.
3. Change the API's source branch to `release-v2` and deploy it alone. Wait until its deployment is healthy; its log shows `V38Upgrade1795585577070` and the rescale count.
4. Once the API is healthy, change the worker's source branch to `release-v2` and deploy it.

The only way back to 1.x is restoring the backup from step 2: stop both 2.0.0 services, restore that PostgreSQL and Bucket backup, and deploy both services from `release-v1` again. Anything written after step 3 is lost.

If an order modification and a cancellation on one order share a timestamp, the rescale stops the migration before writing anything and names the order lines. The API then never becomes healthy. Resolve those lines as the [helper's reference](https://docs.vendure.io/current/core/reference/typescript-api/migration/rescale-order-line-promotion-adjustments) describes, in a fork of this template.

After the upgrade:

- Every administrator has to sign in again once. Admin API sessions created before 3.8 are refused; API keys keep working.
- Checkout recalculates the order when it moves to `ArrangingPayment` and refuses the transition if the selected shipping method is no longer eligible. Storefronts should handle that `OrderStateTransitionError` and re-read order totals after the transition.

### Local Compose

The local stack keeps its `minio` service, `minio-data` volume, and `MINIO_ROOT_PASSWORD`. Only the image changes, from `quay.io/minio/minio` (no longer pullable) to the maintained `pgsty/minio` fork, which reads the same volume. `UPGRADE_FROM=origin/main ./scripts/local-check.sh` checks that an asset written before the switch is still served after it.
