terraform {
### OpenTofu only, and >= 1.8 specifically. The backend block below references
### var.state_bucket / var.state_key, and variables in backend configuration
### landed in OpenTofu 1.8 (opentofu/opentofu#388). HashiCorp Terraform does
### not support it at any version -- `terraform init` will reject this file.
### The last recorded state write was from OpenTofu 1.8.1.
required_version = ">= 1.8.0"
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
