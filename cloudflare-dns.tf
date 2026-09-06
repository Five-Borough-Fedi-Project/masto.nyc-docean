### The four DNS records that carry service traffic, adopted from what exists.
###
### Everything else in the zone stays out for now: DKIM, SPF, DMARC, MX and the
### R2 CDN names. They are stable, unrelated to this infrastructure, and
### twenty-three more records is churn without benefit. They can follow.
###
### masto.nyc and streaming.masto.nyc both point at the masto-nyc tunnel.
### large and small point at their own tunnels and exist to be load balancer
### origins; a direct request to either returns 404, because the tunnel ingress
### only matches masto.nyc and streaming.masto.nyc. The load balancer's monitor
### sends Host: masto.nyc, which is why it sees 200 where curl sees 404.

import {
  to = cloudflare_dns_record.apex
  id = "5559ff186e4f4046b263d8eed2c6e1a3/cf30df8c23976315ec184757171383d5"
}

import {
  to = cloudflare_dns_record.streaming
  id = "5559ff186e4f4046b263d8eed2c6e1a3/d38544a748bcf60e2c65a420f3023ddc"
}

import {
  to = cloudflare_dns_record.large
  id = "5559ff186e4f4046b263d8eed2c6e1a3/7591c8a590ba6f1a3a26d42c11bf3a2c"
}

import {
  to = cloudflare_dns_record.small
  id = "5559ff186e4f4046b263d8eed2c6e1a3/fb897f2d902a6b2d848ad3d82f46b98c"
}

resource "cloudflare_dns_record" "large" {
  comment         = null
  content         = "eecbc4eb-e6c3-4f54-83a5-da0b30dee90a.cfargotunnel.com"
  data            = null
  name            = "large.masto.nyc"
  priority        = null
  private_routing = null
  proxied         = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = local.cf_zone_id
}

resource "cloudflare_dns_record" "small" {
  comment         = null
  content         = "1c39cca4-873a-4678-b614-450fda9f81a9.cfargotunnel.com"
  data            = null
  name            = "small.masto.nyc"
  priority        = null
  private_routing = null
  proxied         = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = local.cf_zone_id
}

resource "cloudflare_dns_record" "apex" {
  comment         = null
  content         = "37c23069-2c21-413b-917e-3c618d4e05ef.cfargotunnel.com"
  data            = null
  name            = "masto.nyc"
  priority        = null
  private_routing = null
  proxied         = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = local.cf_zone_id
}

resource "cloudflare_dns_record" "streaming" {
  comment         = null
  content         = "37c23069-2c21-413b-917e-3c618d4e05ef.cfargotunnel.com"
  data            = null
  name            = "streaming.masto.nyc"
  priority        = null
  private_routing = null
  proxied         = true
  settings = {
    flatten_cname = false
    ipv4_only     = false
    ipv6_only     = false
  }
  tags    = []
  ttl     = 1
  type    = "CNAME"
  zone_id = local.cf_zone_id
}
