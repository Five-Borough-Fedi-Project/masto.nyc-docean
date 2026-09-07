# Cloudflare API tokens

Which token can do what, and which permission each pending change needs. Written
because "give it a Cloudflare token" is not an instruction anyone can act on.

Three tokens, because they have three different blast radii.

## 1. The snapshot token, read-only, already exists

`scripts/cloudflare-snapshot.py` reads 26 endpoints across the zone and the
account. Every one returns 200 with the current token, checked 2026-09-07, so
nothing needs adding for the audit to keep working.

It reads the whole account, including the WAF and DNS. It lives on a laptop and
should stay there. It does not belong in CI.

## 2. The upgrade token, write, in GitHub

The upgrade workflow purges the cache after a deploy. It calls one endpoint:

    POST /zones/{zone}/purge_cache

**Zone → Cache Purge → Purge**, scoped to the masto.nyc zone. That is all it
needs today.

Store as the repository secret `CLOUDFLARE_MASTO_UPGRADE_TOKEN`, with
`CLOUDFLARE_ZONE_ID` beside it. It is named for the job and not for the one
permission, because the upgrade flow is the thing likely to grow: if it later
has to flip a setting or check a rule, the permission gets added to this token
and nothing gets renamed.

It is the only Cloudflare credential that belongs in GitHub. Keep it to what the
workflow actually calls. A token that can purge a cache and nothing else is
worth very little to whoever pulls it out of a workflow log, and that property
is worth protecting as permissions accumulate.

Until both secrets exist the workflow reports what it would have done and
succeeds, so it can sit merged and inert.

The account ID that token creation hands you is not needed. Purging is a
zone-scoped call, and everything else here derives the account ID from the zone
lookup. Keep it out of GitHub: it is not a secret, and it is also not useful
there.

## 3. A change token, write, made and revoked

For the one-time changes in `docs/improvement-plan.md`. Make it, run the script,
delete it. Nothing automated depends on it.

Do not go looking for these in the dashboard. Cloudflare moves settings between
sections and renames them, and the token editor's permission labels do not match
the API paths, so finding them is a scavenger hunt that has to be repeated every
time the dashboard changes. `scripts/cloudflare-apply.py` makes each change as a
single API call instead.

    ./scripts/cloudflare-apply.py                      # read everything, change nothing
    ./scripts/cloudflare-apply.py --apply page-shield zone-hold

It reads the current value of each item and prints what would change. Nothing
happens without `--apply` and an explicit list of names, because several of these
are judgement calls and running them all at once should not be easy.

It opens by printing the exact rows to tick in the token editor, narrowed to
whichever items were named, so the token can be built for the job at hand:

    Token permissions for these items:
      Zone resources: Include -> Specific zone -> masto.nyc
        Zone -> Cache Rules -> Edit  (sometimes listed as Cache Settings)
        Zone -> Page Shield -> Edit
        Zone -> Zone -> Edit
        Zone -> Zone Settings -> Edit
      Account resources: Include -> the account owning that zone
        Account -> Workers Scripts -> Edit

Drop `Zone Settings` if `ssl-strict` and `rocket-loader-off` are being skipped,
which the narrowed output does automatically when they are not named.

When a call fails for want of a permission it prints the permission that call
needs, so the token can be widened one row at a time against real errors instead
of guesses:

    page-shield
      what:    Page Shield on
      now:     off
      FAILED:  Unauthorized to access requested resource (10000)
      needs:   Zone -> Page Shield -> Edit
               ^ that is a permissions error. Add the row above.

The items, and what each one calls:

| item | call | permission |
|---|---|---|
| `page-shield` | `PUT /zones/{z}/page_shield` | Zone → Page Shield → Edit |
| `zone-hold` | `POST /zones/{z}/hold` | Zone → Zone → Edit |
| `ssl-strict` | `PATCH /zones/{z}/settings/ssl` | Zone → Zone Settings → Edit |
| `rocket-loader-off` | `PATCH /zones/{z}/settings/rocket_loader` | Zone → Zone Settings → Edit |
| `wellknown-cache-rule` | `PUT /zones/{z}/rulesets/{id}` | Zone → Cache Rules → Edit |
| `delete-worker-*` | `DELETE /accounts/{a}/workers/scripts/{name}` | Account → Workers Scripts → Edit |
| `delete-hostname-*` | `DELETE /accounts/{a}/r2/buckets/{b}/domains/custom/{h}` then `DELETE /zones/{z}/dns_records/{id}` | Zone → DNS → Edit **and** Account → Workers R2 Storage → Edit |
| `delete-bucket-*` | `DELETE /accounts/{a}/r2/buckets/{b}` | Account → Workers R2 Storage → Edit |

The two `delete-bucket-*` items are safe by construction: R2 refuses to delete a
bucket that is not empty, so if either has gained objects since this was
measured the call fails instead of destroying them. The `delete-hostname-*`
items unbind the R2 custom domain before removing the DNS record, because
deleting the record underneath a live binding leaves the bucket holding a domain
that no longer resolves.

Two of these are decisions, and neither is an obvious fix. `ssl-strict` is the stronger
setting and every origin is a tunnel address, so the practical gap is small.
`rocket-loader-off` is worth doing only if something is actually misbehaving in
the interface. Neither runs unless named.

The load balancer notification is not in the script. It needs Account → Load
Balancing: Monitors and Pools → Edit or Account → Notifications → Edit, and the
choice of where alerts go is yours to make in the dashboard.

DNSSEC and minimum TLS 1.2 were done by hand on 2026-09-06 and are confirmed
active. They need no token.

## Why not one token

One token with everything is one secret to leak and one blast radius covering
DNS, the WAF and the load balancer. The split costs a few minutes in the
dashboard. The purge token is the only one that persists anywhere automated, and
it can purge a cache.
