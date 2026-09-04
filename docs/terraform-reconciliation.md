# Bringing Terraform back in step with reality

The state in Spaces has drifted from what exists in DigitalOcean.
Resources were changed through the console, and the state was last written by
OpenTofu 1.8.1. This describes how to close that gap without changing a single
cloud resource.

The whole approach rests on one property: **refresh and apply are separable**.
`-refresh-only` reconciles state to reality and makes no cloud API writes.
`-target` narrows any operation to one resource. Together they let you reconcile
piece by piece and stop whenever something looks wrong.

## Read this before running anything

**Never run a bare `tofu apply` until a full `tofu plan` reports no changes.**
Every step below is either read-only or state-only. The first bare apply should
be a formality, not a discovery.

**Do not apply the database firewalls until `var.large_node_ips` is populated.**
`digitalocean_database_firewall` reconciles the whole rule set. The address that
lets `mastodon-large` reach Postgres was added through the console, so it lives
in reality and not in state. Applying those three resources with the variable
empty removes it and cuts the web tier off from the database.

## What the drift actually is

Measured 2026-09-03 with `tofu plan -refresh-only`, which reads and writes
nothing. Six resources had drifted.

| resource | drift | risk | status |
|---|---|---|---|
| `digitalocean_kubernetes_cluster.mastodon_k8s` | `1.32.10-do.2` in config, `1.33.12-do.3` in reality | **forces replacement** | fixed by `ignore_changes` |
| `digitalocean_database_cluster.mastodon_os` | `2` in config, `2.19` in reality | in place | fixed by `ignore_changes` |
| `digitalocean_database_firewall.mastodon_pg` | an `ip_addr` rule added by console 2026-05-24 | would be deleted | fixed by `var.large_node_ips` |
| `digitalocean_database_firewall.mastodon_redis` | same | would be deleted | same |
| `digitalocean_database_firewall.mastodon_os` | same | would be deleted | same |
| `digitalocean_firewall.k8s_private` | an outbound rule differs | low | unresolved, DOKS owns this firewall |

### The cluster replacement

`auto_upgrade = true`, so DigitalOcean upgraded the control plane on
2026-07-27 while `kubernetes.tf` still pinned the old slug. Terraform read the
config as authoritative and planned a downgrade, and a version downgrade forces
replacement. Any apply would have destroyed and recreated production.

`ignore_changes = [version]` resolves it, because `auto_upgrade` owns that
attribute. To drive an upgrade from Terraform instead, remove the line and set
`auto_upgrade = false`. Running both is how this happened.

### `-target` is not a safety boundary

The replacement was found while planning a database firewall, not the cluster.
`-target` includes the target's dependencies, and every database firewall
depends on the Kubernetes cluster through its `k8s` rule. So a narrow apply
against one firewall would have taken the cluster with it.

Scope a plan with `-target` to reduce output, never to bound blast radius. Read
every resource in the plan, not the one you aimed at.

### The firewall rules

The address that lets `mastodon-large` reach the databases was added through
the console in May and never existed in state. All three firewalls would have
lost it on the next apply, cutting the web tier off from Postgres, Valkey and
OpenSearch at once. Populating `var.large_node_ips` makes the config match
reality; that change lives in the secrets pull request, so both need to land
before an apply is safe.

## Step 0: guardrails and a backup

Already done in code: `prevent_destroy = true` on the Kubernetes cluster, the
three database clusters, and the VPC. That takes effect at plan time, with no
apply needed. Any plan that would destroy or replace one of them now fails
instead of proceeding.

Back the state up before anything writes to it. This is read-only:

```sh
tofu state pull > "state-backup-$(date +%F-%H%M).json"
```

Keep it outside the repo. It contains database passwords in cleartext.

## Step 1: look at the drift, change nothing

```sh
tofu plan -refresh-only
```

Read-only. It queries DigitalOcean, compares against state, and reports what
differs. It writes neither state nor cloud. Read the whole output before doing
anything else.

Expect three categories:

- **Attributes that changed in the console.** State is stale, reality is right.
- **Resources that exist in reality but not in state.** These need `import`.
- **Resources in state that no longer exist.** These need `removed`.

## Step 2: adopt reality into state, one resource at a time

For each resource where reality is correct and state is stale:

```sh
tofu plan  -refresh-only -target='digitalocean_database_cluster.mastodon_pg'
tofu apply -refresh-only -target='digitalocean_database_cluster.mastodon_pg'
```

`apply -refresh-only` writes **state only**. It makes no cloud API writes and
cannot create, change or destroy anything. This is the safe half of apply.

Work through the list in this order, least to most dangerous:

1. `digitalocean_vpc.mastodon_private`
2. `digitalocean_database_db`, `_user`, `_connection_pool`
3. `digitalocean_database_valkey_config.mastodon_redis`
4. `digitalocean_database_cluster.*`
5. `digitalocean_kubernetes_cluster.mastodon_k8s`
6. `digitalocean_firewall.*`
7. `digitalocean_database_firewall.*` last, and only with `large_node_ips` set

Re-run `tofu plan -refresh-only` after each. The list should shrink.

## Step 3: make the code match

Once state matches reality, `tofu plan` shows where the **code** disagrees. For
each difference, decide which side is wrong:

- **Reality is right, code is stale.** Edit the `.tf` file until the plan for
  that resource is empty. Most differences should land here.
- **Code is right, reality drifted.** This is the only case that needs a real
  apply, and it should be scoped: `tofu apply -target='...'`.

Check one resource at a time:

```sh
tofu plan -target='digitalocean_database_cluster.mastodon_pg'
```

## Step 4: resources missing from state

Adopt an existing cloud resource without creating anything, using an `import`
block rather than the older `tofu import` command, so the intent lands in
version control:

```hcl
import {
  to = digitalocean_database_firewall.mastodon_pg
  id = "the-cluster-uuid"
}
```

Then `tofu plan` shows it as an import with no changes. Delete the block after
the import succeeds.

To drop something from state without destroying the real resource, use a
`removed` block, never `tofu state rm`, so the intent is reviewable:

```hcl
removed {
  from = digitalocean_database_cluster.something
  lifecycle {
    destroy = false
  }
}
```

## Step 5: the finish line

```sh
tofu plan
```

`No changes. Your infrastructure matches the configuration.` Until you see that
line, do not run a bare apply, and do not enable the CI apply from phase 6 of
`docs/devops-roadmap.md`.

## Where this landed

With the guardrails and the secrets pull request both applied to a working
copy, and `var.large_node_ips` populated, a full plan reads:

```
Plan: 2 to add, 3 to change, 0 to destroy.
```

- **2 to add** are the two `kubernetes_secret_v1` resources the secrets change
  intends to create.
- **3 to change** are the database firewalls. Verified against the JSON plan
  rather than the rendered output: each goes from two rules to two rules and
  keeps its `ip_addr` entry. The change is the computed `uuid` and `created_at`
  fields plus the new sensitivity marking, not the rule set.
- **0 to destroy.** That is the number that matters. It was 1 before, and the
  one was the Kubernetes cluster.

The address does not appear anywhere in the plan output. It renders as
`(sensitive value)`, which is what makes the phase 6 CI apply safe to turn on.

Do not read "0 to destroy" as permission to apply. The secrets change still
needs the staged rollout in `docs/secrets-rollout.md`, and both pull requests
have to land first.

## Two things that will surprise you

**The state version upgrades on first write.** State was written by OpenTofu
1.8.1. Any write, including `apply -refresh-only`, rewrites it with the version
you are running. Older versions then refuse to read it. Pick your version, put
it in the roadmap, and use the same one everywhere.

**There is no state locking.** The Spaces backend has none configured, so two
concurrent runs can corrupt state. Reconcile from one machine, and do not start
a run while CI could be running one.
