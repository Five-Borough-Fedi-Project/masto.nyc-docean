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

`policies.md` in the website repository says the instance subscribes to the
[oliphant.social Tier 0 blocklist](https://codeberg.org/oliphant/blocklists/),
and that moderators block additional servers at their discretion.

**There is no automation for any of that.** No reference to oliphant, Tier 0,
`domain_blocks` or defederation exists anywhere in this repository. Whatever
keeps the server's domain blocks aligned with Tier 0 is a person doing it by
hand, or it is not happening.

That is recorded here rather than fixed, deliberately. Automating it would mean
a job that blocks servers without review, and the blast radius is other
people's conversations: a bad entry, or an upstream list that moves in a
direction the moderators would not have chosen, severs real follow
relationships. `policies.md` already frames server blocking as "at the
moderators' discretion", which is a policy position, and a cron job is a poor
way to hold one.

If it is worth automating later, the shape is roughly:

- Pull the Tier 0 CSV, which is versioned on Codeberg.
- Diff it against `/api/v1/admin/domain_blocks`.
- **Open a pull request, or post the diff to Discord, rather than applying it.**
  A human approves the additions.
- Never remove a block automatically. Unblocking is a decision, and
  `policies.md` already points people at the issue tracker for it.

That keeps the list current without handing defederation to a timer. It is a
larger piece of work than it looks, mostly because of the reconciliation rules
rather than the fetching.
