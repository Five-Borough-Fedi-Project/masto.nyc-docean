data "digitalocean_kubernetes_versions" "mastodon" {}

# Careful with changes here. It will probably drop the whole cluster
resource "digitalocean_kubernetes_cluster" "mastodon_k8s" {
  name   = "mastodon-k8s-production"
  region = var.region
  auto_upgrade = true
  # Grab the latest version slug from `doctl kubernetes options versions`
  version = data.digitalocean_kubernetes_versions.mastodon.latest_version
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
}

# Create a new container registry
resource "digitalocean_container_registry" "mastodon_k8s" {
  name                   = "mastodon-reg-production"
  subscription_tier_slug = "starter"
  region = "nyc3" # nyc1 isn't supported?! ugh
}
