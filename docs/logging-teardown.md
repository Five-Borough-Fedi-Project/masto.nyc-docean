# Removing vector, and giving metrics-server its real name

Done 2026-09-05. Log shipping is off, nothing collects pod logs, and
metrics-server now runs under its ordinary name in `kube-system`. This records
what was removed and why, because the trap in the middle of it is worth not
rediscovering.

## The trap

One Helm release, `betterstack-logs`, contained two unrelated things:

- **vector**, a DaemonSet shipping pod logs to BetterStack. Three replicas at
  roughly 143 MiB each, about 5 percent of do-production's memory.
- **metrics-server**, the `metrics.k8s.io` API behind `kubectl top`. Ordinary
  upstream software with nothing to do with BetterStack, but it inherited the
  chart's name and namespace and had been running as
  `mastodon/betterstack-logs-metrics-server` since the cluster was built.

Uninstalling the release to be rid of vector would have taken `kubectl top` with
it, and the name gives no hint of that. DigitalOcean does not ship
metrics-server on DOKS, so there was nothing underneath to fall back to. The
APIService had pointed at that pod for two years.

## What triggered it

The BetterStack log source was deleted, which invalidated the token. Vector
began answering 401 and dropping every event. It classifies 401 as not
retriable, so it dropped rather than buffered, and memory stayed flat.

The deletion was itself a response to something worse: two BetterStack source
tokens had been committed to this public repository in
`k8s/apps/vector/values.yaml` and `configmap-vector.yaml`, swept in by a
`git add -A` during the 2026-09-04 restructure. Deleting the source was the
rotation. A later check confirmed no other log sources exist in the BetterStack
account, so the second token's source is gone too and both are dead.

## What replaced it

`k8s/infrastructure/metrics-server` holds upstream v0.8.0. The arguments are
character for character what the old one ran, so this was a rename and a
relocation rather than a reconfiguration. The only change is the memory request,
dropped from 200 MiB to 64 MiB against 33 MiB measured, with a 192 MiB limit
added.

`large` had always run `kube-system/metrics-server` under the ordinary name, so
this made do-production match rather than inventing a third arrangement.

The cutover applied the new deployment first and confirmed the APIService had
moved before anything was deleted:

```sh
kubectl --context=do top nodes
kubectl --context=do get apiservice v1beta1.metrics.k8s.io
```

`kubectl top` was unavailable for under a minute. Neither cluster runs a
HorizontalPodAutoscaler, so a human at a terminal was the only consumer.

## What was deleted

Nine namespaced objects: the vector DaemonSet, the old metrics-server
Deployment, two Services, two ConfigMaps, one Secret and two ServiceAccounts.

Then four ClusterRoles, four ClusterRoleBindings and one RoleBinding in
`kube-system`. All nine carried `meta.helm.sh/release-name: betterstack-logs`
and no DigitalOcean marker, and every binding pointed at a ServiceAccount that
had already been deleted, so they were dangling rather than merely unused.

`configmap/vector-yaml` went with them: a two year old orphan mounted by
nothing and unrelated to the running config.

Last, ten `sh.helm.release.v1.betterstack-logs.*` secrets. Those hold rendered
copies of the chart, which meant ten more copies of the leaked token sitting in
etcd.

`apiservice/v1beta1.metrics.k8s.io` was deliberately **not** deleted. It appears
in the old release's inventory and looks like teardown, but the new manifests
own it now.

## Recovered

About 429 MiB of actual memory across the three nodes from vector, and 136 MiB
of reserved-but-unused request from metrics-server.

## Left behind on purpose

`kube-state-metrics` in `k8s/infrastructure/monitoring` stays. Vector was its
only consumer, so it now produces metrics nobody reads, but it costs little and
it is what a future pipeline will scrape. Removing it would only have to be
undone.

## When logging comes back

The token does not go back into a values file. Vector interpolates `${VAR}` in
its config, so the shape is a SOPS-encrypted Secret in
`k8s/secrets/do-production/`, pulled in with `envFrom`, and the config carrying
`token: "${BETTERSTACK_SOURCE_TOKEN}"`. That matches how every other credential
in this repository is handled.

The previous arrangement put the token in `k8s/apps/vector/values.yaml`, which
is how it reached a public repository. A gitleaks scan now runs on every pull
request; see `.github/workflows/secret-scan.yaml`.

Worth deciding deliberately rather than by default: vector cost about 5 percent
of cluster memory to ship logs nobody was reading. Whatever replaces it should
earn that.
