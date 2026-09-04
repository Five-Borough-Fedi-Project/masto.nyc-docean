resource "digitalocean_vpc" "mastodon_private" {
  name     = "mastodon-private"
  region   = var.region
  ip_range = "10.116.0.0/20"

  # Guardrail for the slow reconciliation described in
  # docs/terraform-reconciliation.md. This resource cannot be recreated without
  # data loss or a rebuild, so any plan that would destroy or replace it must
  # fail loudly instead of proceeding. Removing this line is a deliberate act.
  lifecycle {
    prevent_destroy = true
  }
}
