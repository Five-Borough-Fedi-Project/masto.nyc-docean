#!/usr/bin/env python3
"""Pick the next Mastodon version to upgrade to, or print nothing.

Renovate is switched off for the Mastodon images on purpose: a version bump has
to rename both migration Jobs and re-point the Flux health checks in the same
commit, and Renovate would open a pull request that edits the tag alone. The
cost of that was that nothing announced a new release, so an upgrade only
happened when somebody noticed.

The policy is one minor at a time. Patches inside the current minor are
cumulative and safe to take together, so it goes straight to the newest of
those. Crossing a minor takes the lowest release of the next one, because that
is where Mastodon's database markers have always appeared and the runbook asks
for the release notes of everything in between.

Usage: next-mastodon-version.py <current> < tags
       where tags is one tag per line, as `gh api .../releases --jq .tag_name`.

Prints the target and exits 0, or prints nothing and exits 0 when there is
nothing newer. Exits 1 only when the current version is unreadable.
"""
import re
import sys


def parse(tag):
    m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag.strip())
    return tuple(int(g) for g in m.groups()) if m else None


def pick(current, tags):
    cur = parse(current)
    if cur is None:
        raise ValueError("%r is not vMAJOR.MINOR.PATCH" % current)
    releases = sorted({p for p in (parse(t) for t in tags) if p})
    newer = [r for r in releases if r > cur]
    if not newer:
        return None
    same_minor = [r for r in newer if r[:2] == cur[:2]]
    return max(same_minor) if same_minor else min(newer)


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    try:
        target = pick(sys.argv[1], sys.stdin)
    except ValueError as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    if target:
        print("v%d.%d.%d" % target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
