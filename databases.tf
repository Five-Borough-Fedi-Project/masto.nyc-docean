################## POSTGRES ##################

resource "digitalocean_database_cluster" "mastodon-pg-production" {
  name       = "mastodon-pg-production"
  engine     = "pg"
  version    = "16"
  size       = "db-s-2vcpu-4gb"
  region     = "nyc1"
  node_count = 1
}

resource "digitalocean_database_db" "mastodon-production" {
  cluster_id = digitalocean_database_cluster.mastodon-pg-production.id
  name       = "mastodon_production"
}

resource "digitalocean_database_user" "mastodon-production" {
  cluster_id = digitalocean_database_cluster.mastodon-pg-production.id
  name       = "mastodon"
}

################## REDIS ##################

resource "digitalocean_database_cluster" "mastodon-redis-production" {
  name       = "mastodon-redis-production"
  engine     = "redis"
  version    = "7"
  size       = "db-s-1vcpu-1gb"
  region     = "nyc1"
  node_count = 1
}

resource "digitalocean_database_redis_config" "mastodon-production" {
  cluster_id             = digitalocean_database_cluster.mastodon-redis-production.id
  timeout                = 90
}

################## OPENSEARCH ##################

resource "digitalocean_database_cluster" "mastodon-os-production" {
  name       = "mastodon-os-production"
  engine     = "opensearch"
  version    = "2"
  size       = "db-s-1vcpu-2gb"
  region     = "nyc1"
  node_count = 1
}