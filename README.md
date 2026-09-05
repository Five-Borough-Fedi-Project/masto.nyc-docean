# Howdy! 

This is the github repo for the [masto.nyc](https://masto.nyc/about) v2.0 infrastructure. This is essentially what the [old kubernetes-only code](https://github.com/Five-Borough-Fedi-Project/masto.nyc) looks like now that it's migrated to Digital Ocean. It's pretty quiet here, but feel free to open an issue or reach out to us on mastodon. We'll try and keep todo items in the issues list.

## Why Digital Ocean?

Since we came from a bare metal Kubernetes setup, we wanted to maintain as much of that infrastructure as possible- and we also wanted to follow our server principals of supporting NYC-based companies whenever possible. Luckily, Digital Ocean not only offered a k8s package but is also based out of NYC!

## Deployment

Both clusters run [Flux](https://fluxcd.io/). **Merging to `main` deploys.**
Manual `kubectl` changes get reverted within ten minutes. OpenTofu plans on every
PR and applies on merge behind an approval gate.

## Flux

Contexts are `do` and `lab`. **Always pass `--context`.** Both clusters have a
`mastodon` namespace with identically named objects.

```sh
flux --context=do get kustomizations                           # is it reconciling
flux --context=do reconcile kustomization apps --with-source   # deploy now
flux --context=do suspend kustomization apps                   # stop it reverting you
flux --context=do resume kustomization apps
flux --context=do events --for Kustomization/apps              # why it failed
kubectl --context=do diff -k k8s/clusters/do-production        # cluster vs repo
```

**Suspend both clusters before a Mastodon upgrade**, or Flux scales the site
back up mid-migration. See `docs/upgrade-runbook.md`.

## docs/

**AI slop.** Written by an LLM, unedited. The commands and numbers were checked
against the live clusters when written. Trust those, ignore the prose.

## Setup instructions:

**Use OpenTofu 1.8 or newer.** The backend block in `provider.tf` references variables, which OpenTofu supports as of 1.8 and HashiCorp Terraform does not support at all. `terraform init` will reject this repo.

1. In the DOcean console, generate a new [Personal access token](https://cloud.digitalocean.com/account/api/tokens). Put them aside for later.
2. From that page, click on the "Spaces Keys" tab and create a new set of s3 creds for the state. Put them aside for later.
3. Create a `terraform.tfvars` file. Populate it with the correct `do_token` (from step 1), `state_bucket`, and `state_key` variables.
4. Run the following command to initialize the state with your s3 creds (from step 2): `tofu init -backend-config="secret_key=YOURSECRETKEY" -backend-config="access_key=YOURACCESSKEY"`
5. [Follow these steps to set up kubectl.](https://docs.digitalocean.com/products/k8s/how-to/connect-to-cluster/)
6. cheers.

The state backend has no lock. Two people running `tofu apply` at once will step
on each other, so prefer letting CI do it.
