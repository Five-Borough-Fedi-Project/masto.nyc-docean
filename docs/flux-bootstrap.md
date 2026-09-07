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

It happened again on 2026-09-06, when metrics-server and kube-state-metrics
came under Flux. kube-state-metrics carried the same February 2025 annotation
and restarted; metrics-server, applied from these manifests the day before, did
not.

## kubectl diff does not predict what Flux will do

Worth knowing before adopting anything else, because it is the trap in the
paragraph above.

`kubectl diff` shows what a client-side apply would change, and client-side
apply merges: it leaves fields alone that the manifest does not mention, so an
annotation living only in the cluster produces no diff. Flux uses server-side
apply, which takes ownership and removes fields the manifest does not declare.

So `kubectl diff -k` exiting 0 means the manifests match, and says nothing about
whether Flux will restart something. Before pointing Flux at a path, check for
cluster-only fields directly:

```sh
kubectl --context=do get deploy,daemonset -n <ns> -o json \
  | grep -c 'kubectl.kubernetes.io/restartedAt'
```

Anything it finds will be removed on the first reconciliation, and removing a
pod-template annotation changes the template hash and rolls the workload.

Three Deployments still carry one: coredns, hubble-relay and hubble-ui. All are
managed by DigitalOcean and none are under Flux, so they are unaffected.
Both clusters otherwise reconciled to no changes, which is the boring result you
want from a first bootstrap.

## A defaulted field can block every Kustomization at once

On 2026-09-07 both clusters stopped reconciling entirely. The error named one
Deployment:

    Deployment/mastodon/libretranslate dry-run failed (Invalid):
    spec.strategy.rollingUpdate: Forbidden: may not be specified
    when strategy `type` is 'Recreate'

The change was adding `strategy: {type: Recreate}` to a Deployment that had been
running the default `RollingUpdate`. The API server had defaulted
`spec.strategy.rollingUpdate` on the live object years ago. Nothing in the
manifest mentions that field, so nothing removed it, and the merged result was a
Deployment that set `Recreate` while still carrying `rollingUpdate` — which the
API server rejects.

Two things worth taking from it.

`kubectl apply --dry-run=server` did not catch this. It was run against both
clusters before the change was merged and reported `configured` for that
Deployment, because kubectl's three-way merge removes fields absent from the new
manifest and Flux's apply did not. This is the same gap as the section above, in
a different shape: the local check and the thing that will actually run disagree,
and the local check is the optimistic one.

**The whole Kustomization stops, so one bad object takes everything with it.**
`apps` went not-ready on both clusters, `migrate-pre` and `migrate-post` went
not-ready behind it, and nothing else in the namespace was reconciling for as
long as it took to notice. The blast radius of an invalid manifest is not the
object it names.

The fix is to bring the live object in line first, then let Flux apply:

```sh
kubectl --context=do -n mastodon patch deploy libretranslate --type=json -p \
  '[{"op":"remove","path":"/spec/strategy/rollingUpdate"},
    {"op":"replace","path":"/spec/strategy/type","value":"Recreate"}]'
```

One atomic patch, because removing the field and changing the type in two steps
leaves an invalid object in between. Deleting the Deployment and letting Flux
recreate it works too and costs an outage of whatever it runs.

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
