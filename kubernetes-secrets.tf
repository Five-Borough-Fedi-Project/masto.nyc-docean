### Credentials handed from Terraform to Kubernetes.
###
### These were ConfigMaps until 2026-08. That was wrong twice over: ConfigMap
### values appear in `kubectl describe` and in events, and -- because the
### provider does not mark them sensitive -- they render in cleartext in
### `tofu plan` output. This repo is public, so a plan running in CI would have
### printed the database password into a world-readable Actions log.
### kubernetes_secret_v1 renders as "(sensitive value)".
###
### The staged rollout is complete. Secrets were created alongside the old
### ConfigMaps on 2026-09-04, every workload was rolled onto secretRef, and both
### clusters ran clean for a day before the ConfigMaps were removed. The overlap
### existed so that a pod restarting mid-migration still found its envFrom
### target; a pod whose configMapRef target has been deleted fails with
### CreateContainerConfigError.

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

### The Discord webhook, for workloads that need to say something.
###
### Everything else that posts to Discord does it from outside the cluster --
### the DigitalOcean alert policies in monitoring.tf, the Cloudflare policy, the
### terraform workflow -- so until now the URL never had to be in Kubernetes.
### sync-blocked-email-domains-watchdog is the first thing inside the cluster
### that needs it: CronJob failures stopped being visible anywhere when the log
### pipeline was removed on 2026-09-05.
###
### count follows local.discord_enabled, the same guard monitoring.tf uses, so
### with no webhook set this creates nothing and the watchdog's secretRef is
### declared optional. It still runs and still fails in the cluster; it just has
### nowhere to post.
###
### The URL is a credential. sensitive = true keeps it out of plan output but
### not out of state, which lives in the private Spaces bucket next to the
### database password. Same trust boundary, stated so nobody assumes otherwise.
### See docs/discord-alerts.md.
resource "kubernetes_secret_v1" "discord_ops_webhook" {
  count = local.discord_enabled

  metadata {
    name      = "discord-ops-webhook"
    namespace = var.masto_ns
  }

  type = "Opaque"

  data = {
    "url" = var.discord_ops_webhook
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
