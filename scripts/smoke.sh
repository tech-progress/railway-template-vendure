#!/usr/bin/env bash
set -euo pipefail

base_url="${BASE_URL:-http://localhost:3000}"
username="${SUPERADMIN_USERNAME:-admin}"
: "${SUPERADMIN_PASSWORD:?set SUPERADMIN_PASSWORD}"

work="$(mktemp -d)"
probe_key_id=""
probe_admin_id=""
probe_role_id=""
token=""

gql() {
  local api="$1" auth="$2"
  if [[ -n "${auth}" ]]; then
    curl --fail --silent --show-error -H 'content-type: application/json' \
      -H "authorization: Bearer ${auth}" --data-binary @- "${base_url}/${api}"
  else
    curl --fail --silent --show-error -H 'content-type: application/json' \
      --data-binary @- "${base_url}/${api}"
  fi
}

cleanup() {
  if [[ -n "${token}" ]]; then
    if [[ -n "${probe_key_id}" ]]; then
      jq -n --arg id "${probe_key_id}" '{query:"mutation($id:ID!){deleteApiKeys(ids:[$id]){result}}",variables:{id:$id}}' |
        gql admin-api "${token}" >/dev/null || true
    fi
    if [[ -n "${probe_admin_id}" ]]; then
      jq -n --arg id "${probe_admin_id}" '{query:"mutation($id:ID!){deleteAdministrator(id:$id){result}}",variables:{id:$id}}' |
        gql admin-api "${token}" >/dev/null || true
    fi
    if [[ -n "${probe_role_id}" ]]; then
      jq -n --arg id "${probe_role_id}" '{query:"mutation($id:ID!){deleteRole(id:$id){result}}",variables:{id:$id}}' |
        gql admin-api "${token}" >/dev/null || true
    fi
  fi
  rm -rf "${work:?}"
}
trap cleanup EXIT

login() {
  jq -n --arg username "$1" --arg password "$2" \
    '{query:"mutation Login($username:String!,$password:String!){login(username:$username,password:$password,rememberMe:false){... on CurrentUser{id identifier}}}",variables:{username:$username,password:$password}}' |
    curl --fail --silent --show-error -D "${work}/login-headers" -o "${work}/login-body" \
      -H 'content-type: application/json' --data-binary @- "${base_url}/admin-api"
  jq -e '.data.login.id != null' "${work}/login-body" >/dev/null
  awk 'BEGIN{IGNORECASE=1} /^vendure-auth-token:/ {gsub("\r", "", $2); print $2}' "${work}/login-headers"
}

curl --fail --silent --show-error "${base_url}/health" | jq -e '.status == "ok"' >/dev/null
curl --fail --silent --show-error "${base_url}/dashboard/" >/dev/null
echo '{"query":"query { products { totalItems } }"}' | gql shop-api "" | jq -e '.data.products.totalItems >= 0' >/dev/null

for api in admin-api shop-api; do
  curl --silent --show-error -H 'content-type: application/json' \
    --data '{"query":"query { __schema { queryType { name } } }"}' "${base_url}/${api}" |
    jq -e '(.data.__schema // null) == null and (.errors | length) > 0' >/dev/null ||
    { echo "GraphQL introspection is enabled on /${api}." >&2; exit 1; }
  ide="$(curl --silent -H 'accept: text/html' "${base_url}/${api}" || true)"
  if grep -qi -e graphiql -e playground <<<"${ide}"; then
    echo "A GraphQL IDE is served on /${api}." >&2
    exit 1
  fi
done
echo '{"query":"query { administrators { totalItems } }"}' | gql admin-api "" |
  jq -e '.data == null and .errors[0].extensions.code == "FORBIDDEN"' >/dev/null ||
  { echo "The Admin API answered an anonymous administrator query." >&2; exit 1; }

token="$(login "${username}" "${SUPERADMIN_PASSWORD}")"
[[ -n "${token}" ]]
[[ -n "${SMOKE_TOKEN_FILE:-}" ]] && printf '%s\n' "${token}" >"${SMOKE_TOKEN_FILE}"

job_id="$(echo '{"query":"mutation { reindex { id state } }"}' | gql admin-api "${token}" | jq -er '.data.reindex.id')"
state=""
for _ in $(seq 1 60); do
  state="$(jq -n --arg id "${job_id}" '{query:"query Job($id:ID!){job(jobId:$id){state}}",variables:{id:$id}}' |
    gql admin-api "${token}" | jq -er '.data.job.state')"
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
[[ -n "${SMOKE_ASSET_URL_FILE:-}" ]] && printf '%s\n' "${asset_url}" >"${SMOKE_ASSET_URL_FILE}"

# GHSA-37xp-mjp8-6f9x: an administrator holding only UpdateApiKey must not be able to rotate a
# SuperAdmin API key and receive its new secret. The probe key, role and administrator are deleted on exit.
suffix="$(date +%s)-${RANDOM}"
probe_password="$(tr -dc 'A-Za-z0-9' <<<"$(head -c 48 /dev/urandom | base64)")"
super_role_id="$(echo '{"query":"query { roles(options:{filter:{code:{eq:\"__super_admin_role__\"}}}) { items { id } } }"}' |
  gql admin-api "${token}" | jq -er '.data.roles.items[0].id')"
probe_key_id="$(jq -n --arg role "${super_role_id}" --arg name "smoke-probe-${suffix}" \
  '{query:"mutation($role:ID!,$name:String!){createApiKey(input:{roleIds:[$role],translations:[{languageCode:en,name:$name}]}){entityId}}",variables:{role:$role,name:$name}}' |
  gql admin-api "${token}" | jq -er '.data.createApiKey.entityId')"
probe_role_id="$(jq -n --arg code "smoke-apikey-${suffix}" \
  '{query:"mutation($code:String!){createRole(input:{code:$code,description:\"Smoke probe: API key update only\",permissions:[ReadApiKey,UpdateApiKey]}){id}}",variables:{code:$code}}' |
  gql admin-api "${token}" | jq -er '.data.createRole.id')"
probe_email="smoke-${suffix}@example.invalid"
probe_admin_id="$(jq -n --arg role "${probe_role_id}" --arg email "${probe_email}" --arg password "${probe_password}" \
  '{query:"mutation($role:ID!,$email:String!,$password:String!){createAdministrator(input:{firstName:\"Smoke\",lastName:\"Probe\",emailAddress:$email,password:$password,roleIds:[$role]}){id}}",variables:{role:$role,email:$email,password:$password}}' |
  gql admin-api "${token}" | jq -er '.data.createAdministrator.id')"
probe_token="$(login "${probe_email}" "${probe_password}")"
[[ -n "${probe_token}" ]]
echo '{"query":"query { me { id } }"}' | gql admin-api "${probe_token}" | jq -e '.data.me.id != null' >/dev/null
jq -n --arg id "${probe_key_id}" '{query:"mutation($id:ID!){rotateApiKey(id:$id){apiKey}}",variables:{id:$id}}' |
  gql admin-api "${probe_token}" >"${work}/rotate-low"
if jq -e '(.data.rotateApiKey.apiKey // "") != ""' "${work}/rotate-low" >/dev/null; then
  echo "SECURITY: rotateApiKey let an UpdateApiKey-only administrator take over a SuperAdmin API key (GHSA-37xp-mjp8-6f9x)." >&2
  exit 1
fi
jq -e '(.errors | length) > 0' "${work}/rotate-low" >/dev/null
jq -n --arg id "${probe_key_id}" '{query:"mutation($id:ID!){rotateApiKey(id:$id){apiKey}}",variables:{id:$id}}' |
  gql admin-api "${token}" | jq -e '(.data.rotateApiKey.apiKey | length) > 0' >/dev/null

echo "Vendure health, Dashboard, closed introspection, anonymous Admin API refusal, authentication, S3 asset, shop query, worker reindex, and API key rotation authorization passed."
