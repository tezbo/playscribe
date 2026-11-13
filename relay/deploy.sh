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
must() { local body; body="$(cat)"; echo "$body" | jq -e '.success == true' >/dev/null 2>&1 || { echo "Cloudflare refused ${1:-a call}: ${body:0:600}" >&2; exit 1; }; }

ADMIN="$(printf 'relay-admin:%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -d' ' -f1)"
echo "::add-mask::$ADMIN"
# The App Store Connect webhook secret is derived the same way, so nobody pastes one. The APNs key is bound only when the
# workflow supplies it (APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID); without it the webhook still verifies and records, and sends nothing.
HOOK="$(printf 'asc-webhook:%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -d' ' -f1)"
echo "::add-mask::$HOOK"

# 1. The KV namespace.
ns="$(cf "$API/storage/kv/namespaces?per_page=100")"; echo "$ns" | must "list KV namespaces"
nsid="$(echo "$ns" | jq -r --arg n "$NAME" '.result[] | select(.title == $n) | .id' | head -1)"
if [ -z "$nsid" ]; then
  made="$(cf -X POST "$API/storage/kv/namespaces" -H 'Content-Type: application/json' -d "{\"title\":\"$NAME\"}")"; echo "$made" | must "create KV namespace"
  nsid="$(echo "$made" | jq -r '.result.id')"; echo "created KV namespace"
fi

# 2. The account's workers.dev subdomain. Terry registered "playscribe" in the dashboard; the API token cannot read or set it
# (Cloudflare answers "Authentication error" to the subdomain endpoint), so the name is taken from RELAY_SUBDOMAIN.
sub="${RELAY_SUBDOMAIN:-playscribe}"
got="$(cf "$API/workers/subdomain" | jq -r '.result.subdomain // empty' 2>/dev/null || true)"
[ -n "$got" ] && sub="$got"

# 3. The script, with its KV binding, the admin secret and the register rate limit (5 new devices a minute per address).
# FEED_DISPATCH_TOKEN (optional): lets the Worker's cron start the Feed workflow when GitHub's schedule does not (docs/push-relay.md "Feed cron").
# RELAY_BLOCKLIST (optional): device ids and addresses to refuse, bound as the BLOCKLIST secret; the list lives only in the repository secret (docs/push-relay.md "Block list").
meta="$(jq -nc --arg ns "$nsid" --arg admin "$ADMIN" --arg hook "$HOOK" --arg key "${APNS_KEY:-}" --arg kid "${APNS_KEY_ID:-}" --arg team "${APNS_TEAM_ID:-}" --arg gh "${FEED_DISPATCH_TOKEN:-}" --arg block "${RELAY_BLOCKLIST:-}" '{main_module:"worker.js",compatibility_date:"2026-11-01",bindings:([{type:"kv_namespace",name:"KV",namespace_id:$ns},{type:"ratelimit",name:"REGISTER_LIMIT",namespace_id:"1001",simple:{limit:5,period:60}},{type:"secret_text",name:"ADMIN_TOKEN",text:$admin},{type:"secret_text",name:"ASC_WEBHOOK_SECRET",text:$hook}] + (if $key != "" and $kid != "" and $team != "" then [{type:"secret_text",name:"APNS_KEY",text:$key},{type:"secret_text",name:"APNS_KEY_ID",text:$kid},{type:"secret_text",name:"APNS_TEAM_ID",text:$team}] else [] end) + (if $gh != "" then [{type:"secret_text",name:"FEED_DISPATCH_TOKEN",text:$gh}] else [] end) + (if $block != "" then [{type:"secret_text",name:"BLOCKLIST",text:$block}] else [] end))}')"
cf -X PUT "$API/workers/scripts/$NAME" -F "metadata=$meta;type=application/json" -F "worker.js=@$here/worker.js;type=application/javascript+module;filename=worker.js" | must "upload Worker script"
# The cron triggers (worker.js FEED_FULL_CRON and FEED_HOT_CRON): 5 minutes after GitHub's own :17 and :47, so a run GitHub did start is seen and not doubled.
cf -X PUT "$API/workers/scripts/$NAME/schedules" -H 'Content-Type: application/json' -d '[{"cron":"22 * * * *"},{"cron":"52 * * * *"}]' | must "set cron triggers"
[ -n "${FEED_DISPATCH_TOKEN:-}" ] && echo "feed cron: on (token bound)" || echo "feed cron: idle (no FEED_DISPATCH_TOKEN; add the repository secret and redeploy)"
# Putting the script on workers.dev; a refusal here is not fatal because new scripts are usually on it already, and the smoke test below decides.
en="$(cf -X POST "$API/workers/scripts/$NAME/subdomain" -H 'Content-Type: application/json' -d '{"enabled":true}')"
echo "$en" | jq -e '.success == true' >/dev/null 2>&1 || echo "workers.dev enable not confirmed: ${en:0:300}"


url="https://$NAME.$sub.workers.dev"
echo "relay url: $url"

# 4. Smoke test: open health, closed admin, open-with-token admin.
for i in 1 2 3 4 5 6; do curl -fsS "$url/health" >/dev/null 2>&1 && break || sleep 5; done
curl -fsS "$url/health" | jq -c .
code="$(curl -s -o /dev/null -w '%{http_code}' "$url/admin/devices")"; echo "admin without token: $code"; [ "$code" = 401 ]
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $ADMIN" "$url/admin/devices")"; echo "admin with token: $code"; [ "$code" = 200 ]
