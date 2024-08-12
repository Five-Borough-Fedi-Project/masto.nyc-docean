
resource "kubernetes_secret" "mastodon_redis" {
  metadata {
    name = "masto-redis"
    namespace = var.masto_ns
  }

  data = {
    "private_host_and_port" = format("%s:%s", digitalocean_database_cluster.mastodon_redis.private_host, digitalocean_database_cluster.mastodon_redis.port)
    "private_host" = digitalocean_database_cluster.mastodon_redis.private_host
    "private_uri" = digitalocean_database_cluster.mastodon_redis.private_uri
    "port" = digitalocean_database_cluster.mastodon_redis.port
  }

  type = "Opaque"
}

resource "kubernetes_config_map" "mastodon_env_tf" {
  metadata {
    name = "mastodon-env-tf"
    namespace = var.masto_ns
  }

  data = {
    "ALLOWED_PRIVATE_ADDRESSES" = digitalocean_vpc.mastodon_private.ip_range
    "DB_HOST" = digitalocean_database_cluster.mastodon_pg.private_host
    "DB_NAME" = digitalocean_database_db.mastodon_pg.name
    "DB_PORT" = digitalocean_database_cluster.mastodon_pg.port
    "DB_USER" = digitalocean_database_user.mastodon_pg.name
    "DB_PASS" = digitalocean_database_user.mastodon_pg.password
    "ES_HOST" = format("https://%s", digitalocean_database_cluster.mastodon_os.private_host)
    "ES_PORT" = digitalocean_database_cluster.mastodon_os.port
    "ES_USER" = digitalocean_database_cluster.mastodon_os.ui_user
    "ES_PASS" = digitalocean_database_cluster.mastodon_os.ui_password
    "REDIS_URL" = format("redis://%s:%s@stunnel.mastodon:6379", digitalocean_database_cluster.mastodon_redis.user, digitalocean_database_cluster.mastodon_redis.password)
    "TRUSTED_PROXY_IP" = digitalocean_vpc.mastodon_private.ip_range
  }

}