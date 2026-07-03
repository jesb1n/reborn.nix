# CI/CD with GitHub Actions

This project includes two GitHub Actions workflows that let you provision and tear down your infrastructure directly from GitHub — no local tooling required after initial setup.

Both workflows are **manual trigger only** (`workflow_dispatch`), so nothing runs automatically on push or PR.

## Workflows

### `apply.yml` — Provision Infrastructure

**What it does:** Runs `tofu -chdir=IaC init` → `tofu -chdir=IaC validate` → `tofu -chdir=IaC plan` → `tofu -chdir=IaC apply`

**When to use:** Whenever you want to create or update your infrastructure.

**Trigger:** Go to **Actions** → **Terraform Apply** → **Run workflow**

If the apply fails mid-way, the workflow automatically attempts to push the partial state (`IaC/errored.tfstate`) to the remote backend so you don't lose track of what was created.

### `destroy.yml` — Tear Down Infrastructure

**What it does:** Runs `tofu -chdir=IaC init` → `tofu -chdir=IaC destroy`

**When to use:** When you want to delete all resources.

**Trigger:** Go to **Actions** → **Terraform Destroy** → **Run workflow**

## Required GitHub Secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** and add:

| Secret | Value | Description |
|--------|-------|-------------|
| `TF_VAR_tenancy_ocid` | `ocid1.tenancy.oc1..aaaa...` | Your OCI tenancy OCID |
| `TF_VAR_user_ocid` | `ocid1.user.oc1..aaaa...` | Your OCI user OCID |
| `TF_VAR_fingerprint` | `aa:bb:cc:...` | API key fingerprint |
| `TF_VAR_OCA_PRIVATE_KEY` | Base64-encoded private key | `base64 < ~/.oci/oci-api-key.pem` |
| `TF_VAR_region` | `us-ashburn-1` | Your OCI region |
| `TF_VAR_ssh_authorized_keys` | `ssh-ed25519 AAAA...` | Your SSH public key |
| `TF_VAR_user_ip_address` | `203.0.113.10/32` | Your IP for SSH whitelist |
| `TF_VAR_TAILSCALE_AUTH_KEY` | `tskey-auth-xxxxx` | Tailscale auth key (optional) |
| `AWS_ACCESS_KEY_ID` | S3 access key | OCI Object Storage S3 credential |
| `AWS_SECRET_ACCESS_KEY` | S3 secret key | OCI Object Storage S3 credential |

> **Note:** Secrets prefixed with `TF_VAR_` are automatically picked up by OpenTofu/Terraform as variable values. This means you don't need an `IaC/terraform.tfvars` file in CI — the secrets replace it entirely.

### Variables that can stay in `IaC/terraform.tfvars`

These aren't sensitive and can be committed to the repo:

```hcl
vcn_cidr_block      = "10.0.0.0/16"
public_subnet_cidr  = "10.0.0.0/24"
private_subnet_cidr = "10.0.1.0/24"
nat_subnet_cidr     = "10.0.2.0/24"
vcn_dns_label       = "myvcn"
project             = "myproject"
```

Or you can set these as `TF_VAR_*` secrets too — your choice.

## How It Works

```
You click "Run workflow" in GitHub
        │
        ▼
GitHub spins up an ubuntu-latest runner
        │
        ▼
OpenTofu 1.9.1 is installed
        │
        ▼
S3 backend credentials are written to ~/.aws/credentials
(so tofu can read/write state from OCI Object Storage)
        │
        ▼
tofu -chdir=IaC init (connects to backend)
        │
        ▼
tofu -chdir=IaC plan → tofu -chdir=IaC apply  (or tofu -chdir=IaC destroy)
        │
        ▼
Infrastructure is created/updated/destroyed
```

The `TF_VAR_*` secrets are automatically available as environment variables in the runner, and OpenTofu reads them as input variable values.
