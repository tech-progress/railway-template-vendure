#!/usr/bin/env bash
set -euo pipefail

template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
required=(
  .dockerignore .env.example .gitignore .railway/package.json .railway/railway.ts CHANGELOG.md
  Dockerfile LICENSE LICENSE_REVIEW.md MARKETPLACE.md PUBLISHING.md README.md SUPPORT.md
  UPGRADE.md VERSION compose.yaml package.json package-lock.json tsconfig.json
  tsconfig.dashboard.json vite.config.mts
  src/index.ts src/index-worker.ts src/vendure-config.ts scripts/smoke.sh
  scripts/fixtures/smoke.svg
)

for file in "${required[@]}"; do
  test -f "${template_root}/${file}" || { echo "Missing ${file}" >&2; exit 1; }
done

version="$(<"${template_root}/VERSION")"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
grep -Fq "## [${version}] - 2026-08-03" "${template_root}/CHANGELOG.md"
for file in README.md PUBLISHING.md; do
  grep -Fq "current template release is \`v${version}\`" "${template_root}/${file}"
done

description="$(grep -E '^  --description "' "${template_root}/PUBLISHING.md" | cut -d '"' -f 2)"
[[ ${#description} -ge 45 && ${#description} -le 75 ]]

POSTGRES_PASSWORD=verify-postgres SUPERADMIN_PASSWORD=verify-admin COOKIE_SECRET=verify-cookie REDIS_PASSWORD=verify-redis docker compose -f "${template_root}/compose.yaml" config --quiet
bash -n "${template_root}/scripts/smoke.sh"

graph="$(cd "${template_root}" && ./node_modules/.bin/railway-iac-ts .railway/railway.ts)"
jq -e '
  .graph.resources |
  ([.[] | select(.type=="service") | .name] | sort) == ["Vendure","Vendure PostgreSQL","Vendure Redis","Vendure Worker"] and
  ([.[] | select(.type=="volume")] | length) == 2 and
  ([.[] | select(.type=="bucket" and .name=="Vendure Assets")] | length) == 1 and
  ([.[] | select(.name=="Vendure")][0].source.repo == "tech-progress/railway-template-vendure") and
  ([.[] | select(.name=="Vendure")][0].source.branch == "release-v1") and
  ([.[] | select(.name=="Vendure")][0].deploy.healthcheckPath == "/health") and
  ([.[] | select(.name=="Vendure Worker")][0].deploy.healthcheckPath == "/health") and
  ([.[] | select(.name=="Vendure Worker")][0].variables.PORT.value == "3020")
' <<<"${graph}" >/dev/null

grep -Fq 'https://www.vendure.io' "${template_root}/README.md"
grep -Rqs '@sha256:' "${template_root}/Dockerfile" "${template_root}/compose.yaml" "${template_root}/.railway/railway.ts"
if find "${template_root}" -type f \( -name .env -o -name '*.local' \) -print -quit | grep -q .; then
  echo "Local secret file found." >&2
  exit 1
fi

echo "Vendure template structure, graph, variables, and pins are valid."
