# Removing vector, and giving metrics-server its real name

The BetterStack log source was deleted on 2026-09-05, so vector has been
shipping into a sink that answers 401 and dropping every event. This removes it
and keeps the one useful thing that arrived alongside it.

## What was actually installed

One Helm release, `betterstack-logs`, contained two unrelated things:

- **vector**, a DaemonSet shipping pod logs to BetterStack. Now pointed at a
  deleted source. Three replicas using about 143Mi each, so roughly 5 percent
  of do-production's memory.
- **metrics-server**, the `metrics.k8s.io` API that answers `kubectl top`. It is
  ordinary upstream metrics-server and has nothing to do with BetterStack, but
  it inherited the chart's name and namespace, so it has been running as
  `mastodon/betterstack-logs-metrics-server` since the cluster was built.

The second one is the trap. Uninstalling the release to be rid of vector takes
`kubectl top` with it, and the name gives no hint of that.

## The plan

Replace the release with upstream metrics-server under its ordinary name, then
delete what is left. The large cluster has always run
`kube-system/metrics-server`, so this makes do-production match rather than
inventing a new arrangement.

The args in `k8s/infrastructure/metrics-server/deployment.yaml` are upstream
v0.8.0 defaults, and they are character for character what has been running on
do-production. The only edit is the memory request, dropped from 200Mi to 64Mi
against 33Mi measured, with a 192Mi limit added.

## Cutover

Apply the new one first. Both run side by side for a moment; only the APIService
decides which answers.

```sh
kubectl --context=do apply -k k8s/infrastructure/metrics-server
kubectl --context=do -n kube-system rollout status deploy/metrics-server
```

Expect `kubectl top` to fail for something under a minute while the new pod
becomes ready, because the APIService is repointed by the same apply. Nothing
depends on it: neither cluster runs a HorizontalPodAutoscaler, so the only
consumer is a human at a terminal.

Confirm before removing anything:

```sh
kubectl --context=do top nodes
kubectl --context=do get apiservice v1beta1.metrics.k8s.io
```

The APIService should report `True` and point at `kube-system/metrics-server`.

## Teardown

Only once the above is green.

```sh
kubectl --context=do -n mastodon delete \
  daemonset/betterstack-logs-vector \
  deployment/betterstack-logs-metrics-server \
  service/betterstack-logs-metrics-server \
  service/betterstack-logs-vector-headless \
  configmap/betterstack-logs-vector \
  configmap/vector-yaml \
  secret/vector-service-account \
  serviceaccount/betterstack-logs-metrics-server \
  serviceaccount/betterstack-logs-vector
```

```sh
kubectl --context=do delete \
  clusterrole/betterstack-logs-vector \
  clusterrole/system:betterstack-logs-metrics-server \
  clusterrole/system:metrics-server-aggregated-reader \
  clusterrole/vector-metrics \
  clusterrolebinding/betterstack-logs-metrics-server:system:auth-delegator \
  clusterrolebinding/betterstack-logs-vector \
  clusterrolebinding/system:betterstack-logs-metrics-server \
  clusterrolebinding/vector-metrics \
  -n kube-system rolebinding/betterstack-logs-metrics-server-auth-reader
```

Do not delete `apiservice/v1beta1.metrics.k8s.io`. The new manifests own it now.

`configmap/vector-yaml` is in that list because it is a two year old orphan
mounted by nothing. It is unrelated to the running config.

Last, the Helm bookkeeping. Ten release secrets hold rendered copies of the
chart, which means ten more copies of the old source token sitting in etcd:

```sh
kubectl --context=do -n mastodon delete secret -l owner=helm,name=betterstack-logs
```

## What this frees

About 429Mi of actual memory across the three nodes from vector, and 136Mi of
reserved-but-unused request from metrics-server. The reservation is the number
that matters for scheduling, and `worker-pool-375jah` is the node that needed
it.

## Left behind on purpose

`kube-state-metrics` in `k8s/infrastructure/monitoring` stays. Vector was its
only consumer, so it is now producing metrics nobody reads, but it costs little
and it is what a future log or metrics pipeline will scrape. Removing it would
only have to be undone.

## When logging comes back

The token does not go back into a values file. Vector interpolates `${VAR}` in
its config, so the shape is a SOPS-encrypted Secret in
`k8s/secrets/do-production/`, pulled in with `envFrom`, and the config carrying
`token: "${BETTERSTACK_SOURCE_TOKEN}"`. That matches how every other credential
in this repository is handled. The previous arrangement put the token in
`k8s/apps/vector/values.yaml`, which is how it ended up committed to a public
repository.
