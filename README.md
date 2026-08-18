# reborn.nix

Declarative infrastructure for a hybrid NixOS fleet spanning Oracle Cloud, a home lab, a Raspberry Pi, and one nix-darwin workstation. OpenTofu provisions OCI resources; Nix flakes configure machines; k3s runs applications; Flux reconciles cluster state from Git.

This repository is operator-specific. It is useful as a reference, but values such as OCI compartments, hostnames, encrypted secrets, Tailnet addresses, and DNS zones must be replaced before reuse.

## Repository Map

| Path | Purpose |
| --- | --- |
| [`IaC/`](IaC/) | OpenTofu configuration for OCI networks and compute in the `beijns` and `beijnseu` environments |
| [`anywhere/`](anywhere/) | NixOS and nix-darwin flake, deploy-rs targets, SOPS declarations, and Kubernetes resources |
| [`anywhere/clusters/s145/`](anywhere/clusters/s145/) | Flux Kustomizations for the production k3s cluster |
| [`anywhere/k8s/`](anywhere/k8s/) | Application and cluster-infrastructure manifests |
| [`docs/`](docs/) | Architecture, prerequisites, setup, and CI/CD guidance |

## Current Architecture

```text
OCI India + OCI Europe ─┐
Home servers + laptop ──┼── Tailscale mesh ── k3s API on s145
Raspberry Pi ───────────┘                         │
                                                   ├── Flux Operator
                                                   ├── Traefik ingress + Cloudflare DNS-01
                                                   ├── stateful data on s145 local storage
                                                   └── workloads across NixOS agents

pro-darwin ── OpenTofu / deploy-rs / kubectl / SOPS operator workstation
```

- `s145` is the single k3s control plane and primary durable-storage host.
- OCI A1 and E2.1.Micro instances are disposable worker capacity in India and Europe.
- `hp348` and `rpi` are on-premises workers; `pro-darwin` is managed separately with nix-darwin.
- Cluster networking and management traffic use Tailscale. Traefik and Cloudflare Tunnel provide application ingress.
- OpenTofu state is stored in the Garage S3-compatible service at `s145`, not in OCI Object Storage or a local state file.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full host and service topology.

## Safe Operator Workflow

### OCI infrastructure

The checked-in environment files are SOPS-encrypted and decrypted only in memory. OCI authentication uses expiring SecurityToken profiles.

```bash
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijns init
make -C IaC fmt
tofu -chdir=IaC validate
make -C IaC ENV=beijns plan
```

Use `ENV=beijnseu` for Europe. `deploy` changes OCI resources and must follow plan review.

### NixOS fleet

Run from `anywhere/`:

```bash
nix flake check
nix eval --raw .#nixosConfigurations.s145.config.networking.hostName
nix build -L .#nixosConfigurations.s145.config.system.build.toplevel
nix develop -c deploy .#s145
```

Routine changes use deploy-rs. `nixos-anywhere` is destructive installation tooling, not a deployment command.

### Kubernetes and Flux

```bash
export KUBECONFIG="$HOME/.kube/s145.yaml"
kubectl get nodes
flux get kustomizations -n flux-system
flux reconcile kustomization immich -n flux-system --with-source
```

Flux-managed changes take effect only after they are committed and pushed to the branch watched by `anywhere/operator/flux-instance.yaml`. Consult each app README before manual operations.

## Documentation

| Document | Scope |
| --- | --- |
| [`docs/PREREQUISITES.md`](docs/PREREQUISITES.md) | Required accounts, tools, credentials, and network access |
| [`docs/SETUP.md`](docs/SETUP.md) | Initial operator and environment setup |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Infrastructure, fleet, networking, storage, and GitOps design |
| [`docs/CICD.md`](docs/CICD.md) | Current GitHub Actions behavior and limitations |
| [`anywhere/README.md`](anywhere/README.md) | NixOS, nix-darwin, deploy-rs, and SOPS usage |
| [`anywhere/MAINTENANCE.md`](anywhere/MAINTENANCE.md) | Day-to-day fleet and cluster runbook |
| [`anywhere/k8s/README.md`](anywhere/k8s/README.md) | Kubernetes application ownership and validation |

## Safety Boundaries

- Never commit plaintext secrets, age private keys, OCI credentials, Terraform state, plans, or PEM files.
- Treat `tofu apply`, `tofu destroy`, deploy-rs activation, `darwin-rebuild switch`, `kubectl apply`, Flux reconciliation, and SOPS re-keying as state-changing operations.
- Review an OpenTofu plan before applying it. OCI micro cloud-init is one-shot and existing instances ignore `metadata["user_data"]` changes.
- Deploy workers before `s145` when updating shared Nix inputs.
- Keep stateful Kubernetes workloads on the intended storage node and retain namespace-local Traefik middleware references.
