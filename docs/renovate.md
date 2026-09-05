# Renovate

Image and action updates arrive as pull requests instead of being noticed months
late. The config is `renovate.json` at the repository root.

The GitHub App was installed on 2026-09-05, so this is live rather than
pending. Because `renovate.json` already existed, there was no onboarding pull
request to merge: Renovate reads the config and starts.

## Where to look

A Dependency Dashboard issue tracks everything pending, including updates
deliberately held back. Read the dashboard rather than the pull request list, or
you will only see what it decided to propose and not what it is sitting on.

After that, a Dependency Dashboard issue tracks everything pending, including
updates deliberately held back. Read the dashboard rather than the pull request
list to see the full picture.

## What it will not touch, and why

**Mastodon.** `ghcr.io/mastodon/mastodon` and `mastodon-streaming` are disabled
outright. A Mastodon version bump is not a merge: it needs the pre-deployment
migration, then the image rollout, then the post-deployment migration, in that
order, with the site drained in between. Flux applies whatever is on main and
knows none of that. An automated pull request that looks like every other
dependency bump, merged on a Friday, would deploy a new image against an
unmigrated database.

The 4.7.0 upgrade in `docs/upgrade-runbook.md` also turned up twenty
post-deployment migrations spanning three years that had never run, because
`SKIP_POST_DEPLOYMENT_MIGRATIONS` was permanently set. That is the kind of thing
found by a person reading release notes, not by a bot comparing version strings.

**Images this repository builds.** `welcome-bot`, `timeline-health` and
`sync-blocked-email-domains` are tagged with the commit that produced them.
There is no upstream to check.

## What it will do

Everything else that runs alongside Mastodon, grouped into one pull request so a
quiet week is one review rather than six: cloudflared, nginx, libretranslate,
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
is the part that makes pinning sustainable rather than a thing that rots.

Two images were pinned by hand when this landed, to the digests they were
actually running: `filefrog/k8s-hacks:pause` and
`eeshugerman/postgres-backup-s3:16`. Both had passed the manifest build check,
which only rejected `:latest` and untagged images. `pause` and a bare major
version like `16` move under you without the manifest changing, and the check
now says so.
