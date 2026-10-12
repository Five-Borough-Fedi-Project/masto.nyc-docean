# Blocklists

Two different things share the word, and only one of them is automated. Worth
separating before anything else, because the names invite the mistake.

| | what it blocks | automated |
|---|---|---|
| `sync-blocked-email-domains` | email domains at signup, anti-spam | yes, a CronJob |
| oliphant.social Tier 0 | fediverse servers, defederation | **no** |

## The email domain job

`k8s/apps/cronjobs/sync-blocked-email-domains.yaml`. A CronJob in the `mastodon`
namespace that pushes a list of blocked email domains into Mastodon over its
API, so throwaway-address signups fail at the door. Nothing to do with
defederation.

    schedule      0 3 * * *   daily, 03:00 UTC, no timeZone set
    runtime       about 115 minutes, measured 2026-09-05
    concurrency   Forbid
    deadline      4h, the point past which it is stuck rather than slow
    retries       backoffLimit 1

The deadline and the retry limit are both scars. With `Forbid` and no deadline a
single hung run silences every later one. And the run on 2026-08-31 failed and
retried to the old default of six, which at roughly two hours an attempt is most
of a day spent failing.

### Its image has no source here

The manifest pins
`ghcr.io/five-borough-fedi-project/masto.nyc-docean/sync-blocked-email-domains`
**by digest**, and there is no `docker/sync-blocked-email-domains/` directory --
nor any record of one in this repository's history.

That matters more than it looks:

- `docker_images.yaml` builds what it finds at `docker/*/Dockerfile`, so it has
  never built this one and never will.
- Renovate has the first-party `ghcr.io/five-borough-fedi-project/` images
  disabled, correctly, since normally their tag is the commit that produced them
  and there is no upstream to check.
- So nothing in this repository can rebuild or update that image. It is frozen
  at a digest, running nightly, holding a Mastodon API token.

`docs/renovate.md` used to list it among "images this repository builds", which
was wrong on both counts. That is corrected; this is the longer version.

Whoever needs to change that job's behaviour has to find where the image is
actually built first. Options are to bring the source in under `docker/` so the
existing pipeline covers it, or to pin it somewhere that makes its externality
obvious. Neither is done.

### Seeing whether it ran

It used to be the log pipeline. Vector shipped pod logs to BetterStack until
2026-09-05, when it was removed along with the rest of log shipping; see
`docs/logging-teardown.md`. Nothing collects pod logs now, so **a CronJob that
fails at 03:00 fails silently** -- it sits in `kubectl get jobs` for whoever
thinks to look, and reaches nobody.

`sync-blocked-email-domains-watchdog.yaml` closes that for this one job. Daily
at 09:00 UTC it reads `kube_cronjob_status_last_successful_time` from
kube-state-metrics and, if the last success is more than twenty hours old, posts
to Discord and exits non-zero.

kube-state-metrics was already running in `kube-system` with no consumer, kept
on the grounds that whatever replaced the pipeline would want it. This is that
consumer.

Two details worth knowing before trusting it:

- **It needs the webhook in the cluster.** Everything else that posts to Discord
  does so from outside it, so the URL had never been handed to Kubernetes.
  `kubernetes-secrets.tf` now creates `discord-ops-webhook`, guarded by the same
  `local.discord_enabled` as `monitoring.tf`. The watchdog declares the
  secretRef `optional`, so with no webhook configured it still runs and still
  fails in the cluster; it just has nowhere to post. **That secret needs a
  `tofu apply`**, which waits behind the production environment gate.
- **The twenty hours is chosen, not arbitrary.** The watched job starts at 03:00
  and takes about two hours against a four-hour deadline, so on a good day its
  last success is between 05:00 and 07:00. Checked at 09:00, that is an age of
  two to four hours; one missed night makes it twenty-six to twenty-eight.
  Twenty sits clear of both.

The same manifest with a different `CRONJOB` covers any of the others that need
it, and fewer need it than first appears. `postgres-backup` and
`timeline-health-check` both send a BetterStack **Uptime** heartbeat, which is a
different product from the BetterStack **Logs** that Vector fed and was not
touched by that teardown. The backup's is the last thing in
`/run.sh && /postgres.sh`, so it only fires on success: a failed or skipped
night shows up as a missed heartbeat rather than as nothing at all.

What has no monitoring of any kind is the six weekly maintenance jobs -- the
three media ones, `preview-cards-remove`, `statuses-remove` and
`migration-status`. The last is the uncomfortable one. It exists because twenty
post-deployment migrations were silently skipped for three years, and a check
nobody ever hears from is the same shape of problem it was built to catch.

## The fediverse blocklist

`.github/workflows/blocklist-sync.yaml`. Three IFTAS denylists are merged
nightly, the allowlist is applied, and the result is compared against what the
instance already blocks. A routine difference is applied straight away; an
anomalously large one is held for a person.

    DNI          curated, IFTAS-recommended defederation      95 domains
    AUD          spammers and abandoned servers               49 domains
    CARIAD 66%   blocked by two thirds of the observed network 115 domains
    ----------------------------------------------------------------------
    merged, minus the allowlist                               204 domains

### Why IFTAS, after two false starts

The job this replaces subscribed to oliphant's Tier 0 list. That list has not
changed since 2026-03-29 and the repository behind it has had no commit of any
kind since 2026-04-15, so restoring the old job as written would have pinned the
instance to a blocklist frozen in March.

Garden Fence was the next candidate and is better maintained, but it had not
published since 2026-08-09 against a stated weekly cadence, and it is explicitly
one instance's judgement: only domains blocked by sunny.garden, filtered through
unnamed reference servers. Its README says plainly that it is not a neutral
survey.

IFTAS is an organisation rather than an admin, was posting in September 2026,
and publishes its consensus thresholds as numbers. That last part is the real
reason: "we defederate what two thirds of the observed network defederates" is a
policy that can be written down, argued with and changed. "We use somebody's
list" is not.

### The threshold, and how to widen it

66% is the chosen tier. The alternative considered was the Omnibus file, which
is DNI + AUD + CARIAD **51%** and 289 domains against this combination's 204.
Replacing the CARIAD 66% URL in `blocklist/sources.toml` with the 51% one makes
this equivalent to Omnibus; the URL is in a comment there. 80% also exists, at
48 domains, for a far more conservative position.

Widening is one URL. Explaining an over-block is not, which is why the first
restored run is the narrower of the two that were on the table.

### Exceptions

`blocklist/allowlist.csv`. Any domain listed there is dropped from the merged
list regardless of which source proposed it. Two entries today:

- `masto.nyc`, because blocking ourselves would break federation for our own
  users.
- `threads.net`, by moderator decision on 2026-10-09. It is in CARIAD 66% as
  `iftas:cariad66`, severity `suspend`, so without this entry adopting these
  lists would have suspended Threads. It is in the Omnibus file too, via the
  51% tier, so the exception is needed whichever threshold is chosen.

Add a row to allow another domain. The `severity` and `public_comment` columns
are there for the human reading the diff; fediblockhole only reads `domain`.

**Matching is exact.** fediblockhole deletes the merged entry whose domain
string matches, so an entry for `example.com` does not cover
`social.example.com`. These lists carry root domains, so that is fine in
practice, but a list adding a subdomain variant would need its own row.

For a one-off that should not be committed, `fediblock-sync --allow DOMAIN`
takes the same argument on the command line.

**One adjacent case, flagged rather than decided.** `mostr.pub`, a Nostr bridge,
is in all three CARIAD tiers at `iftas:cariad80`, so it is currently blocked by
this configuration. Garden Fence deliberately excludes bridges as out of scope;
IFTAS includes them. Nobody has decided which position this instance holds. If
bridges should be reachable, `mostr.pub` belongs in the allowlist.

### What it will not do

**It stores nothing.** There is no committed copy of the blocklist. What this
instance blocks is whatever `/api/v1/admin/domain_blocks` says it blocks, and
that is what the merged lists are compared against. The only file under version
control is `blocklist/allowlist.csv`, which is hand-written configuration rather
than fetched data.

A vendored snapshot was the first design and was dropped. It bought a file-diff
review and a guarantee that what applied was what was reviewed, but it also made
this repository the only place here that keeps a copy of somebody else's data,
against a convention that otherwise references upstream content by pinned digest
and never copies it in.

**It never unblocks anything.** fediblockhole has a `delete_block` function and
no code path that calls it; `push_blocklist` adds new blocks and updates
existing ones. A domain dropping off the upstream lists therefore stays blocked
here until a person removes it in the admin UI. That is also why a shrinking
upstream list can never trip the size gate: removals are not actionable, so they
are reported and ignored.

**It never suspends a domain somebody here follows.** The destination carries
`max_followed_severity = 'silence'`. Every row in all three lists is `suspend`,
and a suspend severs existing follow relationships; this caps the severity at
silence where a follow exists. The old job did the same, and it is the single
setting that makes automating this defensible at all.

### What it decides for itself, and what it does not

Routine updates apply without asking. A person is pulled in for exactly two
cases, and `scripts/check-blocklist.py` tells them apart because they want
opposite responses.

**`fail` -- the data is not trustworthy.** Nothing is applied and nobody is
asked to review it, because there is nothing worth reviewing. Triggered by:

- a header that is not `domain,severity,public_comment`
- fewer than 50 domains, a floor well under the real size and well over an
  error page
- IFTAS's `cariad.invalid` canary missing from the merged result
- an allowlisted domain surviving the merge, which would mean a moderator's
  exception was silently ignored
- the admin API returning something that is not a list of blocks

IFTAS serves these lists from Google Sheets, which sends `no-store` and no
`ETag` and can hand back an HTML error page when throttled. Diffed naively
against the instance, that reads as nothing to do -- or worse, as every domain
being new. The first two checks are what stand in the way.

**`review` -- the data is fine and the decision is a moderator's.** Nothing is
applied, Discord is told, and the run goes red so a held decision does not look
like a success in the run list. Triggered when additions plus severity
escalations exceed the larger of **10** and **10% of what the instance currently
blocks**.

Ten because these lists move weekly at most and a week's change is a handful of
domains. The percentage because the absolute number is the wrong measure at both
extremes: on an instance blocking very little, ten additions is a large
proportional change, and on one blocking a great deal it is noise. Taking the
larger of the two stops either from making the gate absurd.

To accept a held change, re-run the workflow with `allow_large_change` set.
Note that this re-fetches rather than replaying what was held, so what applies
is the current delta -- which is the right behaviour, but means a very stale
approval applies today's list rather than the one in the run you read.

Each case was tested against a fabricated failure: an HTML error page, a
truncated sheet, a stripped canary, a leaked allowlist entry, and an API error
body all return `fail`; an instance missing 184 of the listed domains returns
`review`; three additions, a severity escalation, a removals-only difference,
and an already-synced instance all return `ok`.

### Confirming it ran

Ask the instance for the canary. Every IFTAS list carries a block on
`cariad.invalid`, a domain in an invalid TLD that exists only to be a sentinel.
If it appears under **Moderation > Federation**, a push landed. That is cheaper
and more direct than any watchdog, and it is why this job has none.

Discord gets a message whenever something happened, carrying the diff that was
applied -- the added domains with their severity, and any existing block whose
severity was raised:

    **Blocklist updated**: 3 applied to masto.nyc.
    ```
      + newbadsite.example (suspend)
      + another.example (suspend)
      ^ known.example (silence -> suspend)
    ```

A day with no changes says nothing at all. A channel that gets a daily "nothing
to report" is a channel that gets muted, and a muted channel is worse than no
channel.

Two details in that message are deliberate. The headline is keyed on whether the
apply step actually succeeded rather than on the verdict, because reading the
verdict alone would announce "3 changes applied" after a push that died halfway
through the admin API; a partial apply says so. And the diff is capped at
twenty-five lines with an explicit "and N more" rather than being silently
truncated, because Discord rejects a message over two thousand characters and a
large accepted change would otherwise vanish mid-list.

### Still outstanding

`MASTODON_ADMIN_TOKEN` does not exist yet. Unlike the first design, it is needed
for **every** run and not just to apply: without it there is nothing to compare
the merged lists against, so the job logs a notice and exits 0. It needs
`admin:read:domain_blocks` and `admin:write:domain_blocks`.

It is a secret rather than a config value on purpose. The legacy job put this
token inline in a TOML file inside a ConfigMap, where `kubectl describe` would
print it; this repository is public, and that is the mistake the secrets work of
2026-08 existed to end.
