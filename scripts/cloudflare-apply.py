#!/usr/bin/env python3
"""Make the pending Cloudflare changes over the API, so nobody has to find them.

The dashboard moves things and renames them, and the token editor's permission
labels do not match the API paths, so "turn on Page Shield" is a scavenger hunt.
Every change here is one HTTP call. If the token is missing a permission the
call returns 403 and this prints the permission that call needs.

Nothing happens without --apply. By default it reads the current value of each
item and prints what would change.

    ./scripts/cloudflare-apply.py                    # show everything
    ./scripts/cloudflare-apply.py --apply page-shield zone-hold

Reads CLOUDFLARE_API_TOKEN, or cloudflare_api_token from terraform.tfvars.

The items are deliberately individually named. Several of them are judgement
calls rather than obvious wins, and running everything at once is not a thing
this should make easy.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

API = "https://api.cloudflare.com/client/v4/"


def call(token, method, path, body=None):
    cmd = ["curl", "-sS", "--max-time", "45", "-X", method,
           "-H", "Authorization: Bearer " + token, API + path]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "--data", json.dumps(body)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    try:
        d = json.loads(out)
    except Exception:
        return None, "unparseable response: %s" % out[:200]
    if not d.get("success"):
        errs = d.get("errors") or [{}]
        return None, "; ".join("%s (%s)" % (e.get("message"), e.get("code")) for e in errs)
    return d.get("result"), None


class Item:
    """One change: how to read it, how to write it, and what permission that needs."""

    def __init__(self, key, what, permission, read, write, describe=None):
        self.key, self.what, self.permission = key, what, permission
        self._read, self._write = read, write
        self._describe = describe or (lambda v: json.dumps(v))

    def current(self, ctx):
        return self._read(ctx)

    def apply(self, ctx):
        return self._write(ctx)


def build_items(zid, aid):
    def setting(name):
        return lambda c: call(c["t"], "GET", "zones/%s/settings/%s" % (zid, name))[0]

    def set_setting(name, value):
        return lambda c: call(c["t"], "PATCH", "zones/%s/settings/%s" % (zid, name),
                              {"value": value})

    items = [
        Item("page-shield", "Page Shield on",
             "Zone -> Page Shield -> Edit",
             lambda c: call(c["t"], "GET", "zones/%s/page_shield" % zid)[0],
             lambda c: call(c["t"], "PUT", "zones/%s/page_shield" % zid, {"enabled": True}),
             lambda v: "enabled" if (v or {}).get("enabled") else "off"),

        Item("zone-hold", "Zone hold on, so the domain cannot be moved out by accident",
             "Zone -> Zone -> Edit",
             lambda c: call(c["t"], "GET", "zones/%s/hold" % zid)[0],
             lambda c: call(c["t"], "POST", "zones/%s/hold" % zid, None),
             lambda v: "held" if (v or {}).get("hold") else "not held"),

        Item("ssl-strict", "SSL mode Full (strict)",
             "Zone -> Zone Settings -> Edit",
             setting("ssl"), set_setting("ssl", "strict"),
             lambda v: str((v or {}).get("value"))),

        Item("rocket-loader-off", "Rocket Loader off, it reorders JavaScript under a React app",
             "Zone -> Zone Settings -> Edit",
             setting("rocket_loader"), set_setting("rocket_loader", "off"),
             lambda v: str((v or {}).get("value"))),
    ]

    # The cache rule is the only one that writes a ruleset rather than a flag.
    # It deliberately sets no edge_ttl: Mastodon sends max-age 3 days on a hit
    # and 180 seconds on 404/410, and overriding that would cache a new
    # account's 404 and make it unresolvable from remote instances for days.
    #
    # It names four paths instead of matching /.well-known/* as a prefix. Two
    # other things live under that prefix: /.well-known/assetlinks.json is served
    # by the masto-nyc-assetlinks Worker, and /.well-known/change-password is a
    # 301 carrying no-cache. Cache Rules are evaluated before Workers run, so a
    # prefix match would have changed the caching of a Worker response that was
    # never measured. These four are the ones checked, and all four return
    # max-age=259200, public with cf-cache-status DYNAMIC.
    WELLKNOWN = ["/.well-known/webfinger", "/.well-known/host-meta",
                 "/.well-known/host-meta.json", "/.well-known/nodeinfo"]
    rule = {
        "action": "set_cache_settings",
        "description": "Cache the cacheable .well-known paths, honouring origin cache-control",
        "enabled": True,
        "expression": "http.request.uri.path in {%s}" % " ".join(
            '"%s"' % p for p in WELLKNOWN),
        "action_parameters": {
            "cache": True,
            "edge_ttl": {"mode": "respect_origin"},
            "browser_ttl": {"mode": "respect_origin"},
        },
    }

    def read_cache_rules(c):
        rs, err = call(c["t"], "GET", "zones/%s/rulesets" % zid)
        if err:
            return None
        for r in rs:
            if r.get("phase") == "http_request_cache_settings" and r.get("kind") == "zone":
                full, e = call(c["t"], "GET", "zones/%s/rulesets/%s" % (zid, r["id"]))
                return full if not e else None
        return None

    def write_cache_rule(c):
        existing = read_cache_rules(c)
        if existing is None:
            return None, "no zone cache ruleset to add to"
        rules = existing.get("rules") or []
        if any(rule["expression"] == (x.get("expression") or "") for x in rules):
            return existing, None
        return call(c["t"], "PUT", "zones/%s/rulesets/%s" % (zid, existing["id"]),
                    {"rules": rules + [rule]})

    items.append(Item(
        "wellknown-cache-rule",
        "Cache rule for /.well-known/*, respecting the origin's cache-control",
        "Zone -> Cache Rules -> Edit  (sometimes listed as Cache Settings)",
        read_cache_rules, write_cache_rule,
        lambda v: "%d rule(s) in the cache phase" % len((v or {}).get("rules") or [])))

    for name in ("page-replica-mastonyc", "page-replica-rw"):
        items.append(Item(
            "delete-worker-" + name,
            "Delete the unrouted Worker %s" % name,
            "Account -> Workers Scripts -> Edit",
            (lambda n: lambda c: call(c["t"], "GET", "accounts/%s/workers/scripts" % aid)[0] and
             next((s for s in call(c["t"], "GET", "accounts/%s/workers/scripts" % aid)[0]
                   if s["id"] == n), None))(name),
            (lambda n: lambda c: call(c["t"], "DELETE",
                                      "accounts/%s/workers/scripts/%s" % (aid, n)))(name),
            lambda v: "present" if v else "already gone"))

    # Cleanup, from the measurements in docs/improvement-plan.md.
    #
    # The two dev hostnames are R2 custom domains on a February 2023 bucket.
    # Over 24 hours they took 2,339 requests and returned zero 200s; every path
    # was a WordPress probe. The custom domain binding comes off first, because
    # deleting the DNS record under a live binding leaves the bucket holding a
    # domain that no longer resolves.
    def hostname_item(host, bucket):
        def read(c):
            rs, err = call(c["t"], "GET", "zones/%s/dns_records?per_page=500" % zid)
            if err:
                return None
            return next((r for r in rs if r["name"] == host), None)

        def write(c):
            _, err = call(c["t"], "DELETE",
                          "accounts/%s/r2/buckets/%s/domains/custom/%s" % (aid, bucket, host))
            # Already unbound is fine. Anything else is worth stopping for.
            if err and not any(x in err.lower() for x in ("not found", "does not exist", "10006")):
                return None, "unbinding the R2 custom domain: %s" % err
            rec = read(c)
            if rec is None:
                return None, None
            return call(c["t"], "DELETE", "zones/%s/dns_records/%s" % (zid, rec["id"]))

        return Item("delete-hostname-" + host.split(".masto")[0],
                    "Remove %s: R2 custom domain binding, then the DNS record" % host,
                    "Zone -> DNS -> Edit  and  Account -> Workers R2 Storage -> Edit",
                    read, write,
                    lambda v: ("%s, proxied=%s" % (v["type"], v.get("proxied"))) if v else "already gone")

    for host in ("cdn-dev.masto.nyc", "cdn.dev.masto.nyc"):
        items.append(hostname_item(host, "mastodev"))

    # Both hold zero objects, measured via r2StorageAdaptiveGroups. Neither is
    # the Postgres backup target despite the name: backups go to DigitalOcean
    # Spaces, confirmed from the running cronjob and a completed run.
    def bucket_item(b):
        def read(c):
            r, err = call(c["t"], "GET", "accounts/%s/r2/buckets" % aid)
            if err:
                return None
            return next((x for x in (r or {}).get("buckets", []) if x["name"] == b), None)

        def write(c):
            # R2 refuses to delete a non-empty bucket, which is the safety net
            # that matters: if either has gained objects since this was written,
            # the call fails instead of destroying them.
            return call(c["t"], "DELETE", "accounts/%s/r2/buckets/%s" % (aid, b))

        return Item("delete-bucket-" + b, "Delete the empty R2 bucket %s" % b,
                    "Account -> Workers R2 Storage -> Edit",
                    read, write,
                    lambda v: ("present, created %s" % (v.get("creation_date") or "?")[:10]) if v else "already gone")

    for b in ("mastodon-postgres", "mastodon-snapshooter"):
        items.append(bucket_item(b))

    return items


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("items", nargs="*", help="which to act on; default is all, read-only")
    ap.add_argument("--apply", action="store_true", help="actually make the changes")
    ap.add_argument("--zone", default="masto.nyc")
    args = ap.parse_args()

    token = os.environ.get("CLOUDFLARE_API_TOKEN", "")
    if not token:
        tf = pathlib.Path("terraform.tfvars")
        if tf.exists():
            m = re.search(r'^\s*cloudflare_api_token\s*=\s*"([^"]+)"', tf.read_text(), re.M)
            if m:
                token = m.group(1)
    if not token:
        print("No CLOUDFLARE_API_TOKEN, and none in terraform.tfvars.", file=sys.stderr)
        return 1

    zones, err = call(token, "GET", "zones?name=" + args.zone)
    if err or not zones:
        print("Could not read the zone: %s" % (err or "not found"), file=sys.stderr)
        return 1
    zid, aid = zones[0]["id"], zones[0]["account"]["id"]
    ctx = {"t": token}

    items = build_items(zid, aid)
    if args.items:
        known = {i.key for i in items}
        unknown = set(args.items) - known
        if unknown:
            print("Unknown: %s" % ", ".join(sorted(unknown)), file=sys.stderr)
            print("Known:   %s" % ", ".join(sorted(known)), file=sys.stderr)
            return 1
        items = [i for i in items if i.key in args.items]

    if not args.apply:
        print("Reading only. Add --apply and the names of the items to change.\n")

    # The question this script exists to answer is "what do I tick in the token
    # editor". Print it as a deduplicated list, scoped, so it can be worked
    # through top to bottom.
    def permission_summary(sel):
        # One item can need a row from each scope, so split before grouping.
        rows = {r.strip() for i in sel for r in i.permission.split(" and ")}
        zone = sorted(r for r in rows if r.startswith("Zone"))
        acct = sorted(r for r in rows if r.startswith("Account"))
        print("Token permissions for %s:" % (", ".join(i.key for i in sel)
                                             if len(sel) < 4 else "these items"))
        if zone:
            print("  Zone resources: Include -> Specific zone -> %s" % args.zone)
            for x in zone:
                print("    %s" % x)
        if acct:
            print("  Account resources: Include -> the account owning that zone")
            for x in acct:
                print("    %s" % x)
        print("  Nothing else. Every call this makes is covered by the rows above.\n")

    permission_summary(items)

    failures = 0
    for i in items:
        print("%s" % i.key)
        print("  what:    %s" % i.what)
        try:
            print("  now:     %s" % i._describe(i.current(ctx)))
        except Exception as e:
            print("  now:     could not read (%s)" % e)

        if not args.apply:
            print("  needs:   %s\n" % i.permission)
            continue

        result, err = i.apply(ctx)
        if err:
            failures += 1
            print("  FAILED:  %s" % err)
            print("  needs:   %s" % i.permission)
            if "Unauthorized" in err or "Authentication" in err or "10000" in err:
                print("           ^ that is a permissions error. Add the row above.")
        else:
            print("  done:    %s" % i._describe(i.current(ctx)))
        print()

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
