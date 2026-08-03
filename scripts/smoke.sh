#!/usr/bin/env bash
set -euo pipefail

base_url="${BASE_URL:-http://localhost:3000}"
username="${SUPERADMIN_USERNAME:-admin}"
: "${SUPERADMIN_PASSWORD:?set SUPERADMIN_PASSWORD}"

curl --fail --silent --show-error "${base_url}/health" | jq -e '.status == "ok"' >/dev/null
curl --fail --silent --show-error "${base_url}/dashboard/" >/dev/null
curl --fail --silent --show-error \
  -H 'content-type: application/json' \
  --data '{"query":"query { products { totalItems } }"}' \
  "${base_url}/shop-api" | jq -e '.data.products.totalItems >= 0' >/dev/null

login_headers="$(mktemp)"
login_body="$(mktemp)"
cleanup() { rm -f "${login_headers}" "${login_body}"; }
trap cleanup EXIT

jq -n --arg username "${username}" --arg password "${SUPERADMIN_PASSWORD}" \
  '{query:"mutation Login($username:String!,$password:String!){login(username:$username,password:$password,rememberMe:false){... on CurrentUser{id identifier}}}",variables:{username:$username,password:$password}}' |
  curl --fail --silent --show-error -D "${login_headers}" -o "${login_body}" \
    -H 'content-type: application/json' --data-binary @- "${base_url}/admin-api"
jq -e '.data.login.id != null' "${login_body}" >/dev/null
token="$(awk 'BEGIN{IGNORECASE=1} /^vendure-auth-token:/ {gsub("\r", "", $2); print $2}' "${login_headers}")"
[[ -n "${token}" ]]

job_id="$(curl --fail --silent --show-error \
  -H 'content-type: application/json' -H "authorization: Bearer ${token}" \
  --data '{"query":"mutation { reindex { id state } }"}' "${base_url}/admin-api" |
  jq -er '.data.reindex.id')"

for _ in $(seq 1 60); do
  state="$(jq -n --arg id "${job_id}" '{query:"query Job($id:ID!){job(jobId:$id){state}}",variables:{id:$id}}' |
    curl --fail --silent --show-error -H 'content-type: application/json' \
      -H "authorization: Bearer ${token}" --data-binary @- "${base_url}/admin-api" |
    jq -er '.data.job.state')"
  [[ "${state}" == COMPLETED ]] && break
  [[ "${state}" == FAILED ]] && { echo "Reindex job failed." >&2; exit 1; }
  sleep 2
done
[[ "${state}" == COMPLETED ]]

fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/smoke.svg"
asset_url="$(curl --fail --silent --show-error \
  -H "authorization: Bearer ${token}" \
  -F 'operations={"query":"mutation CreateAsset($file: Upload!) { createAssets(input: [{file: $file}]) { ... on Asset { source } ... on ErrorResult { errorCode message } } }","variables":{"file":null}}' \
  -F 'map={"0":["variables.file"]}' \
  -F "0=@${fixture};type=image/svg+xml" \
  "${base_url}/admin-api" | jq -er '.data.createAssets[0].source')"
curl --fail --silent --show-error "${asset_url}" >/dev/null

echo "Vendure health, Dashboard, authentication, S3 asset, shop query, and worker reindex passed."
