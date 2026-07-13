# Agent Rules

- **Do not commit, push, or delete until the user explicitly confirms.**
- **Only use best practices** — follow idiomatic conventions for each tool (OpenTofu/Terraform, Nix, k8s, Helm), respect immutability, avoid unnecessary state changes, and prefer upstream/official charts over raw manifests.

# Repository Guidelines

## Project Structure

- `IaC/` — OpenTofu/Terraform; provisions OCI VCN, subnets, and instances.
- `anywhere/` — Standalone Nix flake; manages NixOS configs for all hosts via deploy-rs.
- `docs/` — Architecture, setup, prerequisites, CI/CD docs.
- `retire.nix/` — **Ignore.** Separate cloned repo, not part of this project.

### Hosts (current state)

| Host | Shape | Arch | Role | Tailscale IP |
|------|-------|------|------|-------------|
| `s145` | Home server | x86_64 | **k3s control-plane** | `100.69.231.117` |
| `oracle-eu-arm1` | A1.Flex | aarch64 | k3s agent | `100.84.230.4` |
| `oracle-eu-micro1` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | `100.96.237.114` |
| `oracle-eu-micro2` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | `100.67.95.26` |
| `oracle-in-arm1` | A1.Flex | aarch64 | k3s agent | `100.117.227.112` |
| `oracle-in-micro1` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | `129.154.240.246` |
| `oracle-in-micro2` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | — |
| `rpi` | Raspberry Pi 4 | aarch64 | k3s agent | `100.118.166.120` |

## IaC (OpenTofu/Terraform)

### Commands

```bash
# Format before every commit
tofu -chdir=IaC fmt -recursive && tofu -chdir=IaC validate

# Standard flow
tofu -chdir=IaC init
tofu -chdir=IaC plan
tofu -chdir=IaC apply

# State recovery after failed apply
tofu -chdir=IaC state push IaC/errored.tfstate

# Local multi-env workflow (SOPS-integrated, preferred locally)
make ENV=beijns check-auth   # Refresh OCI SecurityToken session first
make ENV=beijns init
make ENV=beijns plan
make ENV=beijns deploy
```

### Critical IaC quirks

- **OCI uses SecurityToken auth** (`auth = "SecurityToken"` in `provider.tf`), not inline API keys. The session expires — run `make check-auth` or `oci session authenticate --profile-name <env> --region <region>` before any tofu command. This is what `make check-auth` automates.
- **Backend is self-hosted Garage** (S3-compatible) running on `s145` at `http://100.69.231.117:31900` — NOT OCI Object Storage. Requires Tailscale to be connected. CI bypasses with `skip_credentials_validation = true`.
- **Multi-env secrets**: the `Makefile` uses `sops exec-file <env>.tfvars 'tofu ... -var-file={}'` — never writes plaintext `.tfvars` to disk. `SOPS_AGE_KEY_FILE` is pre-set in the Makefile.
- **`availability_domain` changes are ignored** in instance lifecycle (`ignore_changes`) to prevent recreation.
- **Micro cloud-init is one-shot**: `metadata["user_data"]` is in `ignore_changes` — cloud-init runs only on first boot (installs Tailscale, joins tailnet, then clears user-data). Re-provisioning requires `taint` + `apply`.
- **`TF_VAR_OCA_PRIVATE_KEY`** must be base64-encoded: `base64 < ~/.oci/key.pem` (macOS) or `base64 -w0 < ~/.oci/key.pem` (Linux).

## NixOS / anywhere/

### Commands (run from `anywhere/`)

```bash
# Enter dev shell first (provides deploy-rs, sops, age, nixos-anywhere, disko, ssh-to-age)
nix develop
# NOTE: direnv allow only sets KUBECONFIG and SOPS_AGE_KEY_FILE — it does NOT load dev shell tools
# (nix print-dev-env is commented out in .envrc)

# Validate on every Nix file change
nix flake check

# Build without activating (use before first deploy to a host)
nix build -L .#nixosConfigurations.<host>.config.system.build.toplevel

# Deploy via deploy-rs (routine updates)
nix develop -c deploy .#<host>
nix develop -c deploy --targets .#oracle-eu-micro1 .#oracle-eu-micro2
nix develop -c deploy .   # all nodes

# Evaluate without deploying
nix eval --raw .#nixosConfigurations.<host>.config.networking.hostName
nix eval .#deploy.nodes.<host>.remoteBuild
```

### Critical NixOS quirks

- **All NixOS systems use `nixpkgs-unstable`**. The `nixpkgs` input (26.05 stable) is only used for the devShell. Every `nixosSystem` call uses `nixpkgs-unstable.lib.nixosSystem`.
- **New Nix files must be `git add`-ed before eval or deploy.** Flakes only see tracked/staged files; untracked files cause evaluation errors.
- **ARM hosts build remotely** (`remoteBuild = true`): `oracle-eu-arm1` and `oracle-in-arm1` build on themselves because s145 is x86_64 and cannot cross-compile aarch64 by default.
- **`oracle-in-micro1` is unique**: `sshUser = "ubuntu"` (not `duck`) and `remoteBuild = false`. Deploy target is a hardcoded IP (`129.154.240.246`), not hostname.
- **`nixos-anywhere` is destructive** — reformats the disk via disko. Never use for routine updates; use deploy-rs instead.
- **`--elevate=sudo`** (not `--use-remote-sudo`) is the correct flag for `nixos-rebuild` remote activation.
- **`s145` overrides GRUB** with systemd-boot (`lib.mkForce`). All other OCI hosts use GRUB from `profiles/server.nix`.
- **Deploy order for input updates**: workers (`oracle-eu-micro2` → `oracle-eu-micro1`) → ARM agents → control-plane (`s145`) last.
- **`rpi` has a 900s activation timeout** (vs 600s for all others) due to slower Raspberry Pi hardware — deploys to rpi take longer.

### Profile composition

Every host imports from `profiles/`:
```
base.nix          ← users (duck), weekly GC, minimal footprint
+ server.nix      ← GRUB/systemd-boot, SSH hardening, TZ=Asia/Kolkata
+ tailscale.nix   ← gated on secrets/tailscale/secrets.yaml existing
+ k3s-server.nix  ← s145 only
  OR k3s-agent.nix          ← arm + rpi
  OR k3s-agent-tiny.nix     ← micro nodes (adds zramSwap 50%, max-pods=10)
+ hermes-agent.nix          ← oracle-eu-arm1 only
+ disko-config.nix          ← all except oracle-eu-arm1 (has hardware-configuration.nix)
+ sops.nix                  ← per-host secret declarations
```

Secret gating pattern (used for optional profiles):
```nix
let hasFoo = builtins.pathExists ./path/to/secrets.yaml;
in lib.mkIf hasFoo { ... }
```

Host-specific `configuration.nix` only sets: `networking.hostName`, `services.k3s.nodeName`, `services.k3s.nodeIP`, `services.tailscale.extraUpFlags`, and host-unique hardware/boot overrides.

## SOPS / Secrets

```bash
# REQUIRED before any sops command
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
# Also set by direnv in anywhere/ and by the IaC/Makefile

# Edit
sops anywhere/secrets/<host>/secrets.yaml
sops anywhere/secrets/k3s/secrets.yaml
sops anywhere/secrets/tailscale/secrets.yaml

# Re-key after .sops.yaml changes
sops updatekeys anywhere/secrets/<host>/secrets.yaml

# Test decrypt
sops -d anywhere/secrets/k3s/secrets.yaml >/dev/null

# Generate k3s token
openssl rand -base64 48

# Get age public key from private key
age-keygen -y /var/lib/sops-nix/key.txt

# Provision host age key (online host)
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
sudo age-keygen -y /var/lib/sops-nix/key.txt  # → add public key to .sops.yaml, then sops updatekeys
```

- `sops.age.generateKey = false` on all hosts — keys must be pre-provisioned.
- Shared secrets (`k3s/`, `tailscale/`) are decryptable by all host keys; per-host secrets only by that host + master/mark.

## k3s / Kubernetes

```bash
# Cluster health
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
ssh duck@s145 'sudo k3s kubectl get pods -A'

# KUBECONFIG (set by direnv in anywhere/)
export KUBECONFIG=~/.kube/s145.yaml
kubectl get nodes

# Apply k8s manifests (NOT auto-deployed — manual only)
kubectl apply -f anywhere/k8s/_infra/
kubectl apply -f anywhere/k8s/vaultwarden/

# Flux reconcile
flux reconcile kustomization immich -n flux-system --with-source
```

### Critical k8s/k3s quirks

- **`tiny=true:NoSchedule` taint is NOT in NixOS config.** It must be re-applied manually after every cluster rebuild:
  ```bash
  ssh duck@s145 'sudo k3s kubectl taint node oracle-eu-micro1 tiny=true:NoSchedule --overwrite'
  ssh duck@s145 'sudo k3s kubectl taint node oracle-eu-micro2 tiny=true:NoSchedule --overwrite'
  # Repeat for oracle-in-micro1/2
  ```
- **`k3s serverAddr` is hardcoded** to `https://100.69.231.117:6443` (s145's Tailscale IP) in `profiles/k3s-agent.nix`. If s145's Tailscale IP changes, update this file and redeploy all agents.
- **k8s manifests in `anywhere/k8s/` are NOT auto-deployed.** They are not in k3s's auto-deploy directory. Only Traefik's HelmChartConfig and Cloudflare secret are placed there by NixOS activation via s145's `sops.nix` + `traefik.nix`.
- **Traefik Middleware is namespace-scoped.** App IngressRoutes reference `security-headers` in their own namespace, not `kube-system/security-headers`.
- **All stateful workloads pin `nodeSelector: kubernetes.io/hostname: s145`** because PVCs use `local-path` storage backed by s145's 1 TB HDD.
- **Flux GitOps** syncs `github.com/jesb1n/reborn.nix@main` → `anywhere/clusters/s145/` via `FluxInstance` in `anywhere/operator/flux-instance.yaml`.
- **k3s SQLite state** is at `/var/lib/rancher/k3s/server/db/state.db` on s145 — no automated backup.
- **All cluster traffic flows over `tailscale0`** (`--flannel-iface=tailscale0`).

## Validation Checklist (before proposing changes)

- **Terraform**: `tofu -chdir=IaC fmt -recursive && tofu -chdir=IaC validate`
- **Nix**: `nix flake check` (from `anywhere/`)
- **New Nix files**: `git add <file>` before any `nix eval` or deploy
- **OCI session**: run `make check-auth` if session may have expired

## CI (GitHub Actions)

Both workflows (`apply.yml`, `destroy.yml`) are **manual-only** (`workflow_dispatch`). They use OpenTofu 1.9.1 on `ubuntu-latest`, write S3 backend creds from GitHub Secrets, and run the standard init → plan → apply/destroy flow. If `apply` fails, it pushes `errored.tfstate` to the backend for recovery.

## What Not to Commit

`IaC/terraform.tfvars`, `IaC/*.tfstate*`, `IaC/*.tfplan`, `IaC/errored.tfstate`, `IaC/.terraform/`, `*.pem`, `*.key`, decrypted secrets. Age *public* key files (e.g., `anywhere/secrets/oracle-in-arm1/key.txt`) are safe to commit.

## Related Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — full infrastructure diagram
- [docs/SETUP.md](docs/SETUP.md) — step-by-step provisioning guide
- [docs/PREREQUISITES.md](docs/PREREQUISITES.md) — required tools, accounts, credentials
- [docs/CICD.md](docs/CICD.md) — GitHub Actions secrets and workflow details
- [anywhere/MAINTENANCE.md](anywhere/MAINTENANCE.md) — NixOS host operations runbook (daily checks, rollback, GC, Hermes)
- [anywhere/README.md](anywhere/README.md) — host management, Tailscale setup, nixos-anywhere install
- [.github/instructions/nixos.instructions.md](.github/instructions/nixos.instructions.md) — NixOS deployment rules for GitHub Copilot
