# CI/CD

The repository currently has two manual GitHub Actions workflows for OpenTofu. NixOS deployments and Flux reconciliation are not performed by GitHub Actions.

## Current Workflows

| Workflow | Trigger | Behavior |
| --- | --- | --- |
| `.github/workflows/apply.yml` | `workflow_dispatch` | checkout, install OpenTofu 1.9.1, configure S3 credentials, init, validate, plan, apply |
| `.github/workflows/destroy.yml` | `workflow_dispatch` | checkout, install OpenTofu 1.9.1, configure S3 credentials, init, destroy |

The apply workflow attempts `tofu state push IaC/errored.tfstate` if an apply failure leaves that recovery file behind.

These workflows are state-changing and require deliberate manual invocation. The destroy workflow has no environment approval gate in the checked-in YAML.

## Required GitHub Configuration

The workflows directly reference only these repository secrets:

| Secret | Purpose |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Garage S3 access key for the OpenTofu backend |
| `AWS_SECRET_ACCESS_KEY` | Garage S3 secret key for the OpenTofu backend |

OpenTofu still requires all OCI variables and usable provider authentication at runtime. The current workflows do not decrypt `IaC/<environment>.tfvars`, do not select an OCI SecurityToken profile, and do not accept an environment input. They also use the static backend key from `IaC/backend.tf`.

Consequently, the local multi-environment Makefile workflow is the authoritative and supported deployment path:

```bash
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijns init
make -C IaC ENV=beijns plan
make -C IaC ENV=beijns deploy
```

Do not assume the Actions workflows can deploy either environment without additional runner authentication and variable wiring.

## Backend Reachability

The backend endpoint is Garage at `http://100.69.231.117:31900`, a Tailscale address. A standard `ubuntu-latest` runner cannot reach it unless the workflow first joins the authorized Tailnet. The checked-in workflows do not currently install or connect Tailscale.

This means CI init is expected to fail unless external runner networking supplies that route. Do not change the backend to OCI Object Storage or local state merely to make CI pass; design and review an explicit migration instead.

## Data Flow

```text
Manual workflow dispatch
  → GitHub-hosted ubuntu-latest runner
  → checkout
  → OpenTofu 1.9.1
  → write temporary ~/.aws/credentials
  → connect to Garage backend (requires private route)
  → init / validate / plan / apply or destroy
```

GitHub masks configured secrets, but OpenTofu plans and provider errors can still expose infrastructure metadata. Review Actions retention and access controls accordingly.

## Safe Improvement Path

Before treating CI as production-capable:

1. Add an explicit environment selector and map it to a distinct state key.
2. Establish short-lived OCI authentication suitable for CI; do not upload long-lived private keys casually.
3. Join Tailscale with an ephemeral, tagged credential or use an authorized self-hosted runner.
4. Provide SOPS decryption through a narrowly scoped CI age identity if encrypted tfvars remain the input source.
5. Add protected GitHub Environments and required reviewers, especially for destroy.
6. Run `tofu fmt -check` and validate before planning.
7. Preserve the failed-state recovery behavior and test it without exposing state.

Until those changes exist, use Actions as repository history, not as the primary operator runbook.
