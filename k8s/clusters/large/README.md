# clusters/large

Manifests for `mastodon-large`: two bare-metal nodes, self-hosted, running the
normal web tier. Copied from `KeepSakes/k8s/ns-mastodon` on 2026-08-31, where
they sat outside version control. Same bus-factor problem as the `private-*`
files, without the secrecy that justifies it.

This is a snapshot of what runs today. Phase 3 folds the shared
parts into `apps/mastodon/base/` and leaves the differences here.

## Not copied

`private-configmap-env-secret.yaml` stays where it is. It holds this cluster's
credentials and belongs in SOPS, which phase 4 covers.

## Differences from do-production

| | large | do-production |
|---|---|---|
| web replicas | 2 | 1, fallback |
| tunnel | `masto-nyc-large` | `masto-nyc`, `masto-nyc-small` |
| tunnel secret | `tunnel-credentials-large` | `tunnel-credentials`, `tunnel-credentials-small` |
| env sources | `mastodon-env-secret` | `mastodon-env-secret` and `mastodon-env-tf` |
| database | public hostnames, IP allowlist | VPC private hostnames |
| reconciled by | Flux, `flux/large` | Flux, `flux/do-production` |
| disruption budget | `mastodon-web`, minAvailable 1 | none, every deployment is single-replica |
| also runs | | streaming, sidekiq, cronjobs, libretranslate, welcome-webhook |

`configmap-nginx.yaml` and `serviceaccount.yaml` are byte-identical to their
do-production counterparts. `service-web.yaml` matches. `service-nginx.yaml`
differs in formatting and one missing label. `cloudflared-large.yaml` is
do-production's `cloudflared.yaml` with the names and the credentials secret
changed.

Five of these eight files are the same file maintained twice, which is the
argument for a shared base.

## Resolved

This file previously recorded a `page-replica` crawler split as an open
inconsistency between the clusters. It is gone: neither nginx config routes to
it, neither Deployment mounts the `emptyDir` it needed, and crawlers get the
same 200 as everyone else. The sidecar meant to serve it never ran.
