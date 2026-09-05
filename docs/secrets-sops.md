# Encrypted secrets

Secrets live in the repository, encrypted with SOPS. Every clone is a backup,
which is the point: before this, seven files existed in exactly one place and
losing that machine meant losing `SECRET_KEY_BASE` and the
`ACTIVE_RECORD_ENCRYPTION_*` keys, and with them every existing 2FA enrollment
and push subscription.

## Two keys, one per cluster

`.sops.yaml` routes by path:

| path | encrypted to |
|---|---|
| `k8s/secrets/shared/` | both keys |
| `k8s/secrets/do-production/` | the do key |
| `k8s/secrets/large/` | the large key |

Compromising the bare-metal cluster does not hand over the DigitalOcean tunnel
credentials, and the reverse holds too. One key would also work and take less
setup; two costs a `.sops.yaml` stanza and buys that separation.

`encrypted_regex` covers only `data` and `stringData`. `apiVersion`, `kind` and
`metadata` stay readable, so a reviewer can see which Secret a file defines and
which keys it sets without reading any value. Flux needs that as well, since it
matches resources by name before decrypting.

## Setup, once

```sh
sudo apt install age
# sops is not packaged on Debian; take the release binary
# https://github.com/getsops/sops/releases
```

Keys live in `~/.config/sops/age/`. Concatenate both into the path sops reads
by default, so one command can decrypt either cluster's files:

```sh
cat ~/.config/sops/age/do-production.txt ~/.config/sops/age/large.txt \
  > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

Encryption needs no private key; the recipients come from `.sops.yaml`.

Back up both private keys somewhere off this machine. They are now the single thing standing between a lost laptop and
unrecoverable secrets, which is a smaller surface than seven files but not zero.

## First encryption

```sh
./scripts/encrypt-secrets.sh
```

It copies each gitignored `private-*.yaml` to its SOPS home, encrypts in place,
and refuses to continue if a file comes out without a `sops:` block. It skips
anything already encrypted, so running it twice is safe.

Confirm a round trip before deleting the originals:

```sh
sops --decrypt k8s/secrets/do-production/mastodon-env-secret.sops.yaml | head -5
```

## Editing a secret

```sh
sops k8s/secrets/do-production/mastodon-env-secret.sops.yaml
```

Opens your editor with the values decrypted, re-encrypts on save. Never decrypt
to a file and edit that; a stray plaintext copy is how this goes wrong.

## Applying

Flux does this. Since 2026-09-05 its kustomize-controller decrypts during
reconciliation, so merging an encrypted change to `main` is how a secret gets
into a cluster.

The manual path still works and is worth knowing for a cluster with Flux
suspended:

```sh
sops --decrypt k8s/secrets/do-production/mastodon-env-secret.sops.yaml \
  | kubectl --context=do -n mastodon apply -f -
```

## How Flux decrypts

The private key lives in each cluster as a Secret named `sops-age`, referenced
by the `secrets` Kustomization:

```yaml
decryption:
  provider: sops
  secretRef:
    name: sops-age
```

That Secret was created out of band, once per cluster, and is deliberately the
one thing not in git. Recreating it is the first half of `docs/flux-bootstrap.md`.

If it is missing, the `secrets` Kustomization reports
`secrets "sops-age" not found` and `apps` refuses to proceed because it declares
`dependsOn: secrets`. Nothing half-applies, which is the behaviour you want.

## Two secrets existed only in the cluster

`welcome-access` and `sync-blocked-email-domains` had files in the repository,
but both were commented out end to end: zero parseable documents. The Secrets
existed in the cluster and nowhere else, so the phase 0 backup covered files
that could not recreate them. Losing the cluster would have lost both.

They were exported from the live cluster on 2026-09-05, stripped of runtime
metadata, encrypted and committed. If you ever wonder whether a `private-*`
file is real, check that it parses rather than that it exists.

## Known duplication

`mastodon-env-secret` exists twice: do-production's carries app identity, and
large's carries the same identity plus its own database endpoints, 53 keys
against 42. Roughly thirty values are therefore maintained in two files and
must match. If they drift, sessions break on one cluster, or 2FA does, or push
notifications do, and it presents as intermittent because it depends which
tunnel served the request.

The fix is to split large's file into a shared identity secret and a small
cluster-specific database secret, giving both clusters the same
`envFrom: [shared, cluster-db]` shape. That is a change to how large's web pods
read configuration, so it is deliberately not bundled with the move to SOPS.
Do it once encryption is proven.
