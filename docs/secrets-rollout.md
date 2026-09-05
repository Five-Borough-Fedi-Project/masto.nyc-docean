# Rollout: ConfigMaps to Secrets

> **Completed 2026-09-04.** Both clusters hold their credentials in Secrets and
> no ConfigMap on either cluster carries one. The `kubectl apply` steps below
> are kept as a record of how it was done and as a reference if a single object
> has to be reapplied by hand. Day to day, Flux applies these from
> `k8s/secrets/<cluster>`; see `docs/secrets-sops.md`.

Every credential in both clusters lived in a ConfigMap. This change moves the
four that carry credentials into Secrets. It rolls out in stages so that no pod
ever points at an object you have deleted.

Roll it on a quiet evening. Do not combine it with a Mastodon upgrade.

## What changes

| Object | Was | Becomes | Managed by |
|---|---|---|---|
| `masto-direct-db` | ConfigMap | Secret | Terraform |
| `mastodon-env-tf` | ConfigMap | Secret | Terraform |
| `mastodon-env-secret` | ConfigMap | Secret | your private file |
| `storage-backup` | ConfigMap | Secret | your private file |
| `postgres-completion` | ConfigMap | unchanged | your private file |
| `timeline-health-config` | ConfigMap | unchanged | your private file |

54 references across 19 manifests move from `configMapRef` to `secretRef` and
from `configMapKeyRef` to `secretKeyRef`. Kubernetes treats `envFrom` the same
either way, so no application configuration changes.

A seventh object, `mastodon-haproxy-env-tf`, used to sit in that table as
unchanged. It was deleted on 2026-09-05: it held `REDIS_HOST` and `REDIS_PORT`,
was created during an haproxy setup that no longer exists, and was referenced by
nothing on either cluster. The same host and port are still carried by
`REDIS_URL` in `mastodon-env-tf`.

## Step 1: create the Secrets, leave the ConfigMaps

```sh
tofu plan     # expect: 2 Secrets to add, 0 to change, 0 to destroy
tofu apply
```

```sh
./scripts/convert-private-configmaps-to-secrets.sh \
  k8s/secrets/private-configmap-env-secret.yaml \
  k8s/secrets/private-configmap-storage-backups.yaml
```

```sh
kubectl apply -f k8s/secrets/private-configmap-env-secret.yaml
kubectl apply -f k8s/secrets/private-configmap-storage-backups.yaml
```

Confirm all four exist as Secrets, with the ConfigMaps still beside them:

```sh
kubectl -n mastodon get secret masto-direct-db mastodon-env-tf mastodon-env-secret storage-backup
```

```sh
kubectl -n mastodon get configmap masto-direct-db mastodon-env-tf mastodon-env-secret storage-backup
```

Both commands should succeed. That overlap is your safety margin.

## Step 2: point the workloads at the Secrets

```sh
for f in k8s/base/mastodon-web and k8s/apps/; do kubectl apply -f "$f"; done
```

```sh
for f in k8s/apps/cronjobs/; do
  [ "$f" = "k8s/apps/cronjobs/pg-repack-statuses.yaml" ] || kubectl apply -f "$f"
done
```

A pod-spec change rolls the deployments on its own. Expect a short gap, since
every deployment on this cluster runs one replica.

```sh
kubectl -n mastodon rollout status deployment/mastodon-web deployment/mastodon-streaming
```

```sh
kubectl -n mastodon get pods
```

**Stop here and check.** Load the site and post something. If any pod sits in
`CreateContainerConfigError`, a reference failed to resolve. Go back to step 1
rather than forward to step 3.

A cronjob proves nothing until it fires. To test the one that touches the most
keys:

```sh
kubectl -n mastodon create job --from=cronjob/postgres-backup secretref-check
```

## Step 3: remove the ConfigMaps

Wait for a full day of green first.

Delete the block in `kubernetes-secrets.tf` marked
`LEGACY CONFIGMAPS -- DELETE AT STEP 3`, then:

```sh
tofu plan     # expect: 0 to add, 0 to change, 2 to destroy
tofu apply
```

The two private ConfigMaps are gone already. Converting each file in place and
re-applying it created a Secret beside the ConfigMap rather than replacing it,
so clear the leftovers yourself:

```sh
kubectl -n mastodon delete configmap mastodon-env-secret storage-backup
```

## Step 4: the same conversion on `mastodon-large`

`large` keeps its own `mastodon-env-secret`, one merged ConfigMap of 54 keys
with the database endpoints included. Its web Deployment now references it as
`secretRef`, so it needs the same treatment against that cluster's context.

```sh
./scripts/convert-private-configmaps-to-secrets.sh \
  /media/seano/library/KeepSakes/k8s/ns-mastodon/private-configmap-env-secret.yaml
```

While that file is open, **delete the `SKIP_POST_DEPLOYMENT_MIGRATIONS` line.**
It is set there too. Nothing on `large` runs migrations, so it does nothing
today, but it is the same trap.

Then, against the large cluster:

```sh
kubectl apply -f <the converted file>
kubectl apply -f k8s/clusters/large/patch-web.yaml
kubectl -n mastodon rollout status deployment/mastodon-web
```

Do `large` first. It runs `replicas: 2`, so the rollout costs no downtime, and a
mistake in the Secret surfaces on the cluster that can absorb it.

Then clear the leftover ConfigMap:

```sh
kubectl -n mastodon delete configmap mastodon-env-secret
```

## Rollback

Before step 3: revert the manifest change, re-apply, roll. The ConfigMaps are
still there and still correct.

After step 3: restore the ConfigMap block in Terraform and apply. Every value
comes from a DigitalOcean resource or from your private files, so nothing is
lost. Waiting a day before step 3 is what keeps that true.
