data "digitalocean_kubernetes_versions" "mastodon" {}

# Careful with changes here. It will probably drop the whole cluster
resource "digitalocean_kubernetes_cluster" "mastodon_k8s" {
  name   = "mastodon-k8s-production"
  region = var.region
  auto_upgrade = true
  # Grab the latest version slug from `doctl kubernetes options versions`
  version = "1.32.10-do.2"
  #version = data.digitalocean_kubernetes_versions.mastodon.latest_version
  registry_integration = true

  maintenance_policy {
    start_time = "03:00"
    day        = "monday"
  }

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-4gb"
    node_count = 3
  }

  # Guardrail for the slow reconciliation described in
  # docs/terraform-reconciliation.md. This resource cannot be recreated without
  # data loss or a rebuild, so any plan that would destroy or replace it must
  # fail loudly instead of proceeding. Removing this line is a deliberate act.
  lifecycle {
    prevent_destroy = true

    # auto_upgrade is true, so DigitalOcean owns this attribute. It moved the
    # cluster to 1.33.12-do.3 on 2026-07-27 while this file still pinned
    # 1.32.10-do.2. Terraform then read the config as authoritative and planned
    # a downgrade, which forces replacement: any apply, including one targeting
    # an unrelated database firewall that depends on this cluster, would have
    # destroyed and recreated production. Measured 2026-09-03.
    #
    # Ignoring version here means Terraform tracks whatever DO upgraded to. To
    # drive an upgrade from Terraform instead, remove this line and set
    # auto_upgrade = false, or the two will fight.
    ignore_changes = [version]
  }
}
