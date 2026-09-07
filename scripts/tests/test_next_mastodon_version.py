#!/usr/bin/env python3
"""Tests for the upgrade version picker. Run: python3 scripts/tests/test_next_mastodon_version.py"""
import importlib.util
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("nmv", root / "scripts" / "next-mastodon-version.py")
nmv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nmv)

TAGS = ["v4.7.0", "v4.7.1", "v4.7.2", "v4.7.3", "v4.8.0", "v4.8.1",
        "v4.6.5", "v4.9.0", "v4.8.0-beta.1", "not-a-version"]

CASES = [
    ("v4.7.0", TAGS, (4, 7, 3), "newest patch in the current minor, not v4.8"),
    ("v4.7.3", TAGS, (4, 8, 0), "at the top of a minor, take the lowest of the next"),
    ("v4.8.1", TAGS, (4, 9, 0), "crossing into the next minor"),
    ("v4.9.0", TAGS, None, "already on the newest"),
    ("v4.6.5", TAGS, (4, 7, 0), "two minors behind still moves exactly one minor"),
    ("v4.7.0", ["v4.7.0-beta.9", "v4.7.0"], None, "prereleases never count"),
    ("v4.7.0", [], None, "no releases at all"),
    ("v4.7.0", ["v4.7.0", "v4.7.0"], None, "duplicates collapse"),
]


def main():
    failures = 0
    for current, tags, want, why in CASES:
        got = nmv.pick(current, tags)
        ok = got == want
        failures += not ok
        print("  %s %-8s -> %-10s %s" % ("ok  " if ok else "FAIL", current, got, why))

    try:
        nmv.pick("garbage", TAGS)
        print("  FAIL an unparseable current version was accepted")
        failures += 1
    except ValueError:
        print("  ok   an unparseable current version is rejected")

    print("  %d failure(s)" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
