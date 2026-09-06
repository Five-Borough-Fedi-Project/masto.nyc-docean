### Cloudflare, declared but not yet managing anything. Issue #11.
###
### The zone in front of masto.nyc carries load balancing with health checks,
### DNS, tunnel routes and the cache. None of it is in version control, and the
### health checks currently fail the `large` pool over in silence, so losing half
### the capacity produces no signal at all.
###
### Nothing here creates or changes anything. The provider is declared, the
### credentials are variables that default to empty, and no resource references
### it, so `tofu plan` runs exactly as it did before. Adopting the existing
### objects means `import` blocks written against a real inventory, the same way
### the DigitalOcean resources were brought in without touching the cloud side.
###
### To take the next step, supply a read-only token and inventory what exists:
###
###   Zone:Read, DNS:Read, Load Balancing:Read
###   Account -> Notifications:Read   for the health alert policy
###   Zone:Cache Purge                only when the upgrade purge is wired up
###
### The token is a credential like any other here: never committed, supplied as
### TF_VAR_cloudflare_api_token from a GitHub Actions secret.

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token. Empty until issue #11 begins; no resource reads it yet."
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Zone ID for masto.nyc. Empty until issue #11 begins."
  default     = ""
  sensitive   = true
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

### Identifiers, not credentials. They appear in every API call this repository
### makes and are derivable from the domain name.
locals {
  cf_zone_id    = "5559ff186e4f4046b263d8eed2c6e1a3"
  cf_account_id = "d5b597054872147b35d4d70517848002"
}
