# Careful with changes here. It will probably drop the whole cluster
# TODO: IAC 
resource "digitalocean_kubernetes_cluster" "mastodon_k8s" {
  name   = "mastodon-k8s-production"
  region = var.region
  # Grab the latest version slug from `doctl kubernetes options versions`
  version = "1.30.2-do.0"
  registry_integration = true

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-4gb"
    node_count = 2
  }
}

# Create a new container registry
resource "digitalocean_container_registry" "mastodon_k8s" {
  name                   = "mastodon-reg-production"
  subscription_tier_slug = "starter"
  region = "nyc3" # nyc1 isn't supported?! ugh
}

# resource "digitalocean_container_registry_docker_credentials" "mastodon_k8s" {
#   registry_name = digitalocean_container_registry.mastodon_k8s.name
# }

# provider "kubernetes" {
#   host  = data.digitalocean_kubernetes_cluster.mastodon_k8s.endpoint
#   token = data.digitalocean_kubernetes_cluster.mastodon_k8s.kube_config[0].token
#   cluster_ca_certificate = base64decode(
#     data.digitalocean_kubernetes_cluster.mastodon_k8s.kube_config[0].cluster_ca_certificate
#   )
# }

# resource "kubernetes_secret" "mastodon_k8s" {
#   metadata {
#     name = "docker-cfg"
#   }

#   data = {
#     ".dockerconfigjson" = digitalocean_container_registry_docker_credentials.mastodon_k8s.docker_credentials
#   }

#   type = "kubernetes.io/dockerconfigjson"
# }