# Howdy! 

This is the github repo for the [masto.nyc](https://masto.nyc/about) v2.0 infrastructure. This is essentially what the [old kubernetes-only code](https://github.com/Five-Borough-Fedi-Project/masto.nyc) looks like now that it's migrated to Digital Ocean. It's pretty quiet here, but feel free to open an issue or reach out to us on mastodon. We'll try and keep todo items in the issues list.

## Why Digital Ocean?

Since we came from a bare metal Kubernetes setup, we wanted to maintain as much of that infrastructure as possible- and we also wanted to follow our server principals of supporting NYC-based companies whenever possible. Luckily, Digital Ocean not only offered a k8s package but is also based out of NYC!

## How deployment works

Both clusters run [Flux](https://fluxcd.io/), so **merging to `main` deploys**.
Change a manifest under `k8s/`, open a pull request, merge, and each cluster
reconciles within ten minutes. `kubectl apply` is no longer the way things ship,
and manual changes get reverted. See [docs/flux-bootstrap.md](docs/flux-bootstrap.md).

Infrastructure is OpenTofu, planned on every pull request and applied on merge
behind an approval gate. See [docs/terraform-reconciliation.md](docs/terraform-reconciliation.md).

## Documentation

| | |
|---|---|
| [devops-roadmap.md](docs/devops-roadmap.md) | where the whole migration stands, and what is still open |
| [multi-cluster.md](docs/multi-cluster.md) | how do-production and `large` divide the work |
| [cluster-capacity.md](docs/cluster-capacity.md) | why 12 GiB of nodes is 8988 MiB of usable memory |
| [flux-bootstrap.md](docs/flux-bootstrap.md) | how GitOps is wired, and how to suspend it |
| [upgrade-runbook.md](docs/upgrade-runbook.md) | **read before any Mastodon version bump** |
| [secrets-sops.md](docs/secrets-sops.md) | how encrypted secrets work, two age keys |
| [secrets-rollout.md](docs/secrets-rollout.md) | record of the ConfigMap to Secret migration |
| [terraform-reconciliation.md](docs/terraform-reconciliation.md) | reading a plan safely on drifted state |
| [logging-teardown.md](docs/logging-teardown.md) | why there is no log shipping right now |
| [renovate.md](docs/renovate.md) | what gets dependency updates, and what deliberately does not |

## Setup instructions:

**OpenTofu 1.8 or newer, not Terraform.** The backend block in `provider.tf` references variables, which OpenTofu supports as of 1.8 and HashiCorp Terraform does not support at all. `terraform init` will reject this repo.

1. In the DOcean console, generate a new [Personal access token](https://cloud.digitalocean.com/account/api/tokens). Put them aside for later.
2. From that page, click on the "Spaces Keys" tab and create a new set of s3 creds for the state. Put them aside for later.
3. Create a `terraform.tfvars` file. Populate it with the correct `do_token` (from step 1), `state_bucket`, and `state_key` variables.
4. Run the following command to initialize the state with your s3 creds (from step 2): `tofu init -backend-config="secret_key=YOURSECRETKEY" -backend-config="access_key=YOURACCESSKEY"`
5. [Follow these steps to set up kubectl.](https://docs.digitalocean.com/products/k8s/how-to/connect-to-cluster/)
6. cheers.

The state backend has no lock, so two people running `tofu apply` at once will
step on each other. CI serialises its own applies with a concurrency group, but
that does not protect against someone applying from a laptop at the same time.
Prefer letting CI do it.
