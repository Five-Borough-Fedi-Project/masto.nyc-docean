#!/usr/bin/env python3
"""Refuse to believe a bad blocklist fetch.

IFTAS serves its denylists from Google Sheets. That endpoint sends
`cache-control: no-store` and no ETag, so there is no conditional request to
make and the workflow has to fetch the whole thing and diff it. It can also
serve an HTML error page or a truncated sheet when throttled, and a naive diff
of that against the committed snapshot reads as "remove every block" -- a pull
request proposing to unblock the entire list.

So nothing becomes a proposal until it passes here.

Usage: check-blocklist.py CANDIDATE [SNAPSHOT]

Prints a summary and the added/removed domains on stdout, for the pull request
body. Exits non-zero if the candidate fails any check, which fails the job.
"""
import csv
import os
import sys

# The canary is IFTAS's own, a row for `cariad.invalid` in an invalid TLD
# carrying `iftas:canary`. It is in every one of their lists. If it survived
# the fetch and the merge, the pipeline moved real data end to end. It is also
# what you look for in the instance's own domain_blocks to confirm a push
# landed, which is cheaper than any watchdog.
CANARY = "cariad.invalid"

# A floor, not a guess at the real size. The merged list was 204 domains on
# 2026-10-09. Fifty is low enough never to trip on genuine shrinkage and high
# enough to catch an error page, an empty sheet, or one source silently
# dropping out of the merge.
MIN_ROWS = 50

# Additions are the normal business of a blocklist and arrive unreviewed by us
# but reviewed by IFTAS. Removals are the dangerous direction: every removal is
# a domain this instance would stop blocking. Ten percent of the current list
# is far more than any real week and far less than the cliff a bad fetch
# produces.
MAX_REMOVAL_PCT = 10.0

EXPECTED_HEADER = ["domain", "severity", "public_comment"]


def read_domains(path):
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames != EXPECTED_HEADER:
            raise ValueError(
                "header is %r, expected %r. A Google Sheets error page or a "
                "config change in blocklist/sources.toml both look like this."
                % (reader.fieldnames, EXPECTED_HEADER)
            )
        rows = {r["domain"]: r for r in reader if r.get("domain")}
    return rows


def read_allowlist(path):
    if not os.path.exists(path):
        return set()
    with open(path, newline="", encoding="utf-8") as fh:
        return {r["domain"] for r in csv.DictReader(fh) if r.get("domain")}


def main(argv):
    if not 2 <= len(argv) <= 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    candidate, snapshot = argv[1], argv[2] if len(argv) == 3 else None
    failures = []

    try:
        new = read_domains(candidate)
    except (ValueError, OSError) as exc:
        print("FAIL: %s" % exc)
        return 1

    print("candidate: %d domains" % len(new))

    if len(new) < MIN_ROWS:
        failures.append(
            "only %d domains, floor is %d. Suspect a failed or partial fetch "
            "rather than a real shrinkage." % (len(new), MIN_ROWS)
        )

    if CANARY not in new:
        failures.append(
            "canary %r is missing. Every IFTAS list carries it, so its absence "
            "means the fetch or the merge lost rows." % CANARY
        )

    # The allowlist is the whole exception mechanism, and a silent failure of it
    # is the worst outcome here: a domain a moderator decided to allow gets
    # suspended anyway. fediblockhole matches domains exactly, so an entry only
    # protects the exact string -- a list adding `www.example.com` is not
    # covered by an allowlist entry for `example.com`.
    # Resolved from this script's own location rather than the working
    # directory. A cwd-relative lookup that silently finds nothing would turn
    # this check into a no-op, which is the one failure mode it cannot have.
    allowlist_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "blocklist",
        "allowlist.csv",
    )
    if not os.path.exists(allowlist_path):
        print("FAIL: no allowlist at %s" % allowlist_path)
        return 1
    allowed = read_allowlist(allowlist_path)
    leaked = sorted(allowed & set(new))
    if leaked:
        failures.append(
            "allowlisted domains present in the merged list: %s. The allowlist "
            "was not applied." % ", ".join(leaked)
        )
    else:
        print("allowlist: %d entries, none present in the merged list" % len(allowed))

    added = removed = []
    if snapshot and os.path.exists(snapshot):
        old = read_domains(snapshot)
        added = sorted(set(new) - set(old))
        removed = sorted(set(old) - set(new))
        print("snapshot: %d domains" % len(old))
        print("added: %d" % len(added))
        print("removed: %d" % len(removed))
        if old:
            pct = 100.0 * len(removed) / len(old)
            if pct > MAX_REMOVAL_PCT:
                failures.append(
                    "%d of %d domains (%.1f%%) would stop being blocked, over "
                    "the %.1f%% ceiling. Refusing to propose this."
                    % (len(removed), len(old), pct, MAX_REMOVAL_PCT)
                )
        for label, items in (("+", added), ("-", removed)):
            for d in items:
                print("  %s %s" % (label, d))
    else:
        print("no snapshot to compare against; this is a first run")

    if failures:
        print()
        for f in failures:
            print("FAIL: %s" % f)
        return 1

    print()
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
