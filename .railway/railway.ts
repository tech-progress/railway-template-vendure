import { bucket, defineRailway, github, group, project, ref, service, volume } from "railway/iac";

const SOURCE = github("tech-progress/railway-template-vendure", {
  branch: "release-v1",
  rootDirectory: "/",
});
const POSTGRES_IMAGE = "postgres:17-alpine@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193";
const REDIS_IMAGE = "redis:7.2.4-alpine@sha256:c8bb255c3559b3e458766db810aa7b3c7af1235b204cfdb304e79ff388fe1a5a";

export default defineRailway(() => {
  const databaseData = volume("Vendure PostgreSQL Data", { sizeMB: 5_000 });
  const redisData = volume("Vendure Redis Data", { sizeMB: 1_000 });
  const assets = bucket("Vendure Assets", { region: "iad" });

  const postgres = service("Vendure PostgreSQL", {
    source: { image: POSTGRES_IMAGE },
    volumeMounts: { "/var/lib/postgresql/data": databaseData },
    env: {
      PGDATA: "/var/lib/postgresql/data/pgdata",
      POSTGRES_DB: "vendure",
      POSTGRES_USER: "vendure",
      POSTGRES_PASSWORD: "${{secret(48)}}",
    },
  });

  const redis = service("Vendure Redis", {
    source: { image: REDIS_IMAGE },
    start: 'sh -c \'exec redis-server --appendonly yes --requirepass "$REDIS_PASSWORD"\'',
    volumeMounts: { "/data": redisData },
    env: { REDIS_PASSWORD: "${{secret(48)}}" },
  });

  const sharedEnvironment = {
    POSTGRES_HOST: "${{Vendure PostgreSQL.RAILWAY_PRIVATE_DOMAIN}}",
    POSTGRES_PORT: "5432",
    POSTGRES_DB: "${{Vendure PostgreSQL.POSTGRES_DB}}",
    POSTGRES_USER: "${{Vendure PostgreSQL.POSTGRES_USER}}",
    POSTGRES_PASSWORD: "${{Vendure PostgreSQL.POSTGRES_PASSWORD}}",
    REDIS_HOST: "${{Vendure Redis.RAILWAY_PRIVATE_DOMAIN}}",
    REDIS_PORT: "6379",
    REDIS_PASSWORD: "${{Vendure Redis.REDIS_PASSWORD}}",
    SUPERADMIN_USERNAME: "admin",
    SUPERADMIN_PASSWORD: "${{secret(32)}}",
    COOKIE_SECRET: "${{secret(64)}}",
    S3_ENDPOINT: ref(assets, "ENDPOINT"),
    S3_REGION: ref(assets, "REGION"),
    S3_BUCKET: ref(assets, "BUCKET"),
    S3_ACCESS_KEY_ID: ref(assets, "ACCESS_KEY_ID"),
    S3_SECRET_ACCESS_KEY: ref(assets, "SECRET_ACCESS_KEY"),
  };

  const api = service("Vendure", {
    source: SOURCE,
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    healthcheck: "/health",
    healthcheckTimeout: 300,
    env: {
      ...sharedEnvironment,
      PORT: "3000",
      PUBLIC_URL: "https://${{Vendure.RAILWAY_PUBLIC_DOMAIN}}",
      ALLOWED_ORIGINS: "https://${{Vendure.RAILWAY_PUBLIC_DOMAIN}}",
    },
  });

  const worker = service("Vendure Worker", {
    source: SOURCE,
    build: { builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    start: "node dist/index-worker.js",
    healthcheck: "/health",
    healthcheckTimeout: 300,
    env: {
      ...sharedEnvironment,
      SUPERADMIN_PASSWORD: "${{Vendure.SUPERADMIN_PASSWORD}}",
      COOKIE_SECRET: "${{Vendure.COOKIE_SECRET}}",
      WORKER_HEALTH_PORT: "3020",
      WORKER_CONCURRENCY: "3",
    },
  });

  return project("Vendure commerce", {
    resources: [
      group("Application", [api, worker]),
      group("Data", [postgres, databaseData, redis, redisData, assets]),
    ],
  });
});
