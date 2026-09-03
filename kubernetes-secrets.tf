### Credentials handed from Terraform to Kubernetes.
###
### These were ConfigMaps until 2026-08. That was wrong twice over: ConfigMap
### values appear in `kubectl describe` and in events, and -- because the
### provider does not mark them sensitive -- they render in cleartext in
### `tofu plan` output. This repo is public, so a plan running in CI would have
### printed the database password into a world-readable Actions log.
### kubernetes_secret_v1 renders as "(sensitive value)".
###
### STAGED ROLLOUT. The ConfigMaps below are deliberately kept for one release
### so that a pod restarting mid-migration still finds its envFrom target. A
### Secret and a ConfigMap may share a name; they are different API resources.
###
###   1. tofu apply           -- creates the Secrets, ConfigMaps still present
###   2. kubectl apply + roll -- workloads switch to secretRef
###   3. delete the marked block below, tofu apply again
###
### Do not skip to step 3. A pod whose configMapRef target has been deleted
### fails to start with CreateContainerConfigError.

################## SECRETS (step 1) ##################

resource "kubernetes_secret_v1" "mastodon_direct_db" {
  metadata {
    name      = "masto-direct-db"
    namespace = var.masto_ns
  }

  type = "Opaque"

  data = {
    "postgres_host" = digitalocean_database_cluster.mastodon_pg.private_host
    "postgres_port" = digitalocean_database_cluster.mastodon_pg.port
    "postgres_db"   = digitalocean_database_db.mastodon_pg.name
    "postgres_user" = digitalocean_database_user.mastodon_pg.name
    "postgres_pass" = digitalocean_database_user.mastodon_pg.password
  }
}

resource "kubernetes_secret_v1" "mastodon_env_tf" {
  metadata {
    name      = "mastodon-env-tf"
    namespace = var.masto_ns
  }

  type = "Opaque"

  data = {
    "ALLOWED_PRIVATE_ADDRESSES" = digitalocean_vpc.mastodon_private.ip_range
    "DB_HOST"                   = digitalocean_database_connection_pool.mastodon_pg.private_host
    "DB_NAME"                   = digitalocean_database_connection_pool.mastodon_pg.db_name
    "DB_PORT"                   = digitalocean_database_connection_pool.mastodon_pg.port
    "DB_USER"                   = digitalocean_database_user.mastodon_pg.name
    "DB_PASS"                   = digitalocean_database_user.mastodon_pg.password
    "ES_HOST"                   = format("https://%s", digitalocean_database_cluster.mastodon_os.private_host)
    "ES_PORT"                   = digitalocean_database_cluster.mastodon_os.port
    "ES_USER"                   = digitalocean_database_cluster.mastodon_os.ui_user
    "ES_PASS"                   = digitalocean_database_cluster.mastodon_os.ui_password
    "REDIS_URL" = format(
      "rediss://%s:%s@%s:%s",
      digitalocean_database_cluster.mastodon_redis.user,
      digitalocean_database_cluster.mastodon_redis.password,
      digitalocean_database_cluster.mastodon_redis.private_host,
      digitalocean_database_cluster.mastodon_redis.port
    )
    "TRUSTED_PROXY_IP" = "10.0.0.0/8"
  }
}

################## LEGACY CONFIGMAPS -- DELETE AT STEP 3 ##################
### Everything between here and the end marker is superseded by the Secrets
### above. Delete this block once the workloads have been rolled onto
### secretRef and `kubectl -n mastodon get pods` is fully healthy.

resource "kubernetes_config_map_v1" "mastodon_direct_db" {
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
}

resource "kubernetes_config_map_v1" "mastodon_env_tf" {
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
    "REDIS_URL" = format(
      "rediss://%s:%s@%s:%s", 
      digitalocean_database_cluster.mastodon_redis.user, 
      digitalocean_database_cluster.mastodon_redis.password, 
      digitalocean_database_cluster.mastodon_redis.private_host, 
      digitalocean_database_cluster.mastodon_redis.port
    )
    "TRUSTED_PROXY_IP" = "10.0.0.0/8"
  }
}

################## END OF BLOCK TO DELETE AT STEP 3 ##################

### Not a credential -- a hostname and a port -- so this stays a ConfigMap.
### Note nothing in kubernetes/ currently references it; it appears to be
### vestigial from the haproxy setup. Left in place rather than destroyed.
resource "kubernetes_config_map_v1" "mastodon_env_ha_tf" {
  metadata {
    name = "mastodon-haproxy-env-tf"
    namespace = var.masto_ns
  }

  data = {
    "REDIS_HOST" = digitalocean_database_cluster.mastodon_redis.private_host
    "REDIS_PORT" = digitalocean_database_cluster.mastodon_redis.port
  }
}

moved {
  from = kubernetes_config_map.mastodon_direct_db
  to   = kubernetes_config_map_v1.mastodon_direct_db
}

moved {
  from = kubernetes_config_map.mastodon_env_tf
  to   = kubernetes_config_map_v1.mastodon_env_tf
}

moved {
  from = kubernetes_config_map.mastodon_env_ha_tf
  to   = kubernetes_config_map_v1.mastodon_env_ha_tf
}
