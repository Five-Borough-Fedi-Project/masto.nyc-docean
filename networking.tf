resource "digitalocean_vpc" "mastodon_private" {
  name     = "mastodon-private"
  region   = var.region
  ip_range = "10.116.0.0/20"
}