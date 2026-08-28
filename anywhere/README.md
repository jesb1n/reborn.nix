# Fleet and cluster configuration

`anywhere/` is the standalone Nix flake that configures the repository's ten
NixOS hosts, the `pro-darwin` operator machine, and the Kubernetes resources
running on the `s145` k3s cluster.

- Routine NixOS updates use deploy-rs.
- `pro-darwin` uses `darwin-rebuild`, not deploy-rs.
- New installations may use `nixos-anywhere`; it is destructive and is never a
  routine update command.
- Cluster applications registered in `clusters/s145/` are reconciled by Flux.

See [MAINTENANCE.md](./MAINTENANCE.md) for day-to-day commands and the
[repository architecture](../docs/ARCHITECTURE.md) for the complete system
model.

## Directory map

| Path | Purpose |
| --- | --- |
| `flake.nix` | Inputs, host outputs, dev shells, and deploy-rs nodes |
| `profiles/` | Shared NixOS behavior for base, server, Tailscale, and k3s roles |
| `hosts/<name>/` | Host identity, disks, hardware overrides, and secret declarations |
| `secrets/` | SOPS-encrypted host and shared credentials |
| `operator/` | Flux Operator `FluxInstance` configuration |
| `clusters/s145/` | Flux `Kustomization` registrations |
| `k8s/` | Kubernetes resources consumed by those registrations |
| `docs/` | Installation, migration, and technical runbooks |

## Host outputs

| Host | Platform | Role | Build placement |
| --- | --- | --- | --- |
| `s145` | `x86_64-linux` | k3s server, durable storage, Garage | target host |
| `hp348` | `x86_64-linux` | k3s agent, distributed Nix builder | target host |
| `nuc7i3` | `x86_64-linux` | k3s agent, general-purpose server | target host |
| `oracle-eu-arm1` | `aarch64-linux` | k3s agent, Hermes Agent | target host |
| `oracle-in-arm1` | `aarch64-linux` | k3s agent, monitoring | target host |
| four Oracle micro nodes | `x86_64-linux` | resource-limited k3s agents | `hp348` for Mac-initiated builds |
| `rpi` | `aarch64-linux` | k3s agent | target host |
| `pro-darwin` | `aarch64-darwin` | operator workstation | local Mac |

The four micro deploy entries use `remoteBuild = false`. From `pro-darwin`, Nix
sends their `x86_64-linux` builds to the configured `hp348` builder. All other
deploy-rs nodes use `remoteBuild = true`.

## Management shell

From this directory:

```bash
direnv allow
nix develop
```

`direnv` only sets `KUBECONFIG` and `SOPS_AGE_KEY_FILE`; it does not enter the
dev shell. You can also run individual tools with `nix develop -c <command>`.

## Validate a change

Run the narrowest useful evaluation first, then the full flake check when Nix
files changed:

```bash
nix eval --raw .#nixosConfigurations.s145.config.networking.hostName
nix build -L .#nixosConfigurations.s145.config.system.build.toplevel
nix flake check
```

Git flakes do not include untracked files. Stage newly created Nix files before
evaluation.

For Kubernetes resources, validate one Flux application locally when it has a
`kustomization.yaml`:

```bash
kubectl kustomize k8s/<app>
```

## Deploy NixOS

Deployment changes live state. Review the diff and validation output first.
Deploy workers before the control plane:

```bash
nix develop -c deploy .#oracle-eu-micro2
nix develop -c deploy --targets \
  .#oracle-eu-micro1 .#oracle-eu-micro2 \
  .#oracle-in-micro1 .#oracle-in-micro2
nix develop -c deploy .#s145
```

Deploying `.#s145` should normally be last. Use `nix develop -c deploy .` only
when a fleet-wide activation is intentional.

`pro-darwin` is a separate nix-darwin output:

```bash
sudo darwin-rebuild build --flake .#pro-darwin
sudo darwin-rebuild switch --flake .#pro-darwin
```

## Secrets

Hosts read their age private key from `/var/lib/sops-nix/key.txt` and decrypt
only the files for which their public `age1...` recipient is listed in
`.sops.yaml`. Shared values are stored in:

- `secrets/k3s/secrets.yaml`
- `secrets/tailscale/secrets.yaml`

Use an authorized operator identity when editing or re-keying:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops secrets/k3s/secrets.yaml
sops updatekeys secrets/k3s/secrets.yaml
```

Never commit plaintext secrets, age private keys, or rendered files from
`/run/secrets`.

## Kubernetes ownership

Flux syncs the repository's `main` branch and reconciles the registrations in
`clusters/s145/`. Application resources belong under `k8s/<app>/`; adding a
directory alone does not deploy it. See [clusters/s145/README.md](./clusters/s145/README.md)
for ownership and reconciliation details.

Traefik is the only ingress controller. It owns DNS-01 ACME and the global HTTP
to HTTPS redirect. Application `Middleware` objects are namespace-scoped, and
stateful workloads normally pin to `s145`; monitoring is the documented
exception and pins to `oracle-in-arm1`.

## Installation boundary

`nixos-anywhere` with Disko can erase the target disk. Use it only for an
explicit installation or reinstallation, after checking the applicable
runbook. The 1 GB Oracle micro procedure must run from a roomier x86_64 host and
is documented in [ORACLE-IN-MICRO-NIXOS.md](./docs/ORACLE-IN-MICRO-NIXOS.md).
