variable "region" {
 type        = string
 description = "Preferred region for all infra"
 default     = "nyc1"
 sensitive   = false
}

variable "masto_ns" {
 type        = string
 description = "Default namespace for masto.nyc infra"
 default     = "mastodon"
 sensitive   = false
}
### Public egress IPs of the mastodon-large bare-metal nodes.
###
### digitalocean_database_firewall is AUTHORITATIVE: it reconciles the entire
### rule set for a database, not just the rules Terraform created. Any IP added
### through the DO console is deleted on the next apply. Since mastodon-large
### reaches Postgres, Valkey and OpenSearch over their public hostnames, those
### IPs have to live here or the web tier loses its database.
###
### Left empty by default so that an apply from a workstation that has not set
### this cannot silently remove rules it does not know about -- an empty list
### adds no rules, it does not delete existing ones. Populate it (in tfvars, or
### TF_VAR_large_node_ips in CI) BEFORE enabling automated apply.
variable "large_node_ips" {
  type        = list(string)
  description = "Public IPs of mastodon-large nodes, allowed through the managed database firewalls"
  default     = []
  sensitive   = false
}
