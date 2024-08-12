terraform {
required_version = ">= 1.6.3"
  backend "s3" {
    endpoints = {
      s3 = "https://nyc3.digitaloceanspaces.com" // only nyc3 supported in ny
    }

    bucket = var.state_bucket
    key    = var.state_key

    # Deactivate a few AWS-specific checks
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    region                      = "us-east-1"
  }
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}
provider "kubernetes" {
  host  = digitalocean_kubernetes_cluster.mastodon_k8s.endpoint
  token = digitalocean_kubernetes_cluster.mastodon_k8s.kube_config[0].token
  cluster_ca_certificate = base64decode(
    digitalocean_kubernetes_cluster.mastodon_k8s.kube_config[0].cluster_ca_certificate
  )
}

variable "do_token" {}
variable "state_bucket" {}
variable "state_key" {}

provider "digitalocean" {
  token = var.do_token
}
