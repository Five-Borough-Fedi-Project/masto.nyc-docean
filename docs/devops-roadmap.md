# DevOps roadmap

The goal: no deploy should require one specific laptop.

The target splits the two tools by the direction they push. Terraform runs from
GitHub Actions, because it needs cloud credentials and provisions the cluster
itself. Kubernetes runs from Flux inside each cluster, which dials out to GitHub
and pulls, so GitHub never holds a kubeconfig.

Two clusters pull from this repo. `do-production` on DigitalOcean carries
nginx, streaming, the seven sidekiq deployments and the cronjobs.
`large` is a two-node bare-metal cluster running the normal web tier. Each
reconciles only its own path. Read `docs/multi-cluster.md` before phases 3, 4
or 5, since it changes what those phases produce.

Everything below costs nothing. The repo is public, so Actions minutes are
unlimited. A private repo would cap you at 2,000 minutes a month.

## Read this before reordering anything

**Phase 2 must land before phase 6.** Workflow logs on a public repo are
world-readable. The Terraform provider does not mark `kubernetes_config_map_v1`
data as sensitive, so a `tofu plan` in CI prints the database password, the SMTP
password and the Spaces keys straight into a public log.
`kubernetes_secret_v1` renders as `(sensitive value)`.

## Phases

| # | Phase | Blocked by | Status |
|---|-------|-----------|--------|
| 0 | Back up the eight `private-*` files off the laptop. Rotate the DO token and Spaces keys | | **manual, do first** |
| 1 | Safe fixes: pin images, restrict the build workflow to main, add the migration-status check | | this branch |
| 2 | Move credentials from ConfigMaps into Secrets | 0 | next |
| 3 | Kustomize: shared base plus one overlay per cluster | 2 | |
| 4 | SOPS and age, two keys. Commit encrypted secrets, delete the `private-*` pattern | 0, 2 | |
| 5 | Bootstrap Flux in both clusters, each with its own `--path` | 3, 4 | |
| 6 | Terraform in Actions: plan on PR, apply on merge behind an environment gate | 2, `large_node_ips` populated | |
| 7 | Renovate for image bumps | 3 | |

## Notes

**Phase 0** takes about an hour and needs no new tooling. It also removes the
largest risk in this document. `mastodon-env-secret` holds `SECRET_KEY_BASE`,
`OTP_SECRET`, `VAPID_PRIVATE_KEY` and the three `ACTIVE_RECORD_ENCRYPTION_*`
keys. If that laptop dies you cannot recover existing 2FA enrollments or push
subscriptions.

**Phase 2** rolls out in three steps so that no pod points at an object that has
been deleted. A pod restarting after you remove its `configMapRef` target fails
with `CreateContainerConfigError`.

1. Add the Secret resources while the ConfigMaps still exist. A Secret and a
   ConfigMap can share a name, since they are different API resources.
2. Update the manifests to `secretRef` and `secretKeyRef`, then roll the
   deployments.
3. Remove the ConfigMap resources.

**Phase 5** uses Flux rather than Argo CD. Argo wants 1 to 2 GiB across its
components. The DO cluster has 12 GiB across three nodes and already runs
Mastodon, two tunnels, Vector and LibreTranslate. Flux's four controllers fit in
roughly 300 MiB and decrypt SOPS without a plugin.

**Phase 6** needs `var.large_node_ips` populated first.
`digitalocean_database_firewall` reconciles the whole rule set for a database.
An automated apply with that list empty, on firewalls whose IP rules were added
by hand, deletes the rules that let `large` reach Postgres. The variable
defaults to an empty list, which adds nothing and deletes nothing, but do not
lean on that once CI applies on merge.

**Phase 6, second constraint:** OpenTofu 1.8 or newer, and OpenTofu
specifically. The backend block references `var.state_bucket` and
`var.state_key`. OpenTofu supports variables in backend configuration from 1.8
onward; HashiCorp Terraform rejects them at every version.

Pick the version CI pins and install the same one locally. State written by a
newer tofu is unreadable by an older one, and CI should not be the thing that
upgrades it first. The last recorded state write came from OpenTofu 1.8.1.

    CI pins OpenTofu: <TBD, fill in when the workflow lands>

## Out of scope

- **Migrations stay human-triggered.** See `docs/upgrade-runbook.md`.
- **Single-replica stays single-replica.** `mastodon-web`,
  `mastodon-streaming` and `mastodon-nginx` each run one pod on
  `do-production`, so every rollout there is a short outage. Adding replicas is
  a capacity decision, separate from automation.
