# clusters/large

Manifests for `mastodon-large`: two bare-metal nodes, self-hosted, running the
normal web tier. Copied from `KeepSakes/k8s/ns-mastodon` on 2026-08-31, where
they sat outside version control. Same bus-factor problem as the `private-*`
files, without the secrecy that justifies it.

This is a snapshot of what runs today, not a rewrite. Phase 3 folds the shared
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
| also runs | | streaming, sidekiq x 7, cronjobs, libretranslate, welcome-webhook, vector |

`configmap-nginx.yaml` and `serviceaccount.yaml` are byte-identical to their
do-production counterparts. `service-web.yaml` matches. `service-nginx.yaml`
differs in formatting and one missing label. `cloudflared-large.yaml` is
do-production's `cloudflared.yaml` with the names and the credentials secret
changed.

Five of these eight files are the same file maintained twice, which is the
argument for a shared base.

## Known inconsistency

The nginx Deployment here mounts no volume. do-production mounts an `emptyDir`
at `/tmp/page-replica`. Both clusters run the same nginx config, which sends
crawler traffic to a local listener rooted at `/tmp/page-replica/masto.nyc`. On
do-production that directory exists and holds nothing; here it does not exist.
Both return 404, since the `page-replica` sidecar that would fill it stays
commented out. The clusters agree by coincidence. Worth resolving either way.
