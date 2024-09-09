
resource "kubernetes_secret" "mastodon_direct_db" {
  metadata {
    name = "masto-direct-db"
    namespace = var.masto_ns
  }

  data = {
    "postgres_host" = digitalocean_database_cluster.mastodon_pg.private_host
    "postgres_port" = digitalocean_database_cluster.mastodon_pg.port
    "postgres_db" = digitalocean_database_db.mastodon_pg.name
    "postgres_user" = digitalocean_database_user.mastodon_pg.name
    "postgres_pass" = digitalocean_database_user.mastodon_pg.password
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
    "DB_HOST" = digitalocean_database_connection_pool.mastodon_pg.private_host
    "DB_NAME" = digitalocean_database_connection_pool.mastodon_pg.db_name
    "DB_PORT" = digitalocean_database_connection_pool.mastodon_pg.port
    "DB_USER" = digitalocean_database_user.mastodon_pg.name
    "DB_PASS" = digitalocean_database_user.mastodon_pg.password
    "ES_HOST" = format("https://%s", digitalocean_database_cluster.mastodon_os.private_host)
    "ES_PORT" = digitalocean_database_cluster.mastodon_os.port
    "ES_USER" = digitalocean_database_cluster.mastodon_os.ui_user
    "ES_PASS" = digitalocean_database_cluster.mastodon_os.ui_password
    "REDIS_URL" = format("redis://%s:%s@haproxy-redis.mastodon:6379", digitalocean_database_cluster.mastodon_redis.user, digitalocean_database_cluster.mastodon_redis.password)
    # waiting on this to be included on a release:
    # https://github.com/mastodon/mastodon/pull/30717
    # "REDIS_URL" = format(
    #   "rediss://%s:%s@%s:%s", 
    #   digitalocean_database_cluster.mastodon_redis.user, 
    #   digitalocean_database_cluster.mastodon_redis.password,
    #   digitalocean_database_cluster.mastodon_redis.private_host,
    #   digitalocean_database_cluster.mastodon_redis.port
    # )
    "TRUSTED_PROXY_IP" = "10.0.0.0/8"
  }
}

resource "kubernetes_config_map" "mastodon_env_ha_tf" {
  metadata {
    name = "mastodon-haproxy-env-tf"
    namespace = var.masto_ns
  }

  data = {
    "REDIS_HOST" = digitalocean_database_cluster.mastodon_redis.private_host
    "REDIS_PORT" = digitalocean_database_cluster.mastodon_redis.port
  }
}