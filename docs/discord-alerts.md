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

**Discord's `/github` endpoint renders only a subset of GitHub's events.** It
handles the familiar ones, pull requests, issues, pushes, releases, reviews, and
silently accepts and drops the rest. Anything workflow or deployment shaped
should be assumed not to arrive until seen to arrive.

That matters twice here. Actions cannot open pull requests in this
organisation, so the upgrade and image-bump workflows push a branch and stop,
producing no pull request event at all. And a waiting approval is a deployment
event, which is the category least likely to render.

Both are covered by posting Slack-shaped JSON ourselves instead, which is a
format we control. See section 4.

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

## 4. A waiting approval, from the terraform workflow

`terraform.yaml` gained a `notify-pending` job. When a push to `main` produces a
plan with changes, it posts the plan summary, the commit and a link to the run.

    **OpenTofu apply is waiting for approval**
    Plan: 3 to add, 0 to change, 0 to destroy.
    commit `abcdef1` by seano-vs
    https://github.com/.../actions/runs/...

The `apply` job carries `environment: production`, so it waits for a reviewer.
The gate is the point, and an approval nobody knows about is a stalled deploy:
one sat waiting overnight on 2026-09-15.

Three decisions worth knowing:

- **A job, where a GitHub webhook event would have been the obvious choice.**
  Deployment reviews sit in the category Discord's `/github` endpoint does not
  render, so subscribing would have been silent. This posts to `/slack`, whose
  format we control.
- **It depends on `plan` alone**, so it runs beside `apply` while `apply` waits
  instead of behind it. Making `apply` depend on it would let a Discord outage
  block infrastructure changes.
- **The URL is normalised.** The same secret feeds DigitalOcean's alert
  policies, where it has to end in `/slack`. The job strips a trailing `/slack`
  or `/github` and appends `/slack`, so it works whichever way the secret was
  stored.

A non-200 from Discord logs a warning and exits 0. The approval is still
waiting; failing the run would add a red X that means nothing.

## What each one costs if the URL leaks

A Discord webhook URL is a credential. Anyone holding it can post to the channel
as the integration; they cannot read it. Keep it in GitHub secrets and in
`terraform.tfvars`, never in a manifest.

Terraform's `sensitive = true` keeps it out of plan and apply output. It does not
keep it out of state, which lives in the private Spaces bucket alongside every
other secret here. Same trust boundary, stated so nobody assumes otherwise.
