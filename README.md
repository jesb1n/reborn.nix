# Oracle Cloud Infrastructure - Terraform/OpenTofu

> **This entire infrastructure is free.** Everything runs on Oracle Cloud's [Always Free Tier](https://www.oracle.com/cloud/free/) — no time limits, no surprise charges. You get 3 servers, 6 OCPUs, 26 GB RAM, 150 GB storage, and full networking for **$0/month, forever**.

This project provisions a production-ready cloud infrastructure on OCI using Terraform/OpenTofu:

- **VCN** with public subnet, internet gateway, route table, and security list
- **ARM instance** (VM.Standard.A1.Flex) — 4 OCPUs, 24 GB RAM, 50 GB boot volume
- **2x AMD micro instances** (VM.Standard.E2.1.Micro) — 1 OCPU, 1 GB RAM, 50 GB boot volume each
- **Tailscale** auto-join on micro instances via cloud-init
- **Local backend** for Terraform/OpenTofu state (`IaC/terraform.tfstate`)

## Documentation

| Doc | Description |
|-----|-------------|
| **[docs/PREREQUISITES.md](docs/PREREQUISITES.md)** | Everything you need before starting — OCI account setup, API keys, tools, S3 backend credentials, and the full Always Free Tier breakdown |
| **[docs/SETUP.md](docs/SETUP.md)** | Step-by-step guide from clone to running infrastructure, plus troubleshooting |
| **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** | Detailed explanation of every component, how they connect, and the network/data flow |
| **[docs/CICD.md](docs/CICD.md)** | GitHub Actions workflows — how to deploy/destroy from CI, required secrets |
| **[anywhere/README.md](anywhere/README.md)** | Commands for managing the OCI NixOS host with the flake and `nixos-rebuild` |

## Quick Start

```bash
cp IaC/terraform.tfvars.example IaC/terraform.tfvars
# Edit IaC/terraform.tfvars with your values (see docs/PREREQUISITES.md)

export TF_VAR_OCA_PRIVATE_KEY="$(base64 < ~/.oci/oci-api-key.pem)"
export TF_VAR_TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"  # optional
export AWS_ACCESS_KEY_ID="your-s3-access-key"
export AWS_SECRET_ACCESS_KEY="your-s3-secret-key"

tofu -chdir=IaC init
tofu -chdir=IaC plan
tofu -chdir=IaC apply
```

## Architecture

```
VCN (10.0.0.0/16)
├── Public Subnet (10.0.0.0/24)
│   ├── ARM Instance (A1.Flex) — 4 OCPU, 24 GB RAM, public IP
│   ├── Micro Instance 1 (E2.1.Micro) — 1 OCPU, 1 GB RAM, public IP, Tailscale
│   └── Micro Instance 2 (E2.1.Micro) — 1 OCPU, 1 GB RAM, public IP, Tailscale
├── Internet Gateway
├── Route Table (0.0.0.0/0 → IGW)
└── Security List
    ├── Ingress: SSH (port 22) from your IP only
    ├── Ingress: All traffic within VCN
    └── Egress: All outbound traffic
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a full breakdown.

## Oracle Cloud Always Free Tier

| Resource | Free Allocation | This Project Uses |
|----------|----------------|-------------------|
| ARM Instances (A1.Flex) | 4 OCPUs + 24 GB RAM | 1 instance (4 OCPU, 24 GB) |
| Micro Instances (E2.1.Micro) | 2 instances | 2 instances (1 OCPU, 1 GB each) |
| Boot Volumes | 200 GB total | 150 GB (50 GB × 3) |
| VCNs | 2 | 1 |
| Outbound Data | 10 TB/month | As needed |
| Object Storage | 20 GB | Terraform state only |

Everything fits comfortably within the free limits, with headroom to spare.

## Files

| File | Description |
|---|---|---|
| `IaC/availability-domains.tf` | Fetches availability domains for the tenancy |
| `IaC/backend.tf` | Local state backend config |
| `IaC/instance.tf` | ARM + micro instance definitions and image lookups |
| `IaC/locals.tf` | Shared locals: tags, image IDs, instance config |
| `IaC/output.tf` | Output public IPs of all instances |
| `IaC/provider.tf` | OCI provider configuration |
| `IaC/variables.tf` | All input variable declarations with validation |
| `IaC/vcn.tf` | VCN, subnet, internet gateway, route table, security list |
| `IaC/versions.tf` | Required provider versions |
| `IaC/terraform.tfvars.example` | Example variable values (copy to `IaC/terraform.tfvars`) |
| `.github/workflows/apply.yml` | GitHub Actions workflow — plan & apply infrastructure |
| `.github/workflows/destroy.yml` | GitHub Actions workflow — destroy all resources |
| `.gitignore` | Prevents committing secrets, state files, and .terraform/ |
| `docs/` | Detailed documentation (prerequisites, setup, architecture, CI/CD) |

## Notes

- All instances use Ubuntu 24.04 images (latest available, looked up dynamically).
- The ARM instance targets availability domain index 1 (falls back to 0 if only one AD exists).
- Micro instances auto-install Tailscale on first boot and clean up the auth key from cloud-init metadata.
- SSH access is restricted to a single whitelisted IP via the security list.
- Terraform state is stored locally in `IaC/terraform.tfstate`.
