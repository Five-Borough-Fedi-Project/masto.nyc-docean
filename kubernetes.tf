resource "digitalocean_kubernetes_cluster" "mastodon_k8s" {
  name   = "mastodon-k8s-production"
  region = var.region
  # Grab the latest version slug from `doctl kubernetes options versions`
  version = "1.30.2-do.0"
  registry_integration = true

  node_pool {
    name       = "worker-pool"
    size       = "s-1vcpu-2gb"
    node_count = 2
  }
}

# Create a new container registry
resource "digitalocean_container_registry" "mastodon_k8s" {
  name                   = "mastodon-reg-production"
  subscription_tier_slug = "starter"
  region = "nyc3" # nyc1 isn't supported?! ugh
}
