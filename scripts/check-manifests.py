#!/usr/bin/env python3
"""Assertions run against a rendered kustomize build.

Both checks exist because kubectl accepted something it should not have.

Namespaces: on 2026-09-04 a Secret carrying production credentials was applied
without one and landed in `default`, because the file declared no namespace and
the command omitted -n. It was caught twenty seconds later by luck.

Pinning: a tag can be moved by whoever owns it. `filefrog/k8s-hacks:pause` and
`eeshugerman/postgres-backup-s3:16` both passed an earlier version of this check
that only rejected `:latest`, and both float.

Usage: kubectl kustomize <path> | check-manifests.py <label>
"""
import re
import sys

import yaml

# Kinds that must not carry a namespace. Anything else must.
CLUSTER_SCOPED = {
    "Namespace",
    "ClusterRole",
    "ClusterRoleBinding",
    "CustomResourceDefinition",
    "StorageClass",
    "APIService",
    "PriorityClass",
}


def walk_containers(doc):
    """Yield (owner, image) for every container in a doc, whatever wraps it."""
    spec = doc.get("spec") or {}
    templates = [spec.get("template")]
    job = (spec.get("jobTemplate") or {}).get("spec") or {}
    templates.append(job.get("template"))
    owner = "%s/%s" % (doc.get("kind"), (doc.get("metadata") or {}).get("name"))
    for tmpl in templates:
        if not tmpl:
            continue
        pod = tmpl.get("spec") or {}
        for c in (pod.get("containers") or []) + (pod.get("initContainers") or []):
            yield owner, c.get("image", "")


def is_pinned(image):
    # A digest is immutable, full stop.
    if "@sha256:" in image:
        return True
    ref = image.rsplit("/", 1)[-1]
    tag = ref.split(":", 1)[1] if ":" in ref else ""
    # A version tag pins if it carries at least major.minor. A 40 character hex
    # tag is a commit, which is immutable too. Anything else (`latest`,
    # `alpine`, `pause`, a bare major like `16`) moves without the manifest
    # changing.
    return bool(re.fullmatch(r"v?\d+\.\d+.*", tag) or re.fullmatch(r"[0-9a-f]{40}", tag))


def main():
    label = sys.argv[1] if len(sys.argv) > 1 else "manifests"
    docs = [d for d in yaml.safe_load_all(sys.stdin) if d]

    # An empty stdin used to pass: nothing to check means nothing to complain
    # about, and the script printed "0 objects" and exited 0. A broken pipe or a
    # kustomize build that rendered nothing would have gone green in CI.
    if not docs:
        print("%s: nothing on stdin. Expected `kubectl kustomize <path> |`." % label)
        return 1

    problems = []

    for d in docs:
        kind = d.get("kind")
        md = d.get("metadata") or {}
        if kind in CLUSTER_SCOPED:
            if "namespace" in md:
                problems.append("%s/%s is cluster-scoped but sets a namespace" % (kind, md.get("name")))
        elif not md.get("namespace"):
            problems.append("%s/%s has no namespace" % (kind, md.get("name")))

        for owner, image in walk_containers(d):
            if not is_pinned(image):
                problems.append("%s uses %r, which is not pinned" % (owner, image))

    if problems:
        print("%s: %d problem(s)" % (label, len(problems)))
        for p in problems:
            print("  " + p)
        return 1

    print("%s: %d objects, all namespaced correctly, every image pinned" % (label, len(docs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
