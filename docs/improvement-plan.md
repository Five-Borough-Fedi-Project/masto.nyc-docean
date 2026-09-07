# Improvement plan, 2026-09-06

Everything proposed from the review of the edge, the request path and the
application, with the evidence for each and what it would cost. Ordered by value
against risk.

Written alongside `docs/cloudflare-audit.md`, which covers the edge in more
depth. Every number here was measured. Where something is a guess it says so.

## Tier 1: do these

Small, evidenced, and none of them need a decision.

### Cache rule for `/.well-known/*`

**17,295 requests a day reach Rails** on paths Mastodon explicitly marks
cacheable. Webfinger, host-meta and nodeinfo all return `max-age=259200, public`
and all report `cf-cache-status: DYNAMIC`, because Cloudflare's default caching
keys on file extension and these paths have none.

The zone's cache rules ruleset is empty, so there is nothing to conflict with.

**The rule must respect the origin's cache-control. Do not set an edge TTL.**
Mastodon returns `max-age=3.days` on a hit and `max-age=180` on 404, 410 and 400,
deliberately, so a cache cannot poison federation with a stale negative answer.
Overriding that with a fixed edge TTL would cache a new account's 404 for three
days and make it unresolvable from remote instances. Verified against
`well_known/webfinger_controller.rb` and confirmed live.

Two smaller risks, both checked. `Vary: Accept` is Rails boilerplate here: three
different Accept headers return byte-identical responses, so Cloudflare not
keying on Accept is safe. The query string distinguishes accounts and Cloudflare
includes it in the cache key.

One operational change to accept: deleting an account returns 410, but a
previously cached 200 keeps serving for up to three days. That is already true
of every remote server's cache, since Mastodon asks for it. It means purging
Cloudflare when deleting an account.

### DNSSEC

Disabled. For a fediverse instance the domain is the identity other servers
trust, and DNSSEC is what stops an answer being forged. One setting, free.

### Minimum TLS version 1.0 to 1.2

**Zero requests** used TLS 1.0 or 1.1 across 5.6 million in 48 hours, so raising
the floor costs nothing measurable.

Not 1.3. It already carries 97.9% of traffic, so the minimum only decides who is
excluded, and the 0.034% still on 1.2 includes named peer instances and the
official Mastodon Android client. TLS 1.3 needs OpenSSL 1.1.1 or newer; a peer on
an older base image simply stops delivering, silently.

### nginx read timeout

Cloudflare waits 125 seconds. nginx sets no timeout, so it defaults to 60. A
request between those two is cut by the middle of the stack while the edge is
still waiting, and the client gets a 504 that did not come from the edge. Set
`proxy_read_timeout 125s`.

### nginx logging

`access_log /dev/null; error_log /dev/null`. With vector removed there is now no
request log anywhere in the stack, so a 502 leaves nothing to read. Turn access
logging on, at minimum for non-2xx.

### Remove the sample tunnel ingress rules

The cloudflared config still carries `hello.example.com` routed to
`hello_world`, from Cloudflare's tutorial. Three lines nobody meant.

### Page Shield and zone hold

Page Shield is included in the current plan and watches for third-party scripts
changing on a site that serves user content. Zone hold prevents the domain being
moved out of the account by accident. Both free, both one setting.

### Delete two orphaned Workers

`page-replica-mastonyc` and `page-replica-rw` are unrouted Workers scripts. They
are the edge half of an experiment whose Kubernetes half was removed in #37.

## Tier 2: worth doing, needs a decision

### The nginx cache does nothing

Configured with a 10MB keys zone, `max_size=1g` and `proxy_cache_valid 200 7d`.
**Zero entries on both clusters.** Mastodon returns `max-age=15` with
`vary: Accept, Accept-Language, Cookie`, so entries are per-user and live fifteen
seconds. `X-Cached` cycles MISS to EXPIRED and never HIT.

Two honest options. Delete the cache directives, which removes dead
configuration. Or make it work for genuinely anonymous paths with
`proxy_ignore_headers` and a cache key excluding cookies, which is a real feature
and also the way one user gets served another user's page if the path list is
wrong.

Deleting is the safe default. Making it work needs a reason.

Related: the cache path is `/tmp`, which is the container's writable layer on
node storage, with no volume and no `ephemeral-storage` limit. It
is harmless while the cache is empty. Anything that fixed the caching would start
writing up to 1GB per pod to node disk.

### nginx error pages are broken

`error_page 404 500 501 502 503 504 /500.html` with `root` commented out. There
is no filesystem to serve `/500.html` from, so it falls through to the proxy,
reaches Rails, and 404s. The Cloudflare custom error page hides this for 5xx.
Either give nginx a root with the file, or remove the directive.

### Load balancer notifications

Both pools have an empty notification address and no account policy is a load
balancing alert. Failover is silent, so half the serving capacity can be gone
indefinitely with no signal. Needs a token with write access; the one in use is
read-only.

### Hand-rolled AI crawler blocking

A WAF rule matches a list of user agents while Cloudflare's own bot controls for
the same purpose sit disabled. Theirs is maintained as new crawlers appear. A
hand-written list rots.

### Rocket Loader with a client-rendered app

It defers and reorders JavaScript and Mastodon's interface is React. Cloudflare
documents that it can break JavaScript-heavy sites. If nothing is broken, leave
it, but it is the first thing to suspect when the interface misbehaves for no
visible reason.

### SSL mode Full, one step below Full (strict)

Every origin is a tunnel address so the tunnel already authenticates that hop and
the practical gap is small. Strict is still the stronger setting.

## Tier 3: measure before acting

### Connection arithmetic is tighter than it looks

| | connections |
|---|---|
| do web, 1 pod | 10 |
| do sidekiq, 3 pods at 25 | 75 |
| large web, 2 pods | 20 |
| **maximum client connections** | **105** |
| pgbouncer pool size | 85 |
| postgres max_connections | 100 |

Nothing is wrong today: 28 server connections in use, and pgbouncer in
transaction mode multiplexes, so client connections exceeding the pool queue
instead of failing. The headroom is arithmetic, though, and thin.

The cheapest slack is `mastodon-sidekiq-sched`, which runs `-c 25` with
`DB_POOL=25` to service the scheduler queue alone. That queue runs periodic jobs
and does not need 25 threads. Dropping it to 5 returns 20 connections.

### Redis has no eviction and 57% peak

179MB used of 418MB, peak 238MB, `maxmemory-policy noeviction`.

`noeviction` is correct for Mastodon: evicting would lose queued jobs. It also
means filling the instance fails writes instead of degrading, so the headroom is
the safety margin. The right response is an alert on used memory; the setting
itself should stay.

### 8,007 dead Sidekiq jobs

Against 409 million processed and 7.2 million failed, a 1.76% failure rate. Much
of that is unreachable remote servers and is normal for federation. The dead set
is worth reading once to see whether it is all the same failure.

### Cache measurements after tiered caching

Tiered caching was enabled on 2026-09-06. Before that the media CDN was missing
40% of requests for objects marked `immutable`. Re-take that measurement once the
caches have warmed. Assuming it worked is how you end up with two problems.

### Two CDN hostnames bound to nothing that still take traffic

They serve roughly three thousand requests a day between them and are bound to no
bucket. Find out what is calling them before removing them.

### Three R2 buckets of unknown purpose

Five exist and two are demonstrably in use. The others may be backups or 2023
leftovers. They bill for storage either way.

## Rejected, with reasons

Recorded so they do not get proposed again.

**Serving static assets from a CDN via `CDN_HOST`, or from an nginx sidecar.**
Cloudflare already absorbs 99.8% of JavaScript and 99.9% of CSS. Static files are
**0.32%** of what reaches Rails, about 3,200 requests a day. Either change buys
back a third of one percent in exchange for a build-and-upload step or an extra
container per pod.

It becomes right if asset misses stop being negligible, if deploys pulling a cold
edge through the tunnel becomes a problem, or if web replicas multiply. Re-measure
before revisiting.

**Caching ActivityPub responses.** 16.6% of origin traffic and `max-age=180`, but
`vary` includes Cookie and authorized fetch signs requests. Hard to reason about
for a three minute TTL.

**Managing Cloudflare in Terraform.** Deferred deliberately. The goal was reading
the configuration and finding problems, and a control plane is the wrong tool for
that. Issue #11 stays open if that changes.

## Checked and found fine

Recorded because each of these looked like a problem and was not.

`DB_POOL` against Sidekiq concurrency: the three Sidekiq deployments already
override it to 25 to match `-c 25`, with comments explaining why. This was the
suspected cause of the connection pool exhaustion in issue #10 and it is already
addressed.

`PREPARED_STATEMENTS=false`, which is required for pgbouncer in transaction mode
and is set correctly.

OpenSearch: 9.7GB of indices on a 2GB node looked undersized. Disk is at 24%,
heap at 60%, and **zero old-generation garbage collections**, which is the number
that would show memory pressure. It is healthy.

Sidekiq throughput: every queue empty with zero latency.

Streaming correctly bypasses nginx, which matters because `proxy_buffering on`
would break server-sent events.

The three health checks do not conflict: the load balancer monitor traverses the
whole path to Rails, the Kubernetes readiness probe checks Rails directly, and
nginx answers its own `/healthz` so a Rails outage does not also remove the proxy.
