#!/usr/bin/env bash
# Converts a gitignored private-*.yaml ConfigMap into a Secret, in place.
#
# Only two of the private files hold credentials and need this:
#
#   kubernetes/mastodon/private-configmap-env-secret.yaml    (SECRET_KEY_BASE,
#       OTP_SECRET, VAPID_PRIVATE_KEY, ACTIVE_RECORD_ENCRYPTION_*, SMTP_PASSWORD,
#       AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
#   kubernetes/cronjobs/private-configmap-storage-backups.yaml  (Spaces keys)
#
# Do NOT run it on:
#   private-configmap-betterstack.yaml    -- a shell script mounted as a volume;
#                                            must stay a ConfigMap
#   private-configmap-timeline-health.yaml -- no credentials; the cronjob still
#                                            references it with configMapRef
#
# A timestamped .bak is written next to each file before it is touched. The
# script never prints file contents.
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: $0 <private-configmap.yaml> [...]" >&2
  exit 64
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "!! not found: $f" >&2
    exit 66
  fi

  if ! grep -q '^kind: ConfigMap$' "$f"; then
    echo "!! $f is not a plain 'kind: ConfigMap' document -- skipping" >&2
    continue
  fi

  bak="$f.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak"

  sed -i \
    -e 's/^kind: ConfigMap$/kind: Secret/' \
    -e 's/^data:$/type: Opaque\nstringData:/' \
    "$f"

  # stringData takes plain strings and lets Kubernetes do the base64, so the
  # values carry over from the ConfigMap unchanged.
  if python3 -c "import sys,yaml; d=yaml.safe_load(open('$f')); sys.exit(0 if d.get('kind')=='Secret' and 'stringData' in d else 1)"; then
    echo "ok  $f  (backup: $bak)"
  else
    echo "!! conversion produced unexpected output, restoring $f" >&2
    mv "$bak" "$f"
    exit 70
  fi
done

echo
echo "Next: apply these, then roll the workloads. See docs/secrets-rollout.md."
