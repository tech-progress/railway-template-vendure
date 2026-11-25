#!/usr/bin/env bash
# Builds the template, runs it on an engine-local network that mirrors the Railway graph, and runs
# the HTTP smoke plus queue-recovery, restart, log-secret and non-root checks. With UPGRADE_FROM set to
# a git ref, it first boots that ref's template, stores data, then upgrades the same volumes in place.
set -euo pipefail

engine="${CONTAINER_ENGINE:-podman}"
template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(git -C "${template_root}" rev-parse --show-toplevel)"
template_dir="${template_root#"${repo_root}/"}"
upgrade_from="${UPGRADE_FROM:-}"
id="vc-check-$(date +%s)-$$"
label="vendure-local-check=${id}"
work="$(mktemp -d)"

image_of() { grep -Eo "image: \S*$1\S*" "${template_root}/compose.yaml" | head -1 | cut -d ' ' -f 2; }
postgres_image="$(image_of postgres)"
redis_image="$(image_of redis)"
minio_image="$(image_of minio)"
old_minio_fallback='docker.io/pgsty/minio:RELEASE.2026-02-14T12-00-00Z@sha256:00c404465c4e7c4fd716d98caec2928e9e0f82c3548615662fdd3866ea9a28c0'
node_image="$(grep -m1 -Eo '^FROM \S+' "${template_root}/Dockerfile" | cut -d ' ' -f 2)"
secret() { tr -dc 'A-Za-z0-9' <<<"$(head -c 64 /dev/urandom | base64)"; }
postgres_password="$(secret)"
redis_password="$(secret)"
superadmin_password="$(secret)"
cookie_secret="$(secret)"
minio_password="$(secret)"
port="${VENDURE_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')}"
base_url="http://127.0.0.1:${port}"

remove_flag=(-f)
pull_flag=()
if [[ "${engine}" == podman ]]; then
  remove_flag=(-f -t 0)
  pull_flag=(--pull=missing)
fi

cleanup() {
  local status=$?
  set +e
  if [[ "${status}" -ne 0 ]]; then
    for name in vendure worker postgres redis minio; do
      echo "--- ${name} log tail" >&2
      "${engine}" logs --tail 40 "${id}-${name}" 2>&1 | grep -v -F -e "${postgres_password}" -e "${redis_password}" -e "${superadmin_password}" -e "${cookie_secret}" -e "${minio_password}" >&2
    done
  fi
  mapfile -t containers < <("${engine}" ps -aq --filter "label=${label}")
  ((${#containers[@]})) && "${engine}" rm "${remove_flag[@]}" "${containers[@]}" >/dev/null
  mapfile -t volumes < <("${engine}" volume ls -q --filter "label=${label}")
  ((${#volumes[@]})) && "${engine}" volume rm -f "${volumes[@]}" >/dev/null
  "${engine}" network rm -f "${id}-net" >/dev/null 2>&1
  for tag in new old; do "${engine}" rmi -f "localhost/${id}:${tag}" >/dev/null 2>&1; done
  rm -rf "${work:?}"
  exit "${status}"
}
trap cleanup EXIT

pass() { echo "PASS $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }

build() {
  "${engine}" build "${pull_flag[@]}" --label "${label}" -t "localhost/${id}:$1" "$2" >"${work}/build-$1.log" 2>&1 ||
    { tail -40 "${work}/build-$1.log" >&2; fail "image build $1"; }
}

run() { "${engine}" run -d --label "${label}" --network "${id}-net" "$@" >/dev/null; }

app_env=(
  -e "PUBLIC_URL=${base_url}" -e "ALLOWED_ORIGINS=${base_url}"
  -e "POSTGRES_HOST=${id}-postgres" -e POSTGRES_PORT=5432 -e POSTGRES_DB=vendure -e POSTGRES_USER=vendure
  -e "POSTGRES_PASSWORD=${postgres_password}"
  -e "REDIS_HOST=${id}-redis" -e REDIS_PORT=6379 -e "REDIS_PASSWORD=${redis_password}"
  -e SUPERADMIN_USERNAME=admin -e "SUPERADMIN_PASSWORD=${superadmin_password}" -e "COOKIE_SECRET=${cookie_secret}"
  -e "S3_ENDPOINT=http://${id}-minio:9000" -e S3_REGION=us-east-1 -e S3_BUCKET=vendure-assets
  -e S3_ACCESS_KEY_ID=vendure-local -e "S3_SECRET_ACCESS_KEY=${minio_password}"
)

wait_for() {
  local what="$1"; shift
  for _ in $(seq 1 90); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
  fail "${what} did not become ready"
}
api_ready() { curl -fsS "${base_url}/health" | jq -e '.status == "ok"'; }
worker_ready() { "${engine}" exec "${id}-worker" node -e "fetch('http://127.0.0.1:3020/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; }
postgres_ready() { "${engine}" exec "${id}-postgres" pg_isready -U vendure -d vendure; }
redis_ready() { "${engine}" exec -e "REDISCLI_AUTH=${redis_password}" "${id}-redis" redis-cli ping | grep -q PONG; }

start_data() {
  "${engine}" network create --label "${label}" "${id}-net" >/dev/null
  for volume in postgres redis minio; do "${engine}" volume create --label "${label}" "${id}-${volume}" >/dev/null; done
  run --name "${id}-keeper" --entrypoint sleep "${node_image}" infinity
  run --name "${id}-postgres" -v "${id}-postgres:/var/lib/postgresql/data" -e PGDATA=/var/lib/postgresql/data/pgdata \
    -e POSTGRES_DB=vendure -e POSTGRES_USER=vendure -e "POSTGRES_PASSWORD=${postgres_password}" "${postgres_image}"
  run --name "${id}-redis" -v "${id}-redis:/data" -e "REDIS_PASSWORD=${redis_password}" "${redis_image}" \
    sh -c 'exec redis-server --appendonly yes --requirepass "$REDIS_PASSWORD"'
  start_minio "$1"
  wait_for PostgreSQL postgres_ready
  wait_for Redis redis_ready
}

start_minio() {
  run --name "${id}-minio" -v "${id}-minio:/data" -e MINIO_ROOT_USER=vendure-local -e "MINIO_ROOT_PASSWORD=${minio_password}" \
    "$1" server /data
}

start_app() {
  local image="localhost/${id}:$1"
  run --name "${id}-vendure" -p "127.0.0.1:${port}:3000" -e PORT=3000 "${app_env[@]}" "${image}"
  wait_for "Vendure API ($1)" api_ready
  run --name "${id}-worker" -e PORT=3020 -e WORKER_HEALTH_PORT=3020 -e WORKER_CONCURRENCY=3 \
    -e "API_HEALTH_URL=http://${id}-vendure:3000/health" "${app_env[@]}" "${image}" node dist/index-worker.js
  wait_for "Vendure worker ($1)" worker_ready
}

stop_app() { "${engine}" rm "${remove_flag[@]}" "${id}-worker" "${id}-vendure" >/dev/null; }

smoke() { BASE_URL="${base_url}" SUPERADMIN_USERNAME=admin SUPERADMIN_PASSWORD="${superadmin_password}" "${template_root}/scripts/smoke.sh" "$@"; }

admin() { curl -fsS -H 'content-type: application/json' -H "authorization: Bearer $1" --data-binary @- "${base_url}/admin-api"; }

job_state() {
  jq -n --arg id "$2" '{query:"query($id:ID!){job(jobId:$id){state}}",variables:{id:$id}}' | admin "$1" | jq -er '.data.job.state'
}

if [[ -n "${upgrade_from}" ]]; then
  mkdir -p "${work}/old"
  git -C "${repo_root}" archive "${upgrade_from}" "${template_dir}" | tar -x -C "${work}/old"
  sed -i -E 's#^FROM (node:)#FROM docker.io/library/\1#' "${work}/old/${template_dir}/Dockerfile"
  old_core="$(jq -r '.dependencies["@vendure/core"]' "${work}/old/${template_dir}/package.json")"
  old_minio_image="$(grep -Eo 'image: \S*minio\S*' "${work}/old/${template_dir}/compose.yaml" | head -1 | cut -d ' ' -f 2)"
  if ! "${engine}" pull "${old_minio_image}" >/dev/null 2>&1; then
    echo "NOTE ${old_minio_image} can no longer be pulled; writing the pre-upgrade assets with ${old_minio_fallback}"
    old_minio_image="${old_minio_fallback}"
  fi
  build old "${work}/old/${template_dir}"
  pass "built ${upgrade_from} template image (Vendure ${old_core})"
fi
build new "${template_root}"
new_core="$(jq -r '.dependencies["@vendure/core"]' "${template_root}/package.json")"
pass "built working-tree image (Vendure ${new_core})"

if [[ -n "${upgrade_from}" ]]; then
  start_data "${old_minio_image}"
  start_app old
  if SMOKE_TOKEN_FILE="${work}/old-token" SMOKE_ASSET_URL_FILE="${work}/old-asset" smoke >"${work}/old-smoke.log" 2>&1; then
    fail "smoke passed on Vendure ${old_core}; the GHSA-37xp-mjp8-6f9x probe should have refused it"
  fi
  grep -q 'SECURITY: rotateApiKey let an UpdateApiKey-only administrator' "${work}/old-smoke.log" ||
    { cat "${work}/old-smoke.log" >&2; fail "old smoke failed for a reason other than GHSA-37xp-mjp8-6f9x"; }
  pass "GHSA-37xp-mjp8-6f9x probe fails on Vendure ${old_core} (UpdateApiKey-only admin rotated a SuperAdmin key)"
  old_token="$(<"${work}/old-token")"
  slug="upgrade-probe-${id}"
  jq -n --arg slug "${slug}" '{query:"mutation($slug:String!){createProduct(input:{translations:[{languageCode:en,name:\"Upgrade probe\",slug:$slug,description:\"Created before the upgrade\"}]}){id}}",variables:{slug:$slug}}' |
    admin "${old_token}" | jq -e '.data.createProduct.id != null' >/dev/null
  pass "stored a product, an asset and an admin session on Vendure ${old_core}"
  stop_app
  "${engine}" rm "${remove_flag[@]}" "${id}-minio" >/dev/null
  start_minio "${minio_image}"
  start_app new
  vendure_log="$("${engine}" logs "${id}-vendure" 2>&1)"
  grep -q 'V38Upgrade1795585577070' <<<"${vendure_log}" || fail "the v3.8 upgrade migration did not run"
  grep -q 'Rescaled PROMOTION adjustments on 0' <<<"${vendure_log}" || fail "the order line promotion rescale did not run"
  pass "upgrade migration V38Upgrade1795585577070 ran on the ${old_core} database, including the promotion rescale"
  echo '{"query":"query { me { id } }"}' | admin "${old_token}" | jq -e '(.data.me // null) == null' >/dev/null ||
    fail "an Admin API session created before the upgrade was still accepted"
  pass "pre-upgrade admin session refused after upgrade (administrators log in again once)"
  jq -n --arg slug "${slug}" '{query:"query($slug:String!){product(slug:$slug){name description}}",variables:{slug:$slug}}' |
    curl -fsS -H 'content-type: application/json' --data-binary @- "${base_url}/shop-api" |
    jq -e '.data.product.name == "Upgrade probe"' >/dev/null || fail "pre-upgrade product is missing after the upgrade"
  curl -fsS "$(<"${work}/old-asset")" >/dev/null || fail "pre-upgrade asset is unreadable after the upgrade"
  pass "pre-upgrade product and S3 asset readable after the upgrade and the switch to ${minio_image%%@*}"
else
  start_data "${minio_image}"
  start_app new
fi

SMOKE_TOKEN_FILE="${work}/token" SMOKE_ASSET_URL_FILE="${work}/asset" smoke
pass "smoke on Vendure ${new_core}, including the GHSA-37xp-mjp8-6f9x probe"
token="$(<"${work}/token")"

"${engine}" stop -t 10 "${id}-worker" >/dev/null
job_id="$(echo '{"query":"mutation { reindex { id } }"}' | admin "${token}" | jq -er '.data.reindex.id')"
sleep 8
[[ "$(job_state "${token}" "${job_id}")" == PENDING ]] || fail "reindex did not wait in the queue while the worker was stopped"
"${engine}" start "${id}-worker" >/dev/null
state=""
for _ in $(seq 1 60); do
  state="$(job_state "${token}" "${job_id}")"
  [[ "${state}" == COMPLETED ]] && break
  sleep 2
done
[[ "${state}" == COMPLETED ]] || fail "queued reindex did not complete after the worker returned (state ${state})"
pass "reindex queued while the worker was stopped completed after it returned"

for name in postgres redis minio; do "${engine}" restart -t 10 "${id}-${name}" >/dev/null; done
wait_for PostgreSQL postgres_ready
wait_for Redis redis_ready
for name in vendure worker; do "${engine}" restart -t 10 "${id}-${name}" >/dev/null; done
wait_for "Vendure API after restart" api_ready
wait_for "Vendure worker after restart" worker_ready
curl -fsS "$(<"${work}/asset")" >/dev/null || fail "asset unreadable after restart"
smoke >/dev/null
pass "restart of every service kept data, assets and the queue working"

for name in vendure worker; do
  [[ "$("${engine}" exec "${id}-${name}" id -u)" != 0 ]] || fail "${name} runs as root"
done
pass "API and worker run as a non-root user"

for name in vendure worker postgres redis minio; do
  log="$("${engine}" logs "${id}-${name}" 2>&1)" || fail "could not read the ${name} log"
  (( $(wc -l <<<"${log}") >= 3 )) || fail "${name} log is unexpectedly short"
  if grep -q -F -e "${postgres_password}" -e "${redis_password}" -e "${superadmin_password}" -e "${cookie_secret}" -e "${minio_password}" <<<"${log}"; then
    fail "${name} log contains a generated secret"
  fi
done
pass "no generated secret in any container log"
