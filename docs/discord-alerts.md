# Alerts in Discord

Three sources, three different mechanisms, one channel if you want it that way.
Nothing here runs a service or a translator, because each source can already
speak a format Discord accepts.

## The trick that makes this cheap

A Discord webhook URL accepts two foreign formats on suffixed paths:

| suffix | accepts | used by |
|---|---|---|
| `/github` | GitHub's webhook payloads | pull requests, issues, pushes |
| `/slack` | Slack's payload shape | DigitalOcean alerts, Cloudflare notifications |

DigitalOcean's only webhook-shaped destination is its Slack one, and
Cloudflare's webhook payload carries a `text` field, which is what Discord's
Slack endpoint reads. So both land without anything in between.

Create the webhook once in Discord, under the channel's settings, then use the
same base URL with different suffixes.

## 1. Pull requests, from GitHub

No code and nothing in this repository. In the repository's webhook settings,
add the Discord URL with **`/github`** appended, content type
`application/json`, and select the events worth seeing. Pull requests, releases
and workflow runs are the useful ones; pushes to `main` are already visible
through everything else.

Worth knowing given how this repository works: Actions cannot open pull
requests here, so the upgrade and image-bump workflows push a branch and stop.
Those produce no pull request event. If the point is to see that an upgrade is
waiting, subscribe to **workflow run** events too, or the branch push will be
the only trace.

## 2. Node memory, disk and CPU, from DigitalOcean

`monitoring.tf`. Three `digitalocean_monitor_alert` policies scoped by the
`k8s:worker` tag, delivered to the Slack destination pointing at Discord.

    memory  > 85% for 5m
    disk    > 80% for 5m
    cpu     > 85% for 5m

Set `TF_VAR_discord_ops_webhook` to the Discord URL **with `/slack` appended**.
Until it is set every policy is `count = 0`, so the configuration plans clean
with no secret.

Scoped by tag on purpose. DOKS replaces a node and its ID changes, and a policy
pinned to a dead droplet is worse than no policy because it still looks
configured.

Two older policies already exist, both email-only and both unmanaged by
Terraform: CPU and memory, each above 90% over 30 minutes, against every droplet
in the account. They are deliberately left alone. Importing them would make this
file the owner of alerts that predate it.

**This does not cover the managed databases.** `/v2/databases/{id}/alerts`
returns 404 and the monitoring API models droplets and load balancers only.
Postgres was at 82GB of 120GB on 2026-09-13, which is the number that most wants
an alert and the one DigitalOcean will not provide an API for. A cronjob that
queries `pg_database_size` and posts to the same webhook would work, following
`k8s/apps/cronjobs/timeline-health-check.yaml`.

## 3. Load balancer failover, from Cloudflare

    ./scripts/cloudflare-apply.py --apply lb-failover-alert

Reads `DISCORD_OPS_WEBHOOK` from the environment, with `/slack` appended. Needs
a Cloudflare token with **Account → Notifications → Edit**.

It creates two things, because Cloudflare models the destination separately from
the policy: a webhook destination named `discord-ops`, then a
`load_balancing_health_alert` policy pointing at it. Both are matched by name
first, so re-running does nothing.

This closes a finding. Failover is silent today:
both pools carry an empty notification address and none of the account's three
notification policies is a load balancing alert. Half the serving capacity can
disappear with nothing saying so, and the surviving cluster is the one that
cannot carry full traffic alone.

## What each one costs if the URL leaks

A Discord webhook URL is a credential. Anyone holding it can post to the channel
as the integration; they cannot read it. Keep it in GitHub secrets and in
`terraform.tfvars`, never in a manifest.

Terraform's `sensitive = true` keeps it out of plan and apply output. It does not
keep it out of state, which lives in the private Spaces bucket alongside every
other secret here. Same trust boundary, stated so nobody assumes otherwise.
