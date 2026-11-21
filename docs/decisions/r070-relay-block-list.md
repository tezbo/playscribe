# Decision note: block list for abusive devices on the relay (short form)

Date / owner / card: 2026-11-12 / Priya / r070-relay-block-list (0.7.0, Nadia's yes 12 Nov). Reviews: Theo (relay), Quinn.

1. **Why.** Public testing (rel-0-8-0, criterion 5) needs a way to shut out a device or address that floods the relay or registers junk, beyond the global and per-address rate limits (#310, #402). Today the only tool is deleting the Worker's KV by hand.
3. **Worth.** Worth = one secret edit and one workflow run stops an abuser within minutes, with no KV writes and no new storage. Cost: about thirty lines in `worker.js`, one binding in `deploy.sh`, one workflow env line, tests. Rule from Nadia: a blocked id or address never lands in a public repo file or the feed branch, so the list lives only in the repository secret `RELAY_BLOCKLIST`.
4. **Alternatives.** (a) A KV key holding the list: readable from the admin route, but every request would read it (a KV read per request on the free plan) and someone still has to write it with the API token. (b) A Cloudflare WAF rule in the dashboard: no code, but agents cannot reach the dashboard and it is invisible to the repo. (c) Do nothing until the first abuse: the rate limits bound the damage, but the first case would then wait on a person with Cloudflare access. Chosen: a Worker secret bound at deploy, read from memory per request.
5. **Decision.** Added: `BLOCKLIST` secret, `parseBlocklist`, 403 on blocked addresses for every `/v1` route and on blocked ids for every device-key route except DELETE; blocked devices are left out of `GET /admin/devices`. Unchanged: rate limits, KV layout, the app.
6. **Learning.** A deny list that only a secret holds keeps the public repo clean and still leaves the change in code and tests.
