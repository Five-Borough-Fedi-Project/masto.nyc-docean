################## POSTGRES ##################

resource "digitalocean_database_cluster" "mastodon_pg" {
  name       = "mastodon-pg-production"
  engine     = "pg"
  version    = "16"
  size       = "db-s-2vcpu-4gb"
  region     = var.region
  node_count = 1
  private_network_uuid = digitalocean_vpc.mastodon_private.id
  # This had to be raised to run pg
  storage_size_mib = 122880
  maintenance_window {
    day  = "thursday"
    hour = "03:00:00"
  }

  # Guardrail for the slow reconciliation described in
  # docs/terraform-reconciliation.md. This resource cannot be recreated without
  # data loss or a rebuild, so any plan that would destroy or replace it must
  # fail loudly instead of proceeding. Removing this line is a deliberate act.
  lifecycle {
    prevent_destroy = true
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

resource "digitalocean_database_connection_pool" "mastodon_pg" {
  cluster_id = digitalocean_database_cluster.mastodon_pg.id
  name       = digitalocean_database_db.mastodon_pg.name
  mode       = "transaction"
  size       = 85
  db_name    = digitalocean_database_db.mastodon_pg.name
  user = digitalocean_database_user.mastodon_pg.name
}

resource "digitalocean_database_firewall" "mastodon_pg" {
  cluster_id = digitalocean_database_cluster.mastodon_pg.id
  rule {
    type  = "k8s"
    value = digitalocean_kubernetes_cluster.mastodon_k8s.id
  }
  dynamic "rule" {
    for_each = var.large_node_ips
    content {
      type  = "ip_addr"
      value = rule.value
    }
  }
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
  engine     = "valkey"
  version    = "8"
  size       = "db-s-1vcpu-1gb"
  region     = var.region
  node_count = 1
  private_network_uuid = digitalocean_vpc.mastodon_private.id
  maintenance_window {
    day  = "tuesday"
    hour = "03:00:00"
  }

  # Guardrail for the slow reconciliation described in
  # docs/terraform-reconciliation.md. This resource cannot be recreated without
  # data loss or a rebuild, so any plan that would destroy or replace it must
  # fail loudly instead of proceeding. Removing this line is a deliberate act.
  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_database_valkey_config" "mastodon_redis" {
  cluster_id             = digitalocean_database_cluster.mastodon_redis.id
  timeout                = 90
}

resource "digitalocean_database_firewall" "mastodon_redis" {
  cluster_id = digitalocean_database_cluster.mastodon_redis.id
  rule {
    type  = "k8s"
    value = digitalocean_kubernetes_cluster.mastodon_k8s.id
  }
  dynamic "rule" {
    for_each = var.large_node_ips
    content {
      type  = "ip_addr"
      value = rule.value
    }
  }
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
    day  = "wednesday"
    hour = "03:00:00"
  }

  # Guardrail for the slow reconciliation described in
  # docs/terraform-reconciliation.md. This resource cannot be recreated without
  # data loss or a rebuild, so any plan that would destroy or replace it must
  # fail loudly instead of proceeding. Removing this line is a deliberate act.
  lifecycle {
    prevent_destroy = true

    # DigitalOcean manages the minor version. This file pins "2" while the
    # cluster reports "2.19", so Terraform plans a change on every run.
    # Updates in place rather than forcing replacement, so it is less dangerous
    # than the Kubernetes version drift, but still noise that hides real
    # changes. Measured 2026-09-03.
    ignore_changes = [version]
  }
}

resource "digitalocean_database_firewall" "mastodon_os" {
  cluster_id = digitalocean_database_cluster.mastodon_os.id
  rule {
    type  = "k8s"
    value = digitalocean_kubernetes_cluster.mastodon_k8s.id
  }
  dynamic "rule" {
    for_each = var.large_node_ips
    content {
      type  = "ip_addr"
      value = rule.value
    }
  }
}