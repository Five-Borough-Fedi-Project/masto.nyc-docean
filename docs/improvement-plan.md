# Improvement plan, 2026-09-06

Everything proposed from the review of the edge, the request path and the
application, with the evidence for each and what it would cost. Ordered by value
against risk.

Written alongside `docs/cloudflare-audit.md`, which covers the edge in more
depth. Every number here was measured. Where something is a guess it says so.

## Tier 1: do these

Small, evidenced, and none of them need a decision.

### Cache rule for `/.well-known/*`

**17,295 requests a day cross the tunnel** on paths Mastodon explicitly marks
cacheable. Webfinger, host-meta and nodeinfo all return `max-age=259200, public`
and all report `cf-cache-status: DYNAMIC`, because Cloudflare's default caching
keys on file extension and these paths have none.

They do not reach Rails. nginx already caches them and answers every one from its
own store, verified by `X-Cached: HIT` on a cold request for all three paths. So
the win is the tunnel hop and the round trip to the cluster. Origin CPU was never
the cost. That is smaller than it first looked, and still worth having: the edge answer is
closer to the remote instance asking, and it survives a pod restart, which the
nginx cache does not.

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

### DNSSEC — done 2026-09-06

Was disabled. For a fediverse instance the domain is the identity other servers
trust, and DNSSEC is what stops an answer being forged. One setting, free.

### Minimum TLS version 1.0 to 1.2 — done 2026-09-06

**Zero requests** used TLS 1.0 or 1.1 across 5.6 million in 48 hours, so raising
the floor costs nothing measurable.

Not 1.3. It already carries 97.9% of traffic, so the minimum only decides who is
excluded, and the 0.034% still on 1.2 includes named peer instances and the
official Mastodon Android client. TLS 1.3 needs OpenSSL 1.1.1 or newer; a peer on
an older base image simply stops delivering, silently.

### nginx read timeout — done

Cloudflare waits 125 seconds. nginx sets no timeout, so it defaults to 60. A
request between those two is cut by the middle of the stack while the edge is
still waiting, and the client gets a 504 that did not come from the edge. Set
`proxy_read_timeout 125s`.

### nginx logging — done

`access_log /dev/null; error_log /dev/null`. With vector removed there is now no
request log anywhere in the stack, so a 502 leaves nothing to read. Turn access
logging on, at minimum for non-2xx.

### Remove the sample tunnel ingress rules — done

All three tunnel configs still carry `hello.example.com` routed to
`hello_world`, from Cloudflare's tutorial. Three lines each, nobody meant any of
them.

### Page Shield and zone hold

Page Shield is included in the current plan and watches for third-party scripts
changing on a site that serves user content. Zone hold prevents the domain being
moved out of the account by accident. Both free, both one setting.

### Delete two orphaned Workers

`page-replica-mastonyc` and `page-replica-rw` are unrouted Workers scripts. They
are the edge half of an experiment whose Kubernetes half was removed in #37.

## Tier 2: worth doing, needs a decision

### The nginx cache is full and unbounded — bounded

Configured with a 10MB keys zone and `max_size=1g`, writing to `/tmp`.

| | entries | on disk |
|---|---|---|
| do | 312 | 12 MB |
| lab | 34,579 | **1.0 GB** |

lab is at `max_size` exactly, which means it has been evicting for some time.
`/tmp` is the container's writable layer on node storage, with no volume and no
`ephemeral-storage` limit, so the ceiling that is actually holding is an nginx
directive. One replica per cluster and ~98GB free on the smallest lab node, so
nothing is at risk today; it is worth an `ephemeral-storage` limit above 1GB so
the kubelet has a number to enforce.

The cache is doing real work and is keyed correctly. Entries are tag, status and
account paths; Mastodon sends `vary: Authorization, Origin` on API responses and
`vary: Cookie` on web ones, and nginx keys on the varying headers, so one user
cannot be served another's page. `proxy_ignore_headers` is not set, so origin
`Cache-Control` governs the TTL.

One dead line: `proxy_cache_valid 410 24h` never applies, because Mastodon sends
an explicit `max-age` on 410 and that takes precedence.

### Upload limits disagree across three layers — done

| | limit |
|---|---|
| Cloudflare `max_upload` | 100 MB |
| nginx `client_max_body_size` | **80 MB** |
| Mastodon `VIDEO_LIMIT` | 99 MB |

A video between 80 and 99 MB is one Mastodon accepts and advertises, and the
client will offer to upload. nginx rejects it with a 413 before Rails sees it.
Raise `client_max_body_size` to 100m.

### Sidekiq memory limits are set where web's deliberately are not — done

`mastodon-sidekiq-bulk` was **OOMKilled on 2026-09-06 at 16:34**, after about
five and a half hours, against a 1100Mi limit. `realtime` shares that limit and
currently sits at 735Mi. Both run 25 threads.

`mastodon-web` carries a comment explaining why it has no memory limit: a limit
guessed below the real peak OOMKills the tier instead of protecting it, and
nothing here retains the history that would tell you the peak. That reasoning is
sound and it applies just as well to Sidekiq, which does have a guessed limit and
has now been killed by it.

An OOMKilled Sidekiq loses its in-flight jobs, so this is not free: plain Sidekiq
has no super_fetch, and whatever the 25 threads were holding goes with them.

Resolved by moving Sidekiq to mastodon-large and raising the ceilings to 2Gi.
The DO nodes carry 3Gi of allocatable memory each and were running at 93, 75 and
56 percent; the bare-metal nodes are 31Gi each at under a third. The limits are
still guesses, and now they are guesses with room above anything observed.

The database path was the thing to check first, and it is not a cost. TCP
connect to Postgres, 15 samples on 2026-09-07: **8.6ms p50 from mastodon-large
against 10.7ms from do-production**. The web tier already runs there and cares
more about latency than a job queue does.

The trade is availability. If the bare-metal cluster is unreachable, Sidekiq
stops, and unlike the web tier there is no second pool to take over. Nothing is
lost, because the queues live in Redis under `noeviction`, but they grow: Redis
peaked at 238MB of 418MB, so a backlog has roughly 180MB before writes start
failing. That is the number to watch during a long outage, and it is the
strongest argument for the Redis alert in Tier 3.

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

### LibreTranslate is deployed and unreachable by Mastodon

Neither cluster's environment carries a translation endpoint. LibreTranslate runs
on do-production, now with a healthy Service endpoint after the selector fix in
#60, and nothing points Mastodon at it. It also could not serve mastodon-large if
it were configured, because the address is inside the do-production pod network
and only that cluster's `ALLOWED_PRIVATE_ADDRESSES` permits it. Wiring it up
needs a decision and a secret change.

### Connection arithmetic is tighter than it looks

| | connections |
|---|---|
| do web, 1 pod | 10 |
| sidekiq bulk and realtime, at 25 | 50 |
| sidekiq scheduler, at 5 | 5 |
| do streaming, 1 pod | 10 |
| large web, 2 pods | 20 |
| **maximum client connections** | **95** |
| pgbouncer pool size | 85 |
| postgres max_connections | 100 |

Nothing is wrong today: 28 server connections in use, and pgbouncer in
transaction mode multiplexes, so client connections exceeding the pool queue
instead of failing. The headroom is arithmetic, though, and thin.

The cheapest slack is `mastodon-sidekiq-sched`, which runs `-c 25` with
`DB_POOL=25` to service the scheduler queue alone. That queue runs periodic jobs
and does not need 25 threads. Dropped to 5, which returns 20 connections and
takes memory pressure off a pod sitting at 573Mi against a 900Mi limit. Maximum
client connections are now 95 against a pgbouncer pool of 85.

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

## Corrections

Four claims in the first draft of this plan were wrong. Recorded because the way
they were wrong is more useful than the claims were.

**The nginx cache was described as empty on both clusters.** It holds 312 entries
on do and 34,579 on lab. The measurement was `find /tmp/proxycache -type f` run
through `kubectl exec`, which returned nothing. The exec shell is uid 0, the cache
directory is `0700 nginx`, and the container drops all capabilities, so root has
no `CAP_DAC_OVERRIDE` and the read was refused. Empty output, no error, wrong
conclusion. Re-run as the `nginx` user it gives the numbers above.

**`error_page` was described as broken.** `/500.html` returns 200 and Mastodon's
real error page. nginx has no root, so `try_files` falls to the proxy and Rails
serves the file itself, because `RAILS_SERVE_STATIC_FILES` is true. The directive
works. It was never tested before being written down.

**`/.well-known/*` was described as reaching Rails 17,295 times a day.** It
reaches nginx, which answers from cache. The Cloudflare figure counts what
crosses the tunnel, and the layer below it was not checked.

**The connection table omitted streaming**, which runs one pod at `DB_POOL=10`.

Three of the four are the same mistake: a number from one layer was read as a
statement about a different layer, or a check that found nothing was read as
proof that nothing was there.

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


Streaming correctly bypasses nginx, which matters because `proxy_buffering on`
would break server-sent events.

The three health checks do not conflict: the load balancer monitor traverses the
whole path to Rails, the Kubernetes readiness probe checks Rails directly, and
nginx answers its own `/healthz` so a Rails outage does not also remove the proxy.
