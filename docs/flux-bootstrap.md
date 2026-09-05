# Bootstrapping Flux

Two clusters, one repository, one path each. After this, merging to `main` is
deploying, and the laptop stops being a required component.

## What Flux will manage, and what it will not

| reconciled | left alone |
|---|---|
| `k8s/clusters/do-production` and its base and apps | anything Terraform creates |
| `k8s/clusters/large` and its base | `k8s/migrate/`, one-shot upgrade Jobs |
| `k8s/secrets/<cluster>`, decrypted with SOPS | `k8s/infrastructure/monitoring`, which targets kube-system |

`prune: true` removes objects that disappear from git, but only objects Flux
itself applied. It tracks them by label, so nothing created by Terraform or by
hand is at risk.

`apps` declares `dependsOn: secrets`, so a cold cluster brings up Secrets before
the workloads that read them. Without that a pod can land in
`CreateContainerConfigError` on first boot.

## Before you start

You need a GitHub token with `repo` scope. Flux uses it once to commit its own
manifests and to create a deploy key; after that the cluster authenticates with
the deploy key, not the token.

```sh
export GITHUB_TOKEN=...
```

## One cluster at a time

Start with `large`. It runs two web replicas and no cronjobs, so a mistake there
is recoverable while do-production keeps serving.

```sh
flux bootstrap github \
  --context=lab \
  --owner=Five-Borough-Fedi-Project \
  --repository=masto.nyc-docean \
  --branch=main \
  --path=flux/large \
  --components=source-controller,kustomize-controller \
  --personal=false
```

`--components` matters. The default installs four controllers; we use two. See
[Memory](#memory) below.

Then install the age key so Flux can decrypt. This is the one secret that never
goes in git:

```sh
kubectl --context=lab -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/large.txt
```

Watch it converge:

```sh
flux --context=lab get kustomizations --watch
```

`secrets` should reconcile first, then `apps`. If `secrets` reports a decryption
failure, the age key is wrong or missing; nothing else will proceed, which is
the correct failure mode.

Repeat for do-production once large is healthy:

```sh
flux bootstrap github \
  --context=do \
  --owner=Five-Borough-Fedi-Project \
  --repository=masto.nyc-docean \
  --branch=main \
  --path=flux/do-production \
  --components=source-controller,kustomize-controller \
  --personal=false

kubectl --context=do -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/do-production.txt
```

## What changes afterwards

`kubectl apply` stops being how things get deployed. Edit, open a pull request,
merge, and Flux converges within its ten minute interval. To make it converge
now:

```sh
flux --context=do reconcile kustomization apps --with-source
```

Drift correction becomes automatic. Change something by hand and Flux puts it
back, which is the point, and occasionally surprising the first time it happens
during a debugging session. To stop it temporarily:

```sh
flux --context=do suspend kustomization apps
flux --context=do resume kustomization apps
```

## Memory

A default bootstrap installs four controllers, each requesting 64Mi, for 256Mi
of reserved memory. Two of the four have nothing to do here: there is not a
single HelmRelease in this repository, and no Alert, Provider or Receiver, so
helm-controller and notification-controller would idle forever holding a
reservation. Passing `--components=source-controller,kustomize-controller`
halves the footprint to 128Mi.

The 64Mi figure is a request, not consumption. kustomize-controller settles
around 25 to 40Mi and source-controller around 50 to 80Mi depending on how
large the repository gets. The 1Gi limits reserve nothing; they only cap.

do-production has no headroom to waste. Memory requests by node, against
roughly 3000Mi allocatable each:

| node | requested | actual |
|---|---|---|
| worker-pool-375ja5 | 2126Mi (70%) | 2426Mi (80%) |
| worker-pool-375jah | 2940Mi (98%) | 2881Mi (96%) |
| worker-pool-375jak | 896Mi (29%) | 1188Mi (39%) |

Only `375jak` can take the controllers, and it can take them comfortably. Check
the numbers again before bootstrapping rather than trusting this table, because
the node at 98 percent leaves no margin for the scheduler to work with:

```sh
kubectl --context=do describe nodes | grep -A5 'Allocated resources' | grep memory
```

On large this does not register. Those nodes are far bigger and sit between 6
and 11 percent requested.

Adding a controller later is a flag change and a re-bootstrap, so starting
narrow costs nothing.

## Rolling back

`flux suspend` stops reconciliation without removing anything. To leave
entirely, `flux uninstall` removes the controllers and leaves every workload
running, because Flux does not own them beyond the labels it adds.
