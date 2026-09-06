#!/usr/bin/env python3
"""Dump the Cloudflare configuration to JSON so it can be diffed and reviewed.

This is deliberately not Terraform. Terraform is a control plane, and an apply
that gets DNS wrong takes the site off the internet. The point here is to be able
to read the configuration, see what changed and when, and hand the whole thing to
something that can spot a bad setting. All of that wants a read-only token and no
ability to write at all.

It also captures more than a provider can model: zone settings, Workers routes,
account membership, and which managed rulesets are enabled. Terraform would show
none of that.

The output is committed, so the git history becomes the change log the Cloudflare
dashboard does not keep, and a diff on a scheduled run is the drift alert.

Usage:
    CLOUDFLARE_API_TOKEN=... ./scripts/cloudflare-snapshot.py [--out cloudflare/snapshot]

Reads the token from terraform.tfvars when the environment does not carry one,
so a local run needs no setup.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

API = "https://api.cloudflare.com/client/v4/"

# Fields that change on every read and would make every diff noise.
VOLATILE = {"modified_on", "created_on", "last_modified", "uploaded_on", "modified_at",
            "created_at", "checked_on", "version", "last_updated"}

# Values that must never be committed. The WAF has a rule that skips the firewall
# for requests carrying a shared header, and that header's value sits in the rule
# expression in plain text.
SECRET_KEYS = re.compile(r"secret|token|password|api_key|private", re.I)
SECRET_LITERAL = re.compile(r'"([A-Za-z0-9_\-]{16,})"')


def api(token, path):
    out = subprocess.run(
        ["curl", "-sS", "--max-time", "45", "-H", "Authorization: Bearer " + token, API + path],
        capture_output=True, text=True).stdout
    try:
        d = json.loads(out)
    except Exception:
        return None, "unparseable response"
    if not d.get("success"):
        return None, (d.get("errors") or [{}])[0].get("message", "unknown error")
    return d.get("result"), None


def scrub(obj, in_expression=False):
    """Strip volatile fields and redact anything that looks like a credential."""
    if isinstance(obj, dict):
        out = {}
        for k, v in sorted(obj.items()):
            if k in VOLATILE:
                continue
            if SECRET_KEYS.search(k) and isinstance(v, str) and v:
                out[k] = "<redacted>"
                continue
            out[k] = scrub(v, in_expression or k == "expression")
        return out
    if isinstance(obj, list):
        return [scrub(v, in_expression) for v in obj]
    if isinstance(obj, str) and in_expression:
        # A rule expression can carry a shared secret as a literal.
        return SECRET_LITERAL.sub('"<redacted>"', obj)
    return obj


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="cloudflare/snapshot")
    ap.add_argument("--zone", default="masto.nyc")
    args = ap.parse_args()

    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    if not token:
        tfvars = pathlib.Path("terraform.tfvars")
        if tfvars.exists():
            m = re.search(r'^\s*cloudflare_api_token\s*=\s*"([^"]+)"', tfvars.read_text(), re.M)
            if m:
                token = m.group(1)
    if not token:
        print("No CLOUDFLARE_API_TOKEN and none in terraform.tfvars.", file=sys.stderr)
        return 1

    zones, err = api(token, "zones?name=" + args.zone)
    if err or not zones:
        print("Could not read the zone: %s" % (err or "not found"), file=sys.stderr)
        return 1
    zid, aid = zones[0]["id"], zones[0]["account"]["id"]

    # Split by concern so a diff points at what moved rather than one huge file.
    groups = {
        "dns": [("records", "zones/%s/dns_records?per_page=500" % zid)],
        "load-balancing": [
            ("load_balancers", "zones/%s/load_balancers" % zid),
            ("pools", "accounts/%s/load_balancers/pools" % aid),
            ("monitors", "accounts/%s/load_balancers/monitors" % aid),
        ],
        "rules": [
            ("rulesets", "zones/%s/rulesets" % zid),
            ("page_rules", "zones/%s/pagerules" % zid),
            ("firewall_access_rules", "zones/%s/firewall/access_rules/rules" % zid),
            ("waiting_rooms", "zones/%s/waiting_rooms" % zid),
        ],
        "zone": [
            ("settings", "zones/%s/settings" % zid),
            ("workers_routes", "zones/%s/workers/routes" % zid),
        ],
        "account": [
            ("notification_policies", "accounts/%s/alerting/v3/policies" % aid),
            ("tunnels", "accounts/%s/cfd_tunnel?is_deleted=false" % aid),
            ("r2_buckets", "accounts/%s/r2/buckets" % aid),
            ("members", "accounts/%s/members" % aid),
        ],
    }

    outdir = pathlib.Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    problems = []

    for group, endpoints in groups.items():
        data = {}
        for name, path in endpoints:
            result, err = api(token, path)
            if err:
                problems.append("%s/%s: %s" % (group, name, err))
                continue
            data[name] = scrub(result)

        # Ruleset listings omit the rules themselves, so each one has to be
        # fetched. Only the zone-owned ones: the managed rulesets are
        # Cloudflare's WAF catalogue, thousands of rules nobody here writes or
        # can change, and expanding them buries the handful of real rules in
        # 600KB that re-diffs whenever Cloudflare ships an update. Their
        # metadata is kept so a newly enabled managed ruleset still shows up.
        if group == "rules" and "rulesets" in data:
            expanded = []
            for rs in data["rulesets"]:
                if rs.get("kind") != "zone":
                    expanded.append(rs)
                    continue
                full, err = api(token, "zones/%s/rulesets/%s" % (zid, rs["id"]))
                expanded.append(scrub(full) if full else rs)
                if err:
                    problems.append("ruleset %s: %s" % (rs.get("id"), err))
            data["rulesets"] = expanded

        path = outdir / ("%s.json" % group)
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
        n = sum(len(v) if isinstance(v, list) else 1 for v in data.values())
        print("  %-16s %3d objects -> %s" % (group, n, path))

    for p in problems:
        print("  note: %s" % p, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
