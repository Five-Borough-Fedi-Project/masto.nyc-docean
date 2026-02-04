# Copilot / AI agent instructions for masto.nyc-docean

Purpose: give an AI coding agent immediate, actionable context for working in this repo.

- **Big picture**: This repo manages the Mastodon instance infra on DigitalOcean using Terraform + Kubernetes. Terraform provisioning (DigitalOcean + k8s) lives at the repo root; app/service manifests live under `kubernetes/`; container builds live under `docker/`.

  - Infrastructure: [provider.tf](/provider.tf#L1-L120), [terraform.tfvars](/terraform.tfvars#L1-L10)
  - Kubernetes manifests: [kubernetes/mastodon/deployment-web.yaml](/kubernetes/mastodon/deployment-web.yaml#L1-L200) and other manifests under `kubernetes/` and `kubernetes/cronjobs/`
  - Containers and runtime: [docker/page-replica/Dockerfile](/docker/page-replica/Dockerfile#L1-L200), [docker/page-replica/package.json](/docker/page-replica/package.json#L1-L60), `docker/welcome-bot/`
  - DigitalOcean Kubernetes (cluster managed by Terraform provider). See [provider.tf](/provider.tf#L1-L120).
  - Apply infra: `terraform apply` from repo root (ensure `terraform.tfvars` is populated with `do_token`, `state_bucket`, `state_key`). See [README.md](/README.md#L1-L40).
- **Architecture notes (discoverable patterns)**:
  - Terraform uses DigitalOcean provider and stores state in DO Spaces S3-compatible backend (see `provider.tf`).
  - Kubernetes resources are managed as plain YAML under `kubernetes/` (no Helm here). Deployments reference prebuilt images (e.g., ghcr.io/mastodon/mastodon:v4.5.6 in the web deployment).
  - Several components run as separate pods (web, streaming, sidekiq variants, nginx is currently a standalone pod — commented suggestion to consider a sidecar in `deployment-web.yaml`).
  - Cronjobs exist for backups and maintenance under `kubernetes/cronjobs/`.

- **Developer workflows & commands (explicit)**:
  - Terraform init with DO Spaces backend: README suggests using `tofu init -backend-config="secret_key=..." -backend-config="access_key=..."`. If you use plain Terraform, replace `tofu` with `terraform` and pass backend config similarly.
  - Apply infra: `terraform apply` from repo root (ensure `terraform.tfvars` is populated with `do_token`, `state_bucket`, `state_key`). See [README.md](README.md#L1-L40).
  - Kubernetes: `kubectl apply -f kubernetes/` to apply all manifests, or apply individual files under `kubernetes/mastodon/`.
  - Build/run local helper image (page-replica): in `docker/page-replica/` run `docker build -t pagereplica .` then `docker run -p 8080:8080 pagereplica` (service `start` script is `npm start`).

- **Conventions & patterns to follow when editing**:
  - Images are often pinned to explicit versions (e.g., `ghcr.io/mastodon/mastodon:v4.5.6`). Preserve intentional pinning unless bumping versions — note where the version is declared in `deployment-web.yaml`.
  - Pod security: many pods set `fsGroup`, `runAsUser/runAsGroup` (991) in Kubernetes manifests. Keep permissions consistent for shared volumes.
  - Config/secrets separation: env is supplied via `configMapRef` names like `mastodon-env-secret` and `mastodon-env-tf` in `deployment-web.yaml`. Do not hardcode secrets into manifests or new code.

- **Integration points / external services**:
  - DigitalOcean Kubernetes (cluster managed by Terraform provider). See [provider.tf](provider.tf#L1-L120).
  - DigitalOcean Spaces used as S3-compatible terraform state backend.
  - External image registry: GitHub Container Registry (ghcr.io) for official Mastodon images.

- **What to avoid / watch for**:
  - `terraform.tfvars` may contain real tokens in the workspace — do not commit secrets. If you find secrets, prompt the maintainer for redaction guidance.
  - There is no global state lock mentioned in README — coordinate when running `terraform apply`.

- **Example edits agents may perform (how to be helpful)**:
  - Bump a Mastodon image version: update the version in `kubernetes/mastodon/deployment-web.yaml` and link the change to any configmaps if env vars changed.
  - Add readiness/liveness probes: `deployment-web.yaml` already has commented probe stubs — enable and tune them rather than inventing new endpoints.
  - Add a sidecar nginx: there is a commented nginx sidecar snippet in `deployment-web.yaml` — prefer small, contained changes and mention potential shared cache requirements.

- **When you need human guidance**:
  - Any change touching secrets, state backend, or Terraform remote state policy.
  - Changing cluster size or any firewall/db changes — ask the maintainers for run-window and rollback plan.

If anything here is unclear or you'd like more detail on CI, developer shells, or secrets handling, tell me which area to expand.
