################## POSTGRES ##################

resource "digitalocean_database_cluster" "mastodon_pg" {
  name       = "mastodon-pg-production"
  engine     = "pg"
  version    = "16"
  size       = "db-s-2vcpu-4gb"
  region     = var.region
  node_count = 1
  private_network_uuid = digitalocean_vpc.mastodon_private.id
  maintenance_window {
    day  = "monday"
    hour = "03:00:00"
  }
}

resource "digitalocean_database_db" "mastodon_pg" {
  cluster_id = digitalocean_database_cluster.mastodon_pg.id
  name       = "mastodon_production"
}

resource "digitalocean_database_user" "mastodon_pg" {
  cluster_id = digitalocean_database_cluster.mastodon_pg.id
  name       = "mastodon"
}

### This is kinda fucky. When I use it, the UI gets kinda messed up and sql connections
### can't find the database.
# resource "digitalocean_database_connection_pool" "mastodon_pg" {
#   cluster_id = digitalocean_database_cluster.mastodon_pg.id
#   name       = "mastodon"
#   mode       = "transaction"
#   size       = 97 # This is the max for the db-s-2vcpu-4gb size
#   db_name    = digitalocean_database_db.mastodon_pg.name
#   user       = digitalocean_database_user.mastodon_pg.name
# }

################## REDIS ##################

resource "digitalocean_database_cluster" "mastodon_redis" {
  name       = "mastodon-redis-production"
  engine     = "redis"
  version    = "7"
  size       = "db-s-1vcpu-1gb"
  region     = var.region
  node_count = 1
  private_network_uuid = digitalocean_vpc.mastodon_private.id
  maintenance_window {
    day  = "monday"
    hour = "03:00:00"
  }
}

resource "digitalocean_database_redis_config" "mastodon_redis" {
  cluster_id             = digitalocean_database_cluster.mastodon_redis.id
  ssl = true # CHANGE THIS AFTER MIGRATION
  persistence = "rdb"
  maxmemory_policy = "noeviction" # This is the reccomended config for sidekiq
  timeout                = 90
}

################## OPENSEARCH ##################

resource "digitalocean_database_cluster" "mastodon_os" {
  name       = "mastodon-os-production"
  engine     = "opensearch"
  version    = "2"
  size       = "db-s-1vcpu-2gb"
  region     = var.region
  node_count = 1
  private_network_uuid = digitalocean_vpc.mastodon_private.id
  maintenance_window {
    day  = "monday"
    hour = "03:00:00"
  }
}