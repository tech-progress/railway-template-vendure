import { bootstrapWorker } from '@vendure/core';
import { config } from './vendure-config';

bootstrapWorker(config)
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
