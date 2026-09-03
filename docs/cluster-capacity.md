# do-production capacity

Measured 2026-09-03, two days after the v4.7.0 upgrade. Recorded because the
numbers contradict what the node size suggests, and because two operational
rules fall out of them.

## The cluster has less memory than it looks like

Three `s-2vcpu-4gb` nodes read as 12 GiB. DOKS reserves roughly 940 MiB per
node for system components, so the schedulable figure is:

| | per node | cluster |
|---|---|---|
| capacity | 3915 MiB | 11745 MiB |
| **allocatable** | **2996 MiB** | **8988 MiB** |
| requested | 2194 to 2588 MiB | 7146 MiB (80%) |
| free by requests | 400 to 800 MiB | 1842 MiB |

Plan against 8988, not 11745. The largest single pod that can be scheduled is
bounded by the free space on one node, around 800 MiB, not by the 1842 MiB
cluster total.

## Rule 1: restart `mastodon-web` by deleting the pod

`kubectl rollout restart deployment/mastodon-web` does not work here. The
default strategy surges to a second pod before terminating the first, and
`mastodon-web` requests 1024 MiB, which no node has free while the old pod
still holds its request. The surge pod stays Pending:

```
FailedScheduling: 0/3 nodes are available: 3 Insufficient memory.
preemption: 0/3 nodes are available: No preemption victims found
```

The rollout then sits there. The old pod keeps serving, so nothing breaks, but
nothing happens either.

Delete the pod instead. The ReplicaSet schedules the replacement once the old
one releases its request:

```sh
kubectl -n mastodon delete pod -l app.kubernetes.io/component=web
```

Two things to know when you do:

- The readiness probe in `deployment-web.yaml` is commented out, so the pod
  reports Ready as soon as the container starts, well before Puma accepts
  connections. Verify from inside the cluster rather than trusting the status:

  ```sh
  kubectl -n mastodon exec deploy/dbg -- curl -sf http://mastodon-web.mastodon:3000/health
  ```

- `masto.nyc` stays up during the gap because `mastodon-large` serves it. The
  external check passing tells you nothing about the DO pod.

## Rule 2: expect OOMKills every few days until this is fixed

`mastodon-web` grew from 301 MiB at boot to 1109 MiB over three days of serving.
Restarting reclaimed 808 MiB and took the worst node from 103% to 73%.

While a node sits above 100%, containers get killed at their own limits.
As of this measurement, `mastodon-sidekiq-pull` had been OOMKilled six times and
`mastodon-sidekiq-ingress` three, both against 900 MiB limits, exit code 137.

Raising those limits makes it worse. The limits are already generous for those
queues, and the pressure comes from the node being full.

Three ways out, none of them free:

1. **Restart `mastodon-web` weekly.** Hides the symptom, costs nothing, and
   leaves you one busy week from the same problem.
2. **Add a fourth node.** Costs money, which for this project is the binding
   constraint.
3. **Move work off do-production.** `mastodon-large` already serves the web
   tier. If Cloudflare can be weighted to prefer it, DO's `mastodon-web` could
   drop to zero replicas and return 1024 MiB of requests, which is more
   headroom than any of the other options.

Option 3 needs confirmation on the Cloudflare side first. Both DO tunnels
currently route `masto.nyc` to `mastodon-nginx`, which proxies to
`mastodon-web:3000` in this cluster, so that pod serves whenever the edge picks
a DO tunnel.

## What this means for Flux

Phase 5 of `docs/devops-roadmap.md` puts Flux in this cluster at roughly
300 MiB. That fits in 1842 MiB of cluster headroom, but only because Flux ships
as four small controllers rather than one pod. Do not add it while a node is
running above 100%, or the scheduler will place it and something else will be
killed to make room.
