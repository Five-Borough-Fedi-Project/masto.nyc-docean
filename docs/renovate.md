# Renovate

Image and action updates arrive as pull requests instead of being noticed months
late. The config is `renovate.json` at the repository root.

The GitHub App was installed on 2026-09-05, so this is live rather than
pending. Because `renovate.json` already existed, there was no onboarding pull
request to merge: Renovate reads the config and starts.

## Where to look

A Dependency Dashboard issue tracks everything pending, including updates
deliberately held back. Read the dashboard. The pull request list shows only
what Renovate chose to propose, and says nothing about what it is sitting on.

After that, a Dependency Dashboard issue tracks everything pending, including
updates deliberately held back. Read the dashboard first to see the full picture.

## What it will not touch, and why

**Mastodon.** `ghcr.io/mastodon/mastodon` and `mastodon-streaming` are disabled
outright. A Mastodon version bump needs more than a merge. It needs the pre-deployment
migration, then the image rollout, then the post-deployment migration, in that
order, with the site drained in between. Flux applies whatever is on main and
knows none of that. An automated pull request that looks like every other
dependency bump, merged on a Friday, would deploy a new image against an
unmigrated database.

The 4.7.0 upgrade in `docs/upgrade-runbook.md` also turned up twenty
post-deployment migrations spanning three years that had never run, because
`SKIP_POST_DEPLOYMENT_MIGRATIONS` was permanently set. A person reading release notes
finds that. A bot comparing version strings never would.

**Images this repository builds.** `welcome-bot`, `timeline-health` and
`sync-blocked-email-domains` are tagged with the commit that produced them.
There is no upstream to check.

## What it will do

Everything else that runs alongside Mastodon, grouped into one pull request so a
quiet week is one review instead of six: cloudflared, nginx, libretranslate,
kube-state-metrics, metrics-server, the backup and repack images, and the two
debugging images. GitHub Actions and the DigitalOcean Terraform provider are
grouped separately.

Two versions pinned as workflow environment variables are tracked by custom
regex managers, since nothing else would find them: `TOFU_VERSION` and
`GITLEAKS_VERSION`.

`GITLEAKS_VERSION` comes with a catch. The secret-scan workflow verifies a
sha256 alongside the version, and Renovate cannot know the new checksum. Those
pull requests arrive as a prompt to update both by hand, and CI fails until the
checksum matches. That is the intended behaviour: a version bump that silently
skipped the checksum check would defeat the reason for pinning it.

## Digest pinning

`pinDigests` is on, so tags become `tag@sha256:...`. A tag can be moved by
whoever owns it; a digest cannot. Renovate then keeps the digest current, which
is what makes pinning sustainable. Left alone, pinned digests go stale.

Two images were pinned by hand when this landed, to the digests they were
actually running: `filefrog/k8s-hacks:pause` and
`eeshugerman/postgres-backup-s3:16`. Both had passed the manifest build check,
which only rejected `:latest` and untagged images. `pause` and a bare major
version like `16` move under you without the manifest changing, and the check
now says so.

## Automerging

Non-major updates -- minor, patch and digest -- merge themselves once the checks
on the pull request are green. Major updates never do. They keep the seven-day
cooling period and the `major` label, because a major version is a reading task.

**This deploys.** The cluster images group edits `k8s/`, and Flux reconciles
main within ten minutes, so an automerged nginx or cloudflared digest is a
production rollout that nobody watched. That is the deliberate trade: the
alternative was a queue of digest bumps sitting until somebody found a Monday
for them. What must never roll out this way is disabled outright in the section
above rather than trusted to this rule, Mastodon first among them.

Four things still wait for a person:

- Anything major.
- The Mastodon upgrade pull requests. Those come from `mastodon-upgrade.yaml`
  rather than from Renovate, so nothing here reaches them.
- The `automation/image-tags-*` pull requests, which come from
  `docker_images.yaml` and are what actually deploys a first-party image.
- `GITLEAKS_VERSION`. Its sha256 has to be updated by hand and CI fails until it
  matches, so automerge never sees a green branch to act on. The pull request
  waits, which is the behaviour the section above describes rather than a
  regression of it.

`platformAutomerge` is off on purpose. GitHub's own auto-merge releases a pull
request when its **required** checks pass, and `main` has no required checks --
the ruleset list is empty -- so it would merge without waiting for anything.
With it off, Renovate reads the branch status itself.

`automergeSchedule` is `at any time`, separate from the Monday creation
schedule. Without it a pull request that went green on Monday morning would sit
until the following Monday, when Renovate next ran and could merge it.

One consequence worth stating before it happens rather than after. Security
updates already bypass the weekly schedule, and they bypass this too: a CVE fix
for a cluster image can be proposed, pass its checks and reach production on a
Saturday night with nobody present. That is what the vulnerability block is for,
but it is a different thing from a Monday morning review.
