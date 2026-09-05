# Howdy! 

This is the github repo for the [masto.nyc](https://masto.nyc/about) v2.0 infrastructure. This is essentially what the [old kubernetes-only code](https://github.com/Five-Borough-Fedi-Project/masto.nyc) looks like now that it's migrated to Digital Ocean. It's pretty quiet here, but feel free to open an issue or reach out to us on mastodon. We'll try and keep todo items in the issues list.

## Why Digital Ocean?

Since we came from a bare metal Kubernetes setup, we wanted to maintain as much of that infrastructure as possible- and we also wanted to follow our server principals of supporting NYC-based companies whenever possible. Luckily, Digital Ocean not only offered a k8s package but is also based out of NYC!

## How deployment works

Both clusters run [Flux](https://fluxcd.io/), so **merging to `main` deploys**.
Change a manifest under `k8s/`, open a pull request, merge, and each cluster
reconciles within ten minutes. `kubectl apply` is no longer how things ship, and
manual changes get reverted.

Infrastructure is OpenTofu, planned on every pull request and applied on merge
behind an approval gate.

## Flux, day to day

Two kubectl contexts: `do` for DigitalOcean, `lab` for the `large` cluster.
Always pass `--context`. Both clusters have a `mastodon` namespace holding
objects with the same names, and there is nothing in a prompt to tell you which
one you are pointed at.

Check that a cluster is reconciling. All three should report `True` on the same
revision:

```sh
flux --context=do get kustomizations
```

Pull and apply immediately, without waiting for the ten minute interval:

```sh
flux --context=do reconcile kustomization apps --with-source
```

Stop Flux reverting you while you debug something by hand, and start it again
afterwards:

```sh
flux --context=do suspend kustomization apps
flux --context=do resume kustomization apps
```

**Suspend both clusters before a Mastodon upgrade.** The upgrade scales
deployments to zero, and a running Flux will scale them back up while the
database is half migrated. See `docs/upgrade-runbook.md`.

Find out why a reconcile failed. `events` is usually enough, and `logs` reads
the controller output without the raw JSON:

```sh
flux --context=do events --for Kustomization/apps
flux --context=do logs --kind=Kustomization --name=apps --tail=20
```

Compare a cluster against the repository without changing anything. Silence
means they agree:

```sh
kubectl --context=do diff -k k8s/clusters/do-production
kubectl --context=lab diff -k k8s/clusters/large
```

## About docs/

**Everything under `docs/` is AI slop.** It was written by an LLM and no human
has edited the prose. The commands and measurements in it were checked against
the live clusters at the time of writing, so the facts were true when they were
written. The writing is machine-generated throughout, it is far longer than it
needs to be, and it will drift as the infrastructure changes. Read it for the
commands and treat the rest with suspicion.

## Setup instructions:

**Use OpenTofu 1.8 or newer.** The backend block in `provider.tf` references variables, which OpenTofu supports as of 1.8 and HashiCorp Terraform does not support at all. `terraform init` will reject this repo.

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
