import { bootstrapWorker } from '@vendure/core';
import { config } from './vendure-config';

async function waitForApi(): Promise<void> {
  const healthUrl = process.env.API_HEALTH_URL;
  if (!healthUrl) return;
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await fetch(healthUrl);
      if (response.ok) return;
    } catch {
      // The API may still be building or applying migrations.
    }
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
  throw new Error(`Timed out waiting for Vendure API health at ${healthUrl}`);
}

waitForApi()
  .then(() => bootstrapWorker(config))
  .then(async worker => {
    await worker.startJobQueue();
    await worker.startHealthCheckServer({
      port: Number(process.env.WORKER_HEALTH_PORT ?? 3020),
      hostname: '0.0.0.0',
    });
  })
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
