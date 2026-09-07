# Cloudflare, as it stood on 2026-09-06

A point-in-time reading of the masto.nyc zone and the account around it. Written
because none of this was in version control and nobody had looked at it as a
whole.

Nothing here is managed by Terraform. That was considered and set aside: managing
it means an apply can take the site off the internet, and the thing actually
wanted was to be able to read the configuration and find problems in it. See the
bottom of this file for how to regenerate the underlying data.

**Deliberately vague in places.** This repository is public. Exact WAF
expressions, rate limit thresholds, which paths are challenged, and the
mechanisms that bypass protection are all omitted, because writing them down
hands an attacker a map. Where a finding needs that detail to act on, it says
where to look in the dashboard instead.

## Shape

Traffic reaches Mastodon through Cloudflare, then a tunnel, then nginx, then
Rails. There is no open port anywhere; every origin dials out.

    masto.nyc ──► load balancer ──┬──► pool: bare metal ──► tunnel ──► nginx ──► web
                                  └──► pool: DigitalOcean ─► tunnel ──► nginx ──► web

The load balancer steers between two pools, one origin each, each behind its own
named tunnel. Steering is off, so it is plain failover in pool order with the
DigitalOcean pool as the fallback. Session affinity is by cookie.

Both pool origins are hostnames in this zone. A request to either directly
returns 404, because the tunnel's ingress rules only match the service
hostnames. The health monitor gets a 200 because it sends an explicit
Host header. That is worth knowing before concluding an origin is broken:

```sh
curl https://<pool-origin>/health                  # 404, and that is correct
curl -H 'Host: masto.nyc' https://<pool-origin>/health   # 200
```

The monitor checks `/health` every 60 seconds, expects a 200 and the body `OK`,
and retries twice.

Streaming has its own hostname pointing at the same tunnel as the apex. Media is
served from a separate hostname bound to an R2 bucket as a custom domain, and a
second bucket serves a custom error page. Three more Cloudflare-adjacent things
exist: a Pages project for a maintenance page, a handful of Workers, and a
default Access app unrelated to this service.

## Measurements

Cloudflare's GraphQL analytics, 48 hours to 2026-09-06. These are the numbers
that matter more than the settings, and they are cheap to re-take.

| host | requests | GB served | cache |
|---|---|---|---|
| apex | 5,337,640 | 46.0 | hit 59.2%, dynamic 38.0% |
| media CDN | 233,008 | 71.8 | hit 48.6%, **miss 40.1%** |
| a third-party API via a Worker | 20,009 | 0.0 | dynamic 99.8% |

TLS, same window:

| protocol | share |
|---|---|
| 1.3 | 97.887% |
| none, redirected to HTTPS | 2.079% |
| 1.2 | 0.034% |
| 1.0 and 1.1 | **zero** |

## Findings

### Tiered caching is off

The strongest finding, because it has a number attached. The media CDN misses
40% of the time on objects served with `max-age=315576000, immutable`. Immutable
content should approach a full hit rate once warm.

Without tiered caching each Cloudflare data centre keeps its own cache, so the
same object misses independently in every location a user lands in. It is free
on this plan. Re-take the cache measurement afterwards; assuming it worked is how
you end up with two problems.

### DNSSEC is disabled

For a fediverse instance the domain is the identity: other servers decide what to
trust by hostname. DNSSEC is the thing that stops an answer being forged. One
setting, free, and there is no argument against it.

### Minimum TLS version is 1.0

Raise it to **1.2**, and not higher.

TLS 1.0 and 1.1 were deprecated by RFC 8996 and carried **zero** requests across
5.6 million, so raising the floor to 1.2 costs nothing measurable.

Going to 1.3 is the tempting mistake. TLS 1.3 already carries 97.9% of traffic,
so the minimum only decides who is excluded, and the 0.034% still on 1.2 includes
named peer instances and the official Mastodon Android client. TLS 1.3 needs
OpenSSL 1.1.1 or newer, so a peer on an older base image simply cannot deliver,
and federation failures are silent. This is the difference between a website and
a federated server: inbound traffic is thousands of independently administered
machines.

Worth re-measuring in a year. If that 0.034% reaches zero, 1.3 becomes free.

### Load balancer failover is silent

Health checks pull an unhealthy pool and nothing says so. Both pools have an
empty notification address, and none of the account's notification policies is a
load balancing alert; they cover passive origin monitoring, analytics and
billing.

The consequence is losing half the serving capacity indefinitely without a
signal, which matters more than it sounds: the surviving cluster runs a single
web replica on nodes already near their memory limit.

Two ways to fix it, either sufficient. Set a notification address on each pool,
or add a notification policy of type `load_balancing_health_alert` filtered to
the pools. Both need a token with write access; the one in use here is read-only.

### Page Shield is off

Included in the current plan. It watches for third-party scripts changing or
appearing, on a site that serves user-submitted content.

### Stale things

Six Workers scripts exist and two are routed. Two of the unrouted ones are the
edge half of a page-replica experiment whose Kubernetes half was removed from
this repository in September 2026. They do nothing and should go together.

Five R2 buckets exist and two are demonstrably in use. The rest may be backups or
may be 2023 leftovers; they bill for storage either way and nobody outside the
account can tell which is which.

Zone hold is off. It is free and prevents the domain being moved out of the
account by accident.

### Worth a decision

**AI crawler blocking is hand-rolled** as a WAF rule matching a list of user
agents, while Cloudflare's own bot controls for the same purpose sit disabled.
Theirs is maintained as new crawlers appear; a hand-written list rots.

**Rocket Loader is on.** It defers and reorders JavaScript, and Mastodon's
interface is a client-rendered React application. Cloudflare's documentation
warns it can break JavaScript-heavy sites. If nothing is broken, leave it, but it
is the first thing to suspect when the interface misbehaves for no visible
reason.

**SSL mode is Full, one step below Full (strict).** Every origin is a tunnel address,
so the tunnel already authenticates that hop and the practical gap is small.
Strict is still the stronger setting.

**A maintenance redirect exists, disabled, matching the whole site.** Correct to
have. Worth knowing it is one toggle away from a site-wide redirect.

## What was checked and found fine

Security level, Brotli, HTTP/3, 0-RTT, Early Hints, IPv6, image optimisation,
browser cache TTL, always-online, and the origin read timeout all look
reasonable. Page rules, waiting rooms, Spectrum applications, KV, D1 and Queues
are all empty. Two Workers routes serve small static concerns.

## Regenerating this

`scripts/cloudflare-snapshot.py` dumps the configuration to JSON with credentials
redacted. It needs a read-only token, in `CLOUDFLARE_API_TOKEN` or in
`terraform.tfvars` as `cloudflare_api_token`.

Its output is gitignored on purpose. Redacted or not, a machine-readable dump
says which paths are challenged, which are rate limited and what the WAF matches
on, and that does not belong in a public repository. Read it, write down what
changed, throw it away.

The measurements come from Cloudflare's GraphQL analytics endpoint, which the
same token can reach. Retention on this plan is short, so ask for a window inside
the last few days.

## Corrections this document already survived

Three claims in the first pass of this audit were wrong, and the pattern is worth
recording because it will recur.

Media was described as never cached, from one request to one recently uploaded
object that returned `DYNAMIC`. Measured across 233,008 requests it hits 48.6% of
the time. Two CDN hostnames were described as dead, on the grounds that nothing
was bound to them; they serve about three thousand requests a day. A third
hostname was called unused when it serves the custom error page.

All three came from generalising a single observation. The configuration says
what is set; the analytics say what is happening, and only the second kind of
question can be answered by looking at settings.
