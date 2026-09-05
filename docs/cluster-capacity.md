# do-production capacity

Measured 2026-09-05, after the sidekiq consolidation, the removal of vector, and
the memory request work. An earlier revision of this file recorded two
operational rules born of a cluster running above 100 percent. Both are gone.
What replaced them is a smaller and more useful set of facts.

## The cluster has less memory than it looks like

This part has not changed and will not. Three `s-2vcpu-4gb` nodes read as
12 GiB. DOKS reserves 919 MiB per node for system components:

| | per node | cluster |
|---|---|---|
| capacity | 3915 MiB | 11745 MiB |
| **allocatable** | **2996 MiB** | **8988 MiB** |

Plan against 8988.

## Where it currently sits

| node | requested | actual | free by request |
|---|---|---|---|
| worker-pool-375ja5 | 2510 MiB (83%) | 2543 MiB (84%) | 486 MiB |
| worker-pool-375jah | 2868 MiB (95%) | 2299 MiB (76%) | 128 MiB |
| worker-pool-375jak | 1024 MiB (34%) | 1200 MiB (40%) | 1972 MiB |

Requests total 6402 MiB, 71 percent of allocatable.

Read the two columns together. `375jah` shows 95 percent requested against 76
percent actual, and that gap is deliberate. Before 2026-09-05 four workloads
declared no requests at all while using 655 MiB, so the scheduler's model of
this cluster was wrong by most of a gigabyte and the requested column was
fiction. It is now a slight overstatement instead, which is the correct
direction to be wrong in.

Scheduling is bounded by the largest free block on any single node, currently
1972 MiB on `375jak`. The 2586 MiB cluster total is spread across three machines
and no single pod can reach it.

## Restarting mastodon-web

`kubectl rollout restart deployment/mastodon-web` used to deadlock here. The
default strategy surges to a second pod before terminating the first,
`mastodon-web` requests 1024 MiB, and no node had that free while the old pod
still held its request. The surge pod stayed Pending on
`FailedScheduling: 3 Insufficient memory` and the rollout sat there forever.

It works now, and it worked on 2026-09-05 during the priority class rollout,
because `375jak` has 1972 MiB free. That is the whole reason, so it is also the
thing to check before assuming it will work again:

```sh
kubectl --context=do describe nodes | grep -A5 'Allocated resources' | grep memory
```

If no node has 1024 MiB free, delete the pod instead. The
ReplicaSet schedules the replacement once the old one releases its request:

```sh
kubectl --context=do -n mastodon delete pod -l app.kubernetes.io/component=web
```

`masto.nyc` stays up through either path because `mastodon-large` serves it. An
external check passing tells you nothing about the state of the DO pod.

## OOMKills

The earlier revision of this file said to expect them every few days. As of
2026-09-05 there are no restarts and no terminated containers anywhere in the
namespace, and no OOM events.

Three changes did it. Seven single-queue sidekiq deployments became three on
2026-09-04, which stopped paying the Rails boot cost seven times and freed
about 1.6 GiB. Vector left on 2026-09-05 with another 429 MiB of real usage
across the three nodes. And the workloads that had been invisible to the
scheduler started declaring what they use.

If pressure returns, the options in rough order of preference:

1. **Move work off do-production.** `mastodon-large` already serves the web
   tier. If Cloudflare can be weighted to prefer it, DO's `mastodon-web` could
   drop to zero replicas and return 1024 MiB. Both DO tunnels currently route
   `masto.nyc` to `mastodon-nginx`, which proxies to `mastodon-web:3000` in this
   cluster, so that pod serves whenever the edge picks a DO tunnel. Confirm the
   Cloudflare side before relying on this.
2. **Add a fourth node.** Costs money, which for this project is the binding
   constraint.
3. **Restart `mastodon-web` on a schedule.** Hides the symptom and leaves you
   one busy week from the same problem.

## What is running that did not used to be

Both additions landed on 2026-09-05 and both are small:

| | requested | actual |
|---|---|---|
| metrics-server, `kube-system` | 64 MiB | 33 MiB |
| Flux, two controllers | 128 MiB | 106 MiB |

Flux runs `source-controller` and `kustomize-controller` only. A default
bootstrap installs four; `helm-controller` and `notification-controller` have
nothing to do here, since the repository contains no HelmRelease and no Alert,
Provider or Receiver. Passing
`--components=source-controller,kustomize-controller` halved the footprint. See
`docs/flux-bootstrap.md`.

## Probes

An earlier revision of this file warned that `mastodon-web` had no readiness
probe, so a pod reported Ready before Puma accepted connections. That is fixed.
`k8s/base/mastodon-web/deployment.yaml` now sets a startupProbe of 60 failures
at 5 second intervals, giving Puma five minutes to boot, with readiness and
liveness probes behind it.
