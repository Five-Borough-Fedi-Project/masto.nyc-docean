### DigitalOcean alert policies, delivered to Discord.
###
### Discord accepts Slack-formatted payloads on a webhook URL with `/slack`
### appended, and DigitalOcean's only webhook-shaped destination is its Slack
### one. That pairing is why these need no translator, no Worker and no service
### in the middle. Set var.discord_ops_webhook to the Discord webhook URL WITH
### `/slack` on the end.
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
  discord_enabled = var.discord_ops_webhook != "" ? 1 : 0
}

### Memory. The nodes are 3Gi of allocatable memory and have run at 93% of
### requests. This fires on actual utilisation rather than on requests, so it is
### a different signal from the scheduling pressure in docs/cluster-capacity.md.
resource "digitalocean_monitor_alert" "node_memory" {
  count = local.discord_enabled
  alerts {
    slack {
      channel = "ops"
      url     = var.discord_ops_webhook
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
      url     = var.discord_ops_webhook
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
      url     = var.discord_ops_webhook
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
