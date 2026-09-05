#!/usr/bin/env bash
#
# Scales the Mastodon workloads down for an upgrade and back up afterwards.
# See docs/upgrade-runbook.md.
#
# Two things this guards against, both learned the hard way.
#
# The context is a required argument. The previous version ran plain `kubectl`
# against whatever context happened to be selected, and both clusters have a
# mastodon namespace holding deployments with the same names. A drain aimed at
# do-production would have taken down the cluster serving the site.
#
# Flux is suspended before scaling and resumed afterwards. Both clusters
# reconcile main every ten minutes and every deployment here declares its
# replica count in git, so an unsuspended Flux scales the site back up while
# the database is half migrated.
#
# Replica counts are not written down here. `fill` resumes Flux and lets it
# restore them from git, which is the only copy that stays correct when a
# deployment changes.

set -euo pipefail

NS=mastodon
SELECTOR='app.kubernetes.io/name=mastodon'

usage() {
  cat >&2 <<EOF
Usage: ${0##*/} <prepare|drain|fill> <do|lab>

  prepare   scale the Mastodon workloads to 0, leaving the scheduler running
  drain     scale the Mastodon workloads to 0, scheduler included
  fill      resume Flux and let it restore the replica counts from git

  do        the DigitalOcean cluster
  lab       the bare-metal cluster running 'large'

Selects deployments by ${SELECTOR}, so nginx, the tunnels,
libretranslate and welcome-webhook keep running.
EOF
  exit 64
}

[ $# -eq 2 ] || usage
action=$1
context=$2

case "$action" in prepare|drain|fill) ;; *) usage ;; esac
case "$context" in do|lab) ;; *) echo "Unknown context '$context'." >&2; usage ;; esac

command -v flux >/dev/null || { echo "flux is not on PATH." >&2; exit 1; }
kubectl config get-contexts -o name | grep -qx "$context" \
  || { echo "kubectl has no context named '$context'." >&2; exit 1; }

k() { kubectl --context="$context" -n "$NS" "$@"; }

# Say out loud which cluster is about to be changed. The whole point of the
# required argument is defeated if nobody reads what it selected.
echo "cluster:  $context"
echo "nodes:    $(kubectl --context="$context" get nodes -o name | sed 's|node/||' | tr '\n' ' ')"

deployments=$(k get deploy -l "$SELECTOR" -o name)
[ -n "$deployments" ] || { echo "No deployments match ${SELECTOR}." >&2; exit 1; }

if [ "$action" = "prepare" ]; then
  deployments=$(k get deploy -l "$SELECTOR" -o name \
    | grep -v 'sidekiq-sched' || true)
fi

echo "affects:  $(echo "$deployments" | sed 's|deployment.apps/||' | tr '\n' ' ')"
echo

case "$action" in
  prepare|drain)
    echo "Suspending Flux so it does not scale these back up."
    flux --context="$context" suspend kustomization apps

    # shellcheck disable=SC2086
    k scale $deployments --replicas=0
    echo
    echo "Scaled to 0. Flux is suspended; run '${0##*/} fill $context' to undo both."
    ;;

  fill)
    echo "Resuming Flux. It restores the replica counts from git."
    flux --context="$context" resume kustomization apps
    flux --context="$context" reconcile kustomization apps --with-source
    echo
    k get deploy -l "$SELECTOR"
    ;;
esac
