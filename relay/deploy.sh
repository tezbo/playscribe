#!/usr/bin/env bash
# Deploys relay/worker.js to Cloudflare with the REST API (no wrangler to pin). Needs CLOUDFLARE_API_TOKEN (Workers Scripts
# edit + Workers KV edit). Idempotent: reuses the KV namespace and the workers.dev subdomain if they exist.
# The Feed job and the Worker share an admin token derived from CLOUDFLARE_API_TOKEN, so there is no extra secret to add.
set -euo pipefail
ACC="${CLOUDFLARE_ACCOUNT_ID:-1ae12701176ab185c99bf46eaff62a18}"
NAME=playscribe-relay
API="https://api.cloudflare.com/client/v4/accounts/$ACC"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
here="$(cd "$(dirname "$0")" && pwd)"
cf() { curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "$@"; }
# Reads a Cloudflare response on stdin; on failure prints it (responses carry no secrets) and stops.
must() { local body; body="$(cat)"; echo "$body" | jq -e '.success == true' >/dev/null 2>&1 || { echo "Cloudflare refused: ${body:0:600}" >&2; exit 1; }; }

ADMIN="$(printf 'relay-admin:%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -d' ' -f1)"
echo "::add-mask::$ADMIN"

# 1. The KV namespace.
ns="$(cf "$API/storage/kv/namespaces?per_page=100")"; echo "$ns" | must
nsid="$(echo "$ns" | jq -r --arg n "$NAME" '.result[] | select(.title == $n) | .id' | head -1)"
if [ -z "$nsid" ]; then
  made="$(cf -X POST "$API/storage/kv/namespaces" -H 'Content-Type: application/json' -d "{\"title\":\"$NAME\"}")"; echo "$made" | must
  nsid="$(echo "$made" | jq -r '.result.id')"; echo "created KV namespace"
fi

# 2. The account's workers.dev subdomain.
sub="$(cf "$API/workers/subdomain" | jq -r '.result.subdomain // empty')"
if [ -z "$sub" ]; then
  made="$(cf -X PUT "$API/workers/subdomain" -H 'Content-Type: application/json' -d '{"subdomain":"playscribe"}')"; echo "$made" | must
  sub="$(echo "$made" | jq -r '.result.subdomain')"; echo "created workers.dev subdomain"
fi

# 3. The script, with its KV binding and the admin secret.
meta="$(jq -nc --arg ns "$nsid" --arg admin "$ADMIN" '{main_module:"worker.js",compatibility_date:"2026-11-01",bindings:[{type:"kv_namespace",name:"KV",namespace_id:$ns},{type:"secret_text",name:"ADMIN_TOKEN",text:$admin}]}')"
cf -X PUT "$API/workers/scripts/$NAME" -F "metadata=$meta;type=application/json" -F "worker.js=@$here/worker.js;type=application/javascript+module;filename=worker.js" | must
cf -X POST "$API/workers/scripts/$NAME/subdomain" -H 'Content-Type: application/json' -d '{"enabled":true}' | must

url="https://$NAME.$sub.workers.dev"
echo "relay url: $url"

# 4. Smoke test: open health, closed admin, open-with-token admin.
for i in 1 2 3 4 5 6; do curl -fsS "$url/health" >/dev/null 2>&1 && break || sleep 5; done
curl -fsS "$url/health" | jq -c .
code="$(curl -s -o /dev/null -w '%{http_code}' "$url/admin/devices")"; echo "admin without token: $code"; [ "$code" = 401 ]
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $ADMIN" "$url/admin/devices")"; echo "admin with token: $code"; [ "$code" = 200 ]
