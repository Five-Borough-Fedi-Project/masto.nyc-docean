# Two clusters, one repository

## What runs where

| | **do-production** (DigitalOcean, Terraform-managed) | **large** (bare metal, 2 nodes, unmanaged) |
|---|---|---|
| web | yes, `replicas: 1`, fallback | yes, `replicas: 2`, the serving tier |
| streaming | yes | no |
| sidekiq (3 deployments) | yes | no |
| nginx | yes | yes, identical config |
| cloudflared | `masto-nyc`, `masto-nyc-small` | `masto-nyc-large` |
| cronjobs | yes | no |
| libretranslate, welcome-webhook, vector | yes | no |
| database path | VPC private hostnames | public hostnames, IP allowlist |

Cloudflare spreads `masto.nyc` across the three tunnels, so both clusters serve
without either one opening a port. Neither accepts inbound connections; both
dial out. Keep that property.

## The constraint that shapes the layout

Terraform builds `mastodon-env-tf` from DigitalOcean `private_host` values.
Those hostnames resolve only inside the VPC, so `large` cannot use that Secret.
The two clusters need different values for `DB_HOST`, `DB_PORT`, `ES_HOST` and
`REDIS_URL`. Per-cluster overlays follow from that.

Check `TRUSTED_PROXY_IP` while you are there. It is `10.0.0.0/8`, which suits
DOKS. If it does not match the pod CIDR on `large`, Rails attributes every
request to the proxy instead of the client.

## Database firewalls

`digitalocean_database_firewall` reconciles the entire rule set for a database.
Any IP you add through the DO console disappears on the next apply. Since
`large` reaches Postgres, Valkey and OpenSearch over their public hostnames,
those IPs belong in `var.large_node_ips`. Populate it before you enable
automated apply, or a merge severs the web tier from the database with nobody
watching.

The variable defaults to an empty list. An empty list adds no rules and deletes
none, so an apply from a workstation that has not set it does nothing. That is
the point.

## Protecting the large cluster's address

`var.large_node_ips` is marked sensitive, so `tofu plan` renders each firewall
rule as `(sensitive value)` rather than printing the address. The Terraform uses
`nonsensitive()` to iterate the list and `sensitive()` to re-mark each element,
because `for_each` cannot walk a sensitive value directly.

The reason is the Cloudflare tunnel. `mastodon-large` runs cloudflared so that
its origin address stays private. Publishing that address anywhere, in a
committed tfvars, in a plan comment on a pull request, or in an Actions log on
this public repo, undoes that and lets anyone reach the box without going
through Cloudflare.

Supply the value locally through the gitignored `terraform.tfvars`, and in CI
through a `TF_VAR_large_node_ips` Actions secret. Confirm on the first real plan
that the rules render as `(sensitive value)`.

Two limits worth knowing. Sensitivity covers plan and apply output, not state,
so the address sits in cleartext in the Spaces state bucket. And the address is
still allowlisted at three managed databases, so it remains a credential-shaped
thing even though it is only an IP.

Tunneling the connection was considered and rejected. cloudflared can proxy
TCP, which would remove the allowlist and stop the databases accepting
connections from any enumerable address. It also adds a userspace proxy hop to
every query. Rails issues many small queries per request and the web tier runs
on `large`, so that cost lands on the critical path. Latency is the binding
constraint here, not the allowlist.

If the allowlist ever needs to go, the option that does not add a hop is a
kernel-level link, WireGuard or Tailscale, terminated on a small droplet inside
the VPC. That costs a droplet rather than a round trip. Until then the address
stays allowlisted and stays protected.

## Repository layout

Both clusters run Flux, both point at this repo, and each reconciles one
directory. Nothing gets copied between clusters. The differences live in the
overlays.

```
apps/mastodon/base/          shared manifests: web, streaming, sidekiq, nginx,
                             cloudflared, cronjobs
clusters/do-production/      Flux entry point, patches in private DB endpoints
clusters/large/              Flux entry point, patches in public DB endpoints
secrets/shared/              encrypted to both age keys
secrets/do-production/       encrypted to the DO key
secrets/large/               encrypted to the large key
```

Run `flux bootstrap` once per cluster with a different `--path`. Neither cluster
can read the other's secrets, because SOPS encrypts per recipient.

## Secrets across two clusters

Sealed Secrets encrypts against one cluster's key. Two clusters would mean two
encrypted copies of every shared value, so it is out. SOPS encrypts to multiple
recipients.

Generate two age keys, one per cluster, and split `.sops.yaml` by path:

| Content | Location | Encrypted to |
|---|---|---|
| App identity and third-party credentials | `secrets/shared/` | both keys |
| Database endpoints (`DB_HOST`, `ES_*`, `REDIS_URL`) | `secrets/<cluster>/` | that cluster |
| Tunnel credentials | `secrets/<cluster>/` | that cluster |
| Tuning (`DB_POOL`, `MAX_THREADS`, `TRUSTED_PROXY_IP`) | cluster overlay, plain ConfigMap | nothing, no credentials here |

One shared key across both clusters also works and takes less setup. The
two-key split means that someone who compromises the bare-metal box does not
also get the DigitalOcean tunnel credentials. Given that `large` sits in a
different building, that separation earns its cost.

## `large` runs its own nginx

Confirmed against the live manifests. `masto-nyc-large` routes `masto.nyc` to
`mastodon-nginx.mastodon:80`, matching the do-production tunnels, and
`configmap-nginx.yaml` is byte-identical on both clusters. Caching and the
crawler split behave the same whichever tunnel Cloudflare picks.

One inconsistency remains. On do-production the nginx Deployment mounts an
`emptyDir` at `/tmp/page-replica`. On `large` it mounts nothing. The shared
nginx config routes crawler traffic to a listener rooted at
`/tmp/page-replica/masto.nyc`, so do-production serves from an empty directory
and `large` from a directory that does not exist. Both return 404, because the
`page-replica` sidecar that would fill it stays commented out. The two clusters
agree by coincidence. Fix it in one direction or the other.

## Where the environment lives

The clusters split their configuration differently, and the shared base has to
reconcile that:

- **do-production** reads `mastodon-env-secret` for app identity and
  `mastodon-env-tf`, generated by Terraform, for database endpoints.
- **large** reads one merged `mastodon-env-secret` of 54 keys, endpoints
  included, maintained by hand.

About thirty values overlap: `SECRET_KEY_BASE`, `OTP_SECRET`, `VAPID_*`, the
three `ACTIVE_RECORD_ENCRYPTION_*` keys, plus the SMTP and S3 credentials. You
maintain them twice, in two files, on one laptop, and they have to match. Let
them drift and sessions break on one cluster, or 2FA does, or push
notifications do. The failure looks intermittent, because which cluster served
the request decides whether it works. That is the case for splitting shared
secrets from per-cluster ones.

## `SKIP_POST_DEPLOYMENT_MIGRATIONS` is set on `large` too

It sits in `large`'s `mastodon-env-secret` as it did in
do-production's. Nothing on `large` runs migrations, so it does nothing today.
The trap is the same one: any pod that inherits that environment and runs
`db:migrate` skips post-deployment migrations without saying so. Delete the line
when you convert that file to a Secret.

## What Terraform should manage

Terraform manages DigitalOcean. It does not manage `large` and should not start.
The cluster is not its resource, and handing CI a kubeconfig for an offsite
cluster works against the pull model.

That leaves a seam. Terraform writes `mastodon-env-tf` and `masto-direct-db`
into the DO cluster through the `kubernetes` provider, and it has no way to
write the equivalent for `large`. Once SOPS is in place you have two options:

1. **Terraform keeps writing DO's Secrets, and you maintain large's by hand.**
   Less to change now. The two clusters' database credentials can drift if
   anyone rotates the database user.
2. **Terraform stops writing Kubernetes objects** and exposes the values as
   sensitive outputs. Both clusters then read committed SOPS secrets. This drops
   the `kubernetes` provider from `provider.tf`, so the Terraform CI job needs a
   DO token and no cluster access at all. Rotating the database password becomes
   a manual re-encrypt.

Option 2 is the better end state and blocks nothing, so it can wait until Flux
runs in both clusters.
