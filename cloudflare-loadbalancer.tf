### The load balancer in front of masto.nyc, adopted from what exists.
###
### It steers between two pools, each a single origin behind its own tunnel:
### web-large is the bare metal box, web-small is do-production. steering_policy
### is off, so it is plain failover in pool order with web-small as the
### fallback.
###
### The monitor probes /health every 60 seconds expecting a 200 and the body OK,
### sending Host: masto.nyc so the tunnel ingress matches.
###
### notification_email is empty on both pools, which is why a pool going
### unhealthy fails over in silence. Setting it, or adding a
### load_balancing_health_alert notification policy, needs a token with write
### access and is the first thing worth doing once there is one.

import {
  to = cloudflare_load_balancer_monitor.masto
  id = "d5b597054872147b35d4d70517848002/a0db454d492b8ff298f524be6f634369"
}

import {
  to = cloudflare_load_balancer_pool.web_large
  id = "d5b597054872147b35d4d70517848002/84299024161d308c818091ae2692152c"
}

import {
  to = cloudflare_load_balancer_pool.web_small
  id = "d5b597054872147b35d4d70517848002/ba78b11a2507c11ccd3d17035d64b801"
}

import {
  to = cloudflare_load_balancer.masto
  id = "5559ff186e4f4046b263d8eed2c6e1a3/407c5326c71a95a6b231e4b590ff6434"
}

resource "cloudflare_load_balancer_pool" "web_large" {
  account_id         = local.cf_account_id
  check_regions      = ["ENAM"]
  description        = "bricks and mortars "
  enabled            = true
  health_sources     = null
  latitude           = null
  load_shedding      = null
  longitude          = null
  minimum_origins    = 1
  monitor            = "a0db454d492b8ff298f524be6f634369"
  monitor_group      = null
  name               = "web-large"
  notification_email = ""
  notification_filter = {
    origin = null
    pool = {
      disable = null
      healthy = null
    }
  }
  origin_steering = null
  origins = [
    {
      address       = "large.masto.nyc"
      enabled       = true
      flatten_cname = true
      header = {
        host = ["masto.nyc"]
      }
      name               = "large"
      port               = null
      virtual_network_id = null
      weight             = 1
    },
  ]
}

resource "cloudflare_load_balancer_pool" "web_small" {
  account_id         = local.cf_account_id
  check_regions      = ["ENAM"]
  description        = "docean "
  enabled            = true
  health_sources     = null
  latitude           = null
  load_shedding      = null
  longitude          = null
  minimum_origins    = 1
  monitor            = "a0db454d492b8ff298f524be6f634369"
  monitor_group      = null
  name               = "web-small"
  notification_email = ""
  notification_filter = {
    origin = null
    pool = {
      disable = null
      healthy = null
    }
  }
  origin_steering = {
    policy = "random"
  }
  origins = [
    {
      address       = "small.masto.nyc"
      enabled       = true
      flatten_cname = true
      header = {
        host = ["masto.nyc"]
      }
      name               = "small"
      port               = null
      virtual_network_id = null
      weight             = 1
    },
  ]
}

resource "cloudflare_load_balancer_monitor" "masto" {
  account_id       = "d5b597054872147b35d4d70517848002"
  allow_insecure   = false
  consecutive_down = null
  consecutive_up   = null
  description      = "masto"
  expected_body    = "OK"
  expected_codes   = "200"
  follow_redirects = false
  header = {
    Host = ["masto.nyc"]
  }
  interval   = 60
  method     = "GET"
  path       = "/health"
  port       = 80
  probe_zone = ""
  retries    = 2
  timeout    = 1
  type       = "http"
}

resource "cloudflare_load_balancer" "masto" {
  adaptive_routing = {
    failover_across_pools = false
  }
  country_pools = null
  default_pools = ["84299024161d308c818091ae2692152c", "ba78b11a2507c11ccd3d17035d64b801"]
  description   = "lb testing"
  enabled       = true
  fallback_pool = "ba78b11a2507c11ccd3d17035d64b801"
  location_strategy = {
    mode       = "pop"
    prefer_ecs = "proximity"
  }
  name      = "masto.nyc"
  networks  = ["cloudflare"]
  pop_pools = {}
  proxied   = true
  random_steering = {
    default_weight = 1
    pool_weights   = null
  }
  region_pools     = {}
  rules            = null
  session_affinity = "cookie"
  session_affinity_attributes = {
    drain_duration         = 0
    headers                = null
    require_all_headers    = null
    samesite               = "Auto"
    secure                 = "Auto"
    zero_downtime_failover = "none"
  }
  session_affinity_ttl = 82800
  steering_policy      = "off"
  ttl                  = null
  zone_id              = "5559ff186e4f4046b263d8eed2c6e1a3"
}
