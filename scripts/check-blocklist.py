#!/usr/bin/env python3
"""Decide whether a blocklist update can apply itself.

The instance is the state. There is no committed copy of the blocklist to diff
against: what masto.nyc currently blocks is whatever /api/v1/admin/domain_blocks
says it blocks, and this compares the freshly merged lists against that.

Three verdicts, on stdout as `verdict=...` for the workflow to read:

  ok       the delta is routine. Apply it.
  review   the delta is anomalously large. Do not apply; a human looks first.
  fail     the fetched data is not trustworthy. Do not apply, and do not
           pretend a human could usefully review it either.

The distinction between `review` and `fail` is the point. A bad fetch from
Google Sheets produces a small or empty list, which is a `fail`: there is
nothing to review, the input is broken. A genuine week where IFTAS adds forty
domains is a `review`: the input is fine and the decision is a moderator's.

Usage: check-blocklist.py CANDIDATE_CSV INSTANCE_JSON
"""
import csv
import json
import os
import sys

# IFTAS puts a block on `cariad.invalid`, a domain in an invalid TLD, into every
# one of their lists. If it survived the fetch and the merge then real rows made
# it through end to end.
CANARY = "cariad.invalid"

# A floor, not an estimate. The three lists merged to 204 domains on 2026-10-09.
# Fifty is far below any plausible shrinkage and far above a truncated sheet or
# an error page.
MIN_ROWS = 50

# What counts as anomalous. Additions above *either* of these needs a person.
#
# The lists move weekly at most and a week's change is a handful of domains, so
# ten is already unusual. The percentage is there for the case the absolute
# number is not: on an instance blocking very little, ten additions is a large
# proportional change, and on one blocking a lot it is noise. Whichever is
# larger wins, so neither alone can make the gate absurd.
MAX_NEW_ABSOLUTE = 10
MAX_NEW_PCT = 10.0

EXPECTED_HEADER = ["domain", "severity", "public_comment"]

# Ordered least to most severe, for spotting escalations. fediblockhole will
# raise an existing block's severity; it never lowers one and never deletes.
SEVERITY_RANK = {"noop": 0, "silence": 1, "suspend": 2}


def read_candidate(path):
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames != EXPECTED_HEADER:
            raise ValueError(
                "header is %r, expected %r. A Google Sheets error page and a "
                "changed sources.toml both look like this."
                % (reader.fieldnames, EXPECTED_HEADER)
            )
        return {r["domain"]: r for r in reader if r.get("domain")}


def read_allowlist():
    # Resolved from this file's location, not the working directory. A
    # cwd-relative lookup that silently found nothing would turn the allowlist
    # check into a no-op, which is the one way it must not fail.
    path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "blocklist",
        "allowlist.csv",
    )
    if not os.path.exists(path):
        raise ValueError("no allowlist at %s" % path)
    with open(path, newline="", encoding="utf-8") as fh:
        return {r["domain"] for r in csv.DictReader(fh) if r.get("domain")}


def read_instance(path):
    """Current blocks, as the admin API reports them."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, list):
        raise ValueError(
            "instance blocks are %s, not a list. An API error body looks like "
            "this." % type(data).__name__
        )
    return {b["domain"]: b for b in data if b.get("domain")}


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    try:
        candidate = read_candidate(argv[1])
        allowed = read_allowlist()
        current = read_instance(argv[2])
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as exc:
        print("reason: %s" % exc)
        print("verdict=fail")
        return 1

    print("candidate: %d domains" % len(candidate))
    print("instance:  %d domains currently blocked" % len(current))

    hard = []
    if len(candidate) < MIN_ROWS:
        hard.append(
            "only %d domains in the merged list, floor is %d. Suspect a failed "
            "or partial fetch." % (len(candidate), MIN_ROWS)
        )
    if CANARY not in candidate:
        hard.append(
            "canary %r missing from the merged list. Every IFTAS list carries "
            "it, so losing it means rows were lost." % CANARY
        )
    leaked = sorted(allowed & set(candidate))
    if leaked:
        hard.append(
            "allowlisted domains survived the merge: %s. The allowlist was not "
            "applied." % ", ".join(leaked)
        )

    if hard:
        for h in hard:
            print("reason: %s" % h)
        print("verdict=fail")
        return 1

    print("allowlist: %d entries, none present in the merged list" % len(allowed))

    # What applying would actually do. Removals are listed for information
    # only: fediblockhole has no code path that deletes a domain block, so a
    # domain leaving the upstream lists stays blocked here until a person
    # removes it by hand.
    new = sorted(set(candidate) - set(current))
    escalations = sorted(
        d
        for d in set(candidate) & set(current)
        if SEVERITY_RANK.get(candidate[d]["severity"], 0)
        > SEVERITY_RANK.get(current[d].get("severity", "noop"), 0)
    )
    gone = sorted(set(current) - set(candidate))

    print("would add: %d" % len(new))
    print("would raise severity on: %d" % len(escalations))
    print("no longer listed upstream (left alone): %d" % len(gone))
    for d in new:
        print("  + %s (%s)" % (d, candidate[d]["severity"]))
    for d in escalations:
        print("  ^ %s (%s -> %s)" % (d, current[d].get("severity"), candidate[d]["severity"]))

    # The gate is on additions and escalations together, since both change what
    # federation does. Removals cannot be acted on, so they cannot be anomalous.
    changes = len(new) + len(escalations)
    ceiling = max(MAX_NEW_ABSOLUTE, int(len(current) * MAX_NEW_PCT / 100.0))
    print("changes: %d, ceiling: %d" % (changes, ceiling))

    if changes == 0:
        print("verdict=ok")
        print("nothing to do")
        return 0

    if changes > ceiling:
        print(
            "reason: %d changes is over the ceiling of %d (the larger of %d and "
            "%.0f%% of the %d currently blocked). Not applying this without a "
            "person." % (changes, ceiling, MAX_NEW_ABSOLUTE, MAX_NEW_PCT, len(current))
        )
        print("verdict=review")
        return 0

    print("verdict=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
