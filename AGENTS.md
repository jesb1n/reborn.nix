# Agent Rules

- **Do not commit, push, or delete until the user explicitly confirms.**
- **Only use best practices** — follow idiomatic conventions for each tool (OpenTofu/Terraform, Nix, k8s, Helm), respect immutability, avoid unnecessary state changes, and prefer upstream/official charts over raw manifests.

# Repository Guidelines

## Project Structure & Module Organization

This repository provisions Oracle Cloud Always Free infrastructure with OpenTofu/Terraform under `IaC/`. Core files are split by concern: `IaC/provider.tf`, `IaC/versions.tf`, and `IaC/backend.tf` configure tooling; `IaC/variables.tf` and `IaC/locals.tf` define inputs and shared values; `IaC/vcn.tf`, `IaC/availability-domains.tf`, and `IaC/instance.tf` create OCI networking and instances; `IaC/output.tf` exposes instance IPs. Docs live in `docs/`. Ignore `retire.nix/`; it is a separate cloned repo.

The `anywhere/` directory is a standalone Nix flake that manages NixOS configurations for the provisioned hosts:

```
anywhere/
├── flake.nix              # Inputs, deploy-rs nodes, NixOS configs
├── hosts/<hostname>/      # Per-host: configuration.nix, disko-config.nix, sops.nix
├── secrets/<hostname>/    # SOPS-encrypted age files (decrypted at activation)
├── packages/              # Custom Nix derivations (kexec images)
├── MAINTENANCE.md         # Runbook for routine ops
└── GATEWAY-NLB-PLAN.md   # Planned NLB addition
```

### Hosts

| Host | Shape | Arch | Role |
|------|-------|------|------|
| `oci-nixos` | A1.Flex (4 OCPU, 24 GB) | aarch64 | k3s control-plane |
| `oracle-eu-micro1` | E2.1.Micro (1 OCPU, 1 GB) | x86_64 | k3s worker (tainted `tiny`) |
| `oracle-eu-micro2` | E2.1.Micro (1 OCPU, 1 GB) | x86_64 | k3s worker (tainted `tiny`) |
| `rpi` | Raspberry Pi 4 | aarch64 | standalone |

## Build, Test, and Development Commands

### Terraform (IaC/)

- `cp IaC/terraform.tfvars.example IaC/terraform.tfvars`: create a local variable file; never commit it.
- `tofu -chdir=IaC init`: initialize providers and backend.
- `tofu -chdir=IaC fmt -recursive`: format all `.tf` files before committing.
- `tofu -chdir=IaC validate`: validate configuration syntax and provider schema.
- `tofu -chdir=IaC plan`: preview OCI changes; review creates, replacements, and destroys carefully.
- `tofu -chdir=IaC apply`: apply reviewed infrastructure changes.

### NixOS (`anywhere/` directory)

- `cd anywhere && direnv allow`: enter the Nix dev shell (provides deploy-rs, sops, age, nixos-anywhere, disko).
- `nix flake check`: validate flake outputs when Nix files change.
- `nix flake show`: inspect available NixOS configurations.
- `nix develop -c deploy .#<hostname>`: deploy a single host via deploy-rs.
- `nix develop -c deploy --targets .#oracle-eu-micro1 .#oracle-eu-micro2`: deploy multiple hosts.
- `nix develop -c deploy .`: deploy all hosts.
- `nix build -L .#nixosConfigurations.<hostname>.config.system.build.toplevel`: build without activating.

## Coding Style & Naming Conventions

Use standard Terraform formatting: two-space indentation, aligned attributes from `tofu -chdir=IaC fmt`, and descriptive `description` fields for variables and outputs. Keep resource names lowercase with underscores, such as `oci_core_vcn.vcn`, and OCI labels lowercase with hyphens. For Nix files, follow existing two-space indentation and keep host-specific logic under `anywhere/hosts/<host>/`.

## Testing Guidelines

There is no unit test suite. Treat formatting, validation, and planning as the main checks:

- **Terraform**: `tofu -chdir=IaC fmt -recursive && tofu -chdir=IaC validate && tofu -chdir=IaC plan`
- **Nix**: `nix flake check` and optionally `nix eval --raw .#nixosConfigurations.<host>.config.nixpkgs.hostPlatform.system`

## Commit & Pull Request Guidelines

Use short imperative subjects, for example `Add deploy-rs support...` or `Update oracle-eu-micro2 IP address...`. Keep commits focused and describe infrastructure impact. Pull requests should include a summary, affected hosts/resources, validation commands run, and relevant `tofu plan` highlights.

## Security & Configuration Tips

Do not commit `IaC/terraform.tfvars`, `IaC/*.tfstate`, `IaC/*.tfplan`, private keys, or decrypted secrets. Prefer environment variables for sensitive Terraform inputs: `TF_VAR_OCA_PRIVATE_KEY`, `TF_VAR_TAILSCALE_AUTH_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. SOPS-encrypted secrets live under `anywhere/secrets/`; each host decrypts with an age key at `/var/lib/sops-nix/key.txt`.

## Key Pitfalls

- **Never use `nixos-anywhere` for routine updates** — it destroys and reinstalls. Use `deploy-rs` for config changes.
- **ARM host (`oci-nixos`) builds remotely** (`remoteBuild = true`) since the operator machine is x86.
- **Micro instances have only 1 GB RAM** — zramSwap at 50%, max-pods=10; don't schedule heavy workloads.
- **`availability_domain` changes are ignored** in instance lifecycle to prevent recreation.
- **k3s cluster traffic flows over `tailscale0`** (`--flannel-iface=tailscale0`); Tailscale IP changes require updating `services.k3s.nodeIP`.

## Related Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — full infrastructure diagram and component breakdown
- [docs/SETUP.md](docs/SETUP.md) — step-by-step provisioning guide
- [docs/PREREQUISITES.md](docs/PREREQUISITES.md) — required tools, accounts, and credentials
- [docs/CICD.md](docs/CICD.md) — GitHub Actions deployment workflows
- [anywhere/MAINTENANCE.md](anywhere/MAINTENANCE.md) — NixOS host operations runbook
