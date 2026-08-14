# Architecture

This repository manages a hybrid personal infrastructure platform. OCI supplies disposable compute in two regions, on-premises machines supply the control plane and durable storage, and Tailscale joins every node into one private network.

## Layers

```text
┌─────────────────────────────────────────────────────────────┐
│ Operator: pro-darwin                                        │
│ OpenTofu · Nix · deploy-rs · SOPS · kubectl · Flux          │
└───────────────┬─────────────────────────────────────────────┘
                │ Git, OCI API, SSH, Tailscale, Kubernetes API
┌───────────────▼─────────────────────────────────────────────┐
│ Provisioning: IaC/                                          │
│ OCI VCNs, subnets, gateways, security lists, public IPs, VMs│
└───────────────┬─────────────────────────────────────────────┘
                │ Ubuntu bootstrap followed by NixOS install
┌───────────────▼─────────────────────────────────────────────┐
│ Machine configuration: anywhere/                            │
│ NixOS profiles · host modules · SOPS · deploy-rs            │
└───────────────┬─────────────────────────────────────────────┘
                │ k3s over tailscale0
┌───────────────▼─────────────────────────────────────────────┐
│ Cluster: s145 control plane                                 │
│ Flux Operator · Traefik · Cloudflare Tunnel · applications  │
└─────────────────────────────────────────────────────────────┘
```

## Host Inventory

| Host | Platform | Architecture | Cluster role | Operational role |
| --- | --- | --- | --- | --- |
| `s145` | Home server | x86_64 | k3s server | Control plane, primary local-path storage, Traefik, Garage endpoint |
| `hp348` | HP laptop | x86_64 | agent | On-prem worker and distributed x86_64 builder for Mac-initiated micro deployments |
| `oracle-eu-arm1` | OCI A1.Flex | aarch64 | agent | General worker and Hermes Agent |
| `oracle-eu-micro1` | OCI E2.1.Micro | x86_64 | tiny agent | Low-memory Europe worker |
| `oracle-eu-micro2` | OCI E2.1.Micro | x86_64 | tiny agent | Low-memory Europe worker |
| `oracle-in-arm1` | OCI A1.Flex | aarch64 | agent | General worker and monitoring host |
| `oracle-in-micro1` | OCI E2.1.Micro | x86_64 | tiny agent | Low-memory India worker |
| `oracle-in-micro2` | OCI E2.1.Micro | x86_64 | tiny agent | Low-memory India worker |
| `rpi` | Raspberry Pi 4 | aarch64 | agent | On-prem ARM worker |
| `pro-darwin` | Apple Silicon Mac | aarch64-darwin | none | Operator workstation managed by nix-darwin/home-manager |

`anywhere/flake.nix` is authoritative for systems, deploy targets, and build placement. The four micro deploy targets use `remoteBuild = false`; their x86_64 closures are delegated from `pro-darwin` through the configured `hp348` builder. Other NixOS targets build remotely.

## OCI Provisioning

`IaC/` supports two encrypted environments:

| Environment | Region intent | State key |
| --- | --- | --- |
| `beijns` | India | `beijns.tfstate` |
| `beijnseu` | Europe | `beijnseu.tfstate` |

Each environment supplies its own project, region, compartment, CIDRs, SSH allowlist, and instance inputs through a SOPS-encrypted tfvars file. OpenTofu creates the OCI VCN, public subnet, internet gateway, route and security resources, ARM instance, micro instances, and outputs.

The OCI provider reads an OCI CLI SecurityToken profile selected by `config_file_profile`. The Makefile checks or refreshes that session before init, plan, or apply.

## State and Secrets

### OpenTofu state

`IaC/backend.tf` uses the S3 backend with bucket `tofu-backend` and the Garage endpoint at `http://100.69.231.117:31900`. The Makefile selects one key per environment during `init`. Reaching the endpoint requires Tailscale and valid S3 credentials from the encrypted `IaC/secrets/<environment>.env` file.

This creates an important dependency: Garage and `s145` must be reachable before normal state operations. Keep independent state backups before Garage layout changes.

### SOPS

- IaC tfvars and backend environment files are encrypted and decrypted in memory.
- NixOS secrets are declared per host and materialized under `/run/secrets` during activation.
- Shared k3s and Tailscale secrets include recipients for all consuming hosts.
- Flux decrypts selected Kubernetes secrets with `Secret/flux-system/sops-age`.
- Public `age1...` recipients may be committed; age private keys must not be committed or copied into general archives.

## NixOS Composition

Shared behavior lives in `anywhere/profiles/`:

| Profile | Responsibility |
| --- | --- |
| `base.nix` | User, SSH keys, Nix settings, packages, and garbage collection |
| `server.nix` | Boot defaults, SSH hardening, firewall, and server baseline |
| `tailscale.nix` | Tailnet membership and firewall integration |
| `k3s-server.nix` | `s145` server flags and control-plane configuration |
| `k3s-agent.nix` | Agent connection to `https://100.69.231.117:6443` over Tailscale |
| `k3s-agent-tiny.nix` | 1 GB tuning, zram, and `max-pods=10` |
| `k3s-cni.nix` | Shared k3s network behavior |
| `smartd.nix` | SMART monitoring for capable on-prem disks |
| `hermes-agent.nix` | Hermes gateway on `oracle-eu-arm1` |

Host modules contain identity, node addresses, disks, secret declarations, and genuine hardware overrides. `rpi` uses `nixos-raspberrypi`; `pro-darwin` is a separate `darwinConfigurations` output and is not a deploy-rs node.

## Cluster Design

`s145` runs the single k3s server. Agents join through its Tailscale IP, and Flannel uses `tailscale0`. A single control plane avoids depending on disposable OCI nodes for quorum, but makes the k3s SQLite database and `s145` availability critical.

Tiny nodes have 1 GB RAM, 50% zram, and a `tiny=true:NoSchedule` taint applied after registration. Only workloads with an explicit toleration should run there.

### GitOps

The Flux Operator instance in `anywhere/operator/` syncs the repository and reconciles Kustomizations in `anywhere/clusters/s145/`. Registered workloads are:

- `_infra`
- `cloudflared`
- `garage`
- `immich`
- `immich-public-proxy`
- `litellm`
- `monitoring`
- `vaultwarden`

The cluster Kustomizations encode dependencies and SOPS decryption. App resources remain in `anywhere/k8s/<app>/`.

### Ingress

Traefik is the only ingress controller. Its NixOS-managed HelmChartConfig:

- obtains certificates through Cloudflare DNS-01;
- redirects HTTP to HTTPS globally;
- persists ACME data on `s145`;
- exposes Prometheus metrics.

Application `Middleware` resources are namespace-scoped. Each public `IngressRoute` references a middleware in its own namespace. Cloudflare Tunnel is a separate ingress path used by applications such as Immich Public Proxy.

## Storage and Failure Domains

- Primary stateful application PVCs use k3s `local-path` storage pinned to `s145` and its 1 TB disk.
- Monitoring state is intentionally pinned to `oracle-in-arm1`.
- Garage is a distributed S3 service spanning declared node classes; its manual layout migration has its own runbook.
- OCI VMs are replaceable capacity. Loss of `s145` affects the API server, local-path application data, and the OpenTofu backend endpoint.
- Back up application data, Garage state, and `/var/lib/rancher/k3s/server/db/state.db` off-host.

## Sources of Truth

When documentation and code disagree, use:

1. `anywhere/flake.nix` for hosts, systems, deploy nodes, and build placement.
2. `IaC/backend.tf`, `IaC/provider.tf`, and `IaC/Makefile` for state, authentication, and environment flow.
3. `anywhere/profiles/` and `anywhere/hosts/` for machine behavior.
4. `anywhere/clusters/s145/` for Flux registration.
5. `anywhere/k8s/` for application resources and scheduling.
