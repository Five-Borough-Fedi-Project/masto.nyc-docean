#!/usr/bin/env bash
# Moves the gitignored private-*.yaml files into their SOPS homes and encrypts
# them, so they can be committed and every clone becomes a backup.
#
# Requires sops and age. Reads your private keys from
# ~/.config/sops/age/. Nothing here prints a secret value.
#
# Idempotent: a file that is already encrypted is skipped.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/do-production.txt}"

command -v sops >/dev/null || { echo "!! sops is not installed" >&2; exit 69; }

# source path : destination path
map=(
  "k8s/secrets/private-configmap-env-secret.yaml:k8s/secrets/do-production/mastodon-env-secret.sops.yaml"
  "k8s/secrets/private-configmap-storage-backups.yaml:k8s/secrets/do-production/storage-backup.sops.yaml"
  "k8s/secrets/private-configmap-betterstack.yaml:k8s/secrets/do-production/postgres-completion.sops.yaml"
  "k8s/secrets/private-configmap-timeline-health.yaml:k8s/secrets/do-production/timeline-health-config.sops.yaml"
  "k8s/secrets/private-secret-sync-blocked-email-domains.yaml:k8s/secrets/do-production/sync-blocked-email-domains.sops.yaml"
  "k8s/secrets/private-secret-webhook-welcome.yaml:k8s/secrets/do-production/welcome-access.sops.yaml"
  "/media/seano/library/KeepSakes/k8s/ns-mastodon/private-configmap-env-secret.yaml:k8s/secrets/large/mastodon-env-secret.sops.yaml"
)

for pair in "${map[@]}"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  if [ ! -f "$src" ]; then
    echo "   skip, source missing: $src"
    continue
  fi
  if [ -f "$dst" ] && grep -q '^sops:' "$dst"; then
    echo "   already encrypted: $dst"
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  # .sops.yaml decides the recipients from the destination path
  sops --encrypt --in-place "$dst"
  grep -q '^sops:' "$dst" || { echo "!! encryption produced no sops block: $dst" >&2; exit 70; }
  echo "   encrypted: $dst"
done

echo
echo "Every file above is now safe to commit. Verify one with:"
echo "    sops --decrypt k8s/secrets/do-production/mastodon-env-secret.sops.yaml | head -5"
echo
echo "The originals are left in place. Delete them once you have confirmed a"
echo "decrypt round-trip and applied from the encrypted copies."
