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