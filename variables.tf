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
### Marked sensitive, and it matters more than the usual reasons. mastodon-large
### sits behind a Cloudflare tunnel so that its origin address is never public;
### that is the whole point of running cloudflared there. Phase 6 of the roadmap
### runs `tofu plan` in GitHub Actions, this repo is public, and Actions logs are
### world-readable. An unmarked value would print the origin IP into a public log
### and undo the tunnel, handing anyone a way to reach the box directly and skip
### Cloudflare entirely.
###
### Supply it, never commit it:
###   locally  terraform.tfvars, which is gitignored
###   in CI    TF_VAR_large_node_ips, from a GitHub Actions secret
###
### sensitive = true redacts plan and apply output. It does NOT redact state, so
### the address is readable to anyone who can read the Spaces state bucket. That
### bucket is private, and the Spaces keys guarding it are worth treating as
### carefully as the database password.
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
  sensitive   = true
}
