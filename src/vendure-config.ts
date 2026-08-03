import {
  AssetServerPlugin,
  configureS3AssetStorage,
  PresetOnlyStrategy,
} from '@vendure/asset-server-plugin';
import {
  DefaultSchedulerPlugin,
  DefaultSessionCacheStrategy,
  DefaultSearchPlugin,
  dummyPaymentHandler,
  RedisCachePlugin,
  TypeORMHealthCheckStrategy,
  VendureConfig,
} from '@vendure/core';
import { DashboardPlugin } from '@vendure/dashboard/plugin';
import { HardenPlugin } from '@vendure/harden-plugin';
import { BullMQJobQueuePlugin } from '@vendure/job-queue-plugin/package/bullmq';
import 'dotenv/config';
import path from 'node:path';

const isBuild = process.env.VENDURE_BUILD === 'true';
const env = (name: string, fallback?: string): string => {
  const value = process.env[name] ?? fallback;
  if (isBuild) return value ?? `build-only-${name.toLowerCase()}`;
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
};

const port = Number(process.env.PORT ?? 3000);
const redisPort = Number(process.env.REDIS_PORT ?? 6379);
const publicUrl = (process.env.PUBLIC_URL ?? `http://localhost:${port}`).replace(/\/$/, '');
class SharedSessionCacheStrategy extends DefaultSessionCacheStrategy {}

export const config: VendureConfig = {
  apiOptions: {
    port,
    adminApiPath: 'admin-api',
    shopApiPath: 'shop-api',
    trustProxy: 1,
    cors: {
      origin: (process.env.ALLOWED_ORIGINS ?? publicUrl).split(',').map(value => value.trim()),
      credentials: true,
    },
  },
  authOptions: {
    tokenMethod: ['bearer', 'cookie'],
    superadminCredentials: {
      identifier: env('SUPERADMIN_USERNAME', 'admin'),
      password: env('SUPERADMIN_PASSWORD'),
    },
    cookieOptions: { secret: env('COOKIE_SECRET') },
    sessionCacheStrategy: new SharedSessionCacheStrategy(),
  },
  dbConnectionOptions: {
    type: 'postgres',
    host: env('POSTGRES_HOST'),
    port: Number(process.env.POSTGRES_PORT ?? 5432),
    username: env('POSTGRES_USER', 'vendure'),
    password: env('POSTGRES_PASSWORD'),
    database: env('POSTGRES_DB', 'vendure'),
    synchronize: false,
    migrations: [path.join(__dirname, './migrations/*.+(js|ts)')],
    logging: false,
  },
  paymentOptions: { paymentMethodHandlers: [dummyPaymentHandler] },
  systemOptions: {
    healthChecks: [new TypeORMHealthCheckStrategy({ key: 'postgres', timeout: 5000 })],
  },
  plugins: [
    AssetServerPlugin.init({
      route: 'assets',
      assetUploadDir: '/tmp/vendure-assets',
      assetUrlPrefix: `${publicUrl}/assets/`,
      storageStrategyFactory: configureS3AssetStorage({
        bucket: env('S3_BUCKET'),
        credentials: {
          accessKeyId: env('S3_ACCESS_KEY_ID'),
          secretAccessKey: env('S3_SECRET_ACCESS_KEY'),
        },
        nativeS3Configuration: {
          endpoint: env('S3_ENDPOINT'),
          region: env('S3_REGION', 'auto'),
          forcePathStyle: true,
        },
      }),
      imageTransformStrategy: new PresetOnlyStrategy({ defaultPreset: 'medium' }),
    }),
    DefaultSchedulerPlugin.init(),
    BullMQJobQueuePlugin.init({
      connection: {
        host: env('REDIS_HOST'),
        port: redisPort,
        password: env('REDIS_PASSWORD'),
        maxRetriesPerRequest: null,
      },
      queueOptions: { prefix: 'vendure-queue' },
      workerOptions: { prefix: 'vendure-queue' },
      concurrency: Number(process.env.WORKER_CONCURRENCY ?? 3),
    }),
    RedisCachePlugin.init({
      namespace: 'vendure-cache',
      redisOptions: {
        host: env('REDIS_HOST'),
        port: redisPort,
        password: env('REDIS_PASSWORD'),
      },
    }),
    DefaultSearchPlugin.init({ bufferUpdates: false, indexStockStatus: true }),
    DashboardPlugin.init({ route: 'dashboard', appDir: path.join(__dirname, 'dashboard') }),
    HardenPlugin.init({ apiMode: 'prod', maxQueryComplexity: 1000 }),
  ],
};
