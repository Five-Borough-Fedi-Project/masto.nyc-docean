# Flux

Both clusters were bootstrapped on 2026-09-05. Merging to `main` is now
deploying, and the laptop is no longer part of the deploy path.

This file records how it is wired, what went wrong during bootstrap in case it
has to be done again, and how to work with a cluster that reverts your changes.

## Shape

Two `Kustomization` resources per cluster, plus the `flux-system` one that
bootstrap creates for itself:

| name | path | decryption | dependsOn |
|---|---|---|---|
| `secrets` | `k8s/secrets/<cluster>` | SOPS | |
| `apps` | `k8s/clusters/<cluster>` | | `secrets` |

`dependsOn` is not decoration. On a cold cluster a pod that starts before its
Secret exists lands in `CreateContainerConfigError`, and during the 2026-09-05
bootstrap `apps` correctly refused to start while `secrets` was failing.

`prune: true` removes objects that disappear from git, but only objects Flux
itself applied, tracked by label. Terraform-managed resources and anything
applied by hand are not at risk.

`flux/` sits outside `k8s/` because bootstrap writes its own controller
manifests into whatever path it is given, and mixing those with the manifests
being reconciled makes both harder to read.

## What Flux does not manage

Reconciled paths are `k8s/clusters/<cluster>` and `k8s/secrets/<cluster>`.
Everything else is outside its view:

- `k8s/infrastructure/metrics-server` and `k8s/infrastructure/monitoring` target
  `kube-system` and are applied out of band. Worth folding in later.
- `k8s/migrate/` holds one-shot Jobs a human runs during an upgrade.
- Anything Terraform owns.

## The commands, for the next time

```sh
export GITHUB_TOKEN=...

flux bootstrap github \
  --context=lab \
  --owner=Five-Borough-Fedi-Project \
  --repository=masto.nyc-docean \
  --branch=main \
  --path=flux/large \
  --components=source-controller,kustomize-controller \
  --personal=false
```

`--components` matters: the default installs four controllers at 64Mi each, and
two of them have nothing to do here. See `docs/cluster-capacity.md`.

Then the age key, which is the one secret that never goes in git:

```sh
kubectl --context=lab -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/large.txt
```

Repeat with `--context=do`, `--path=flux/do-production`, and
`do-production.txt`. Each path gets its own deploy key, so the repository ends
up with two. Both are required.

## The token needs more than you would guess

The first attempt on 2026-09-05 failed here:

```
✗ POST https://api.github.com/repos/.../keys: 403 Resource not accessible by personal access token
```

The push had already succeeded, so the token had `Contents: write` and was
approved for the organisation. What it lacked was **`Administration: Read and
write`**, which is the fine-grained permission governing deploy keys. That
wording, `Resource not accessible by personal access token`, is specific to
fine-grained tokens; a classic token fails differently.

Two things about fixing it. Changing permissions on a fine-grained token
**revokes its organisation approval**, so an owner has to approve it again
before it works. And bootstrap is idempotent: rerunning the identical command
after fixing the token picked up exactly where it stopped.

`--token-auth=true` avoids needing the permission by storing the PAT in-cluster
as basic auth instead. Avoid it. The PAT becomes a live credential in the
cluster, and when it expires Flux stops syncing with no obvious signal. Deploy
keys do not expire.

## Working with a cluster that reverts you

Drift correction is the point, and it is startling the first time it happens
mid-debugging. Change something with `kubectl` and Flux puts it back within its
ten minute interval.

To trigger a reconcile immediately:

```sh
flux --context=do reconcile kustomization apps --with-source
```

To stop it while you work:

```sh
flux --context=do suspend kustomization apps
flux --context=do resume kustomization apps
```

**Suspend before a Mastodon upgrade.** The upgrade runbook scales deployments
and runs migration Jobs, and an unsuspended Flux will undo the scaling
mid-migration. See `docs/upgrade-runbook.md`.

## What the first reconciliation did

Worth knowing, because it looks alarming and is not.

On do-production, Flux immediately rolled `libretranslate`. The cause was a
single annotation:

```
kubectl.kubernetes.io/restartedAt: 2025-02-26T00:15:12-05:00
```

left behind by a `kubectl rollout restart` in February 2025. It existed only in
the cluster. Git never had it, Flux applies the git state, and removing the
annotation changed the pod template hash, which triggered one rollout. That is
drift correction working exactly as intended.

It was a one-off. No other workload on either cluster carries that annotation.
Both clusters otherwise reconciled to no changes, which is the boring result you
want from a first bootstrap.

## Checking on it

```sh
flux --context=do get kustomizations
```

All three should report `True` on the same revision. If `secrets` reports a
decryption failure the age key is wrong or missing, and nothing downstream
proceeds, which is the correct failure mode.

## Leaving

`flux suspend` stops reconciliation without removing anything. `flux uninstall`
removes the controllers and leaves every workload running, because Flux does not
own them beyond the labels it adds. Backing out is cheap.
