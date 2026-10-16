### DigitalOcean alert policies, delivered to Discord.
###
### Discord accepts Slack-formatted payloads on a webhook URL with `/slack`
### appended, and DigitalOcean's only webhook-shaped destination is its Slack
### one. That pairing is why these need no translator, no Worker and no service
### in the middle. var.discord_ops_webhook may be set with or without the
### `/slack` suffix; local.discord_slack_url below normalises it.
###
### Scoped to the `k8s:worker` tag rather than to droplet IDs. DOKS replaces a
### node and its ID changes; the tag does not, and an alert policy pinned to a
### dead droplet is worse than no alert because it looks configured.
###
### Two policies already existed when this was written, both email-only and both
### unmanaged: droplet/cpu and droplet/memory_utilization_percent, each
### GreaterThan 90 over 30m against every droplet in the account. They are left
### alone deliberately. Importing them would mean this file owns Sean's existing
### email alerts, and adopting resources that predate the repository has caused
### enough trouble already. These are additive and scoped tighter.

locals {
  # Empty string disables every policy below, so this file is inert until the
  # secret exists. Terraform cannot conditionally omit a nested block, so the
  # count goes on the resource.
  #
  # Keyed on the raw variable rather than on the normalised URL below, because
  # normalising an empty string must not look like a configured webhook.
  discord_enabled = var.discord_ops_webhook != "" ? 1 : 0

  # DigitalOcean posts a Slack-shaped payload straight to this URL, so for
  # these three policies it has to end in `/slack`. Every other consumer of the
  # same secret -- the watchdog CronJob here, the blocklist sync in
  # sync-blocked-fedi-domains -- strips the suffix and re-appends it, so the
  # secret works for them whichever form it is in and this file was the only
  # strict one.
  #
  # That asymmetry cost two days. The secret's value changed on 2026-10-13 and
  # these policies drifted from state on every scheduled run afterwards, while
  # the strict format requirement lived only in a comment. A re-paste without
  # the suffix would not fail here -- it would quietly point every node alert
  # at a URL Discord 404s, which reads exactly like no alerts at all.
  #
  # Mirrors the shell in the watchdog step for step: drop a trailing slash,
  # then a `/slack` or `/github` suffix, then append `/slack`.
  discord_webhook_base = trimsuffix(trimsuffix(trimsuffix(var.discord_ops_webhook, "/"), "/slack"), "/github")
  discord_slack_url    = var.discord_ops_webhook == "" ? "" : "${local.discord_webhook_base}/slack"
}

### Memory. The nodes are 3Gi of allocatable memory and have run at 93% of
### requests. This fires on actual utilisation rather than on requests, so it is
### a different signal from the scheduling pressure in docs/cluster-capacity.md.
resource "digitalocean_monitor_alert" "node_memory" {
  count = local.discord_enabled
  alerts {
    slack {
      channel = "ops"
      url     = local.discord_slack_url
    }
  }
  window      = "5m"
  type        = "v1/insights/droplet/memory_utilization_percent"
  compare     = "GreaterThan"
  value       = 85
  enabled     = true
  tags        = ["k8s:worker"]
  description = "masto.nyc: a Kubernetes node is above 85% memory for 5 minutes"
}

### Disk. This is the one with a real precedent: LibreTranslate wrote 10.32GB to
### a node's writable layer with no ephemeral-storage accounting, and nothing
### would have said so until a node filled. See #98.
resource "digitalocean_monitor_alert" "node_disk" {
  count = local.discord_enabled
  alerts {
    slack {
      channel = "ops"
      url     = local.discord_slack_url
    }
  }
  window      = "5m"
  type        = "v1/insights/droplet/disk_utilization_percent"
  compare     = "GreaterThan"
  value       = 80
  enabled     = true
  tags        = ["k8s:worker"]
  description = "masto.nyc: a Kubernetes node is above 80% disk for 5 minutes"
}

### CPU, at a tighter window than the existing account-wide policy. 30 minutes
### above 90% is a report after the fact; 5 minutes is something to look at.
resource "digitalocean_monitor_alert" "node_cpu" {
  count = local.discord_enabled
  alerts {
    slack {
      channel = "ops"
      url     = local.discord_slack_url
    }
  }
  window      = "5m"
  type        = "v1/insights/droplet/cpu"
  compare     = "GreaterThan"
  value       = 85
  enabled     = true
  tags        = ["k8s:worker"]
  description = "masto.nyc: a Kubernetes node is above 85% CPU for 5 minutes"
}

### What this does NOT cover, so nobody assumes it does.
###
### The managed databases. /v2/databases/{id}/alerts returns 404 and the
### monitoring API only models droplets and load balancers, so Postgres disk is
### not alertable here at all. It was at 82GB of 120GB on 2026-09-13, which is
### the number that most wants an alert and is the one this cannot provide. A
### cronjob querying pg_database_size and posting to the same webhook is the
### shape that would work, following the timeline-health-check pattern.
