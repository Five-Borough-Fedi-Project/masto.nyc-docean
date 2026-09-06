#!/usr/bin/env bash
#
# Resolves the mastodon-large origin address and exports it as
# TF_VAR_large_node_ips for the database firewall rules.
#
# The address is dynamic, handed out by an ISP, and nobody knows when it
# changes. It is also the thing the Cloudflare tunnel exists to hide, so it must
# not appear in the repository, in a plan, or in an Actions log.
#
# Resolving here rather than with the Terraform dns provider keeps two things
# out of reach. The hostname never enters Terraform state, and a resolution
# failure prints this script's error rather than a provider error containing the
# hostname. Provider errors are not redacted, and since the hostname resolves to
# the address, leaking one leaks the other.
#
# Failure is fatal on purpose. digitalocean_database_firewall is authoritative:
# it reconciles the whole rule set, so an empty list does not mean "change
# nothing", it means "delete the rule" and cut mastodon-large off Postgres,
# Valkey and OpenSearch at once.

set -euo pipefail

host="${LARGE_NODE_HOSTNAME:-}"

if [ -z "$host" ]; then
  # No hostname configured. Fall back to a literal list so this can land before
  # the secret exists, and so a local run with terraform.tfvars still works.
  if [ -n "${TF_VAR_large_node_ips:-}" ]; then
    echo "LARGE_NODE_HOSTNAME is unset; using the TF_VAR_large_node_ips already in the environment." >&2
    exit 0
  fi
  echo "::error::Neither LARGE_NODE_HOSTNAME nor TF_VAR_large_node_ips is set. Refusing to continue, because an empty list deletes the firewall rule."
  exit 1
fi

ip="$(python3 - "$host" <<'PY'
import socket, sys
try:
    print(socket.gethostbyname(sys.argv[1]))
except Exception:
    # Deliberately says nothing about what failed to resolve.
    sys.exit(1)
PY
)" || {
  echo "::error::Could not resolve the mastodon-large hostname. Refusing to continue, because an empty firewall rule set cuts large off every managed database."
  exit 1
}

# Mask before the value can reach a log through any later command. Only under
# Actions: outside it the workflow command is noise that breaks `eval`.
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "::add-mask::${ip}"
fi

if ! printf '%s' "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo "::error::The hostname resolved to something that is not an IPv4 address."
  exit 1
fi

# A private or loopback answer means the DDNS is broken or a resolver is lying.
# Writing one of these into the allowlist would replace a working rule with a
# useless one, which is worse than stopping.
case "$ip" in
  10.*|127.*|169.254.*|192.168.*|0.*|255.*)
    echo "::error::The hostname resolved to a non-routable address. Refusing to use it."
    exit 1 ;;
  172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
    echo "::error::The hostname resolved to a non-routable address. Refusing to use it."
    exit 1 ;;
esac

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "TF_VAR_large_node_ips=[\"${ip}\"]" >> "$GITHUB_ENV"
  echo "Resolved the mastodon-large origin and exported it for this job." >&2
else
  # Local use: eval "$(./scripts/resolve-large-ip.sh)"
  echo "export TF_VAR_large_node_ips='[\"${ip}\"]'"
fi
