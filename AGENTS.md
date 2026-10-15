# Agent Rules

- **Do not commit, push, or delete until the user explicitly confirms.**
- **Only use best practices** — follow idiomatic conventions for each tool (OpenTofu/Terraform, Nix, k8s, Helm), respect immutability, avoid unnecessary state changes, and prefer upstream/official charts over raw manifests.

# Repository Guidelines

## Project Structure

- `IaC/` — OpenTofu/Terraform; provisions OCI VCN, subnets, and instances.
- `anywhere/` — Standalone Nix flake; manages NixOS configs for all hosts via deploy-rs.
- `docs/` — Architecture, setup, prerequisites, CI/CD docs.
- `anywhere/hosts/pro-darwin/` — nix-darwin config for the maintainer's MacBook (Apple Silicon). Deployed with `darwin-rebuild`, not deploy-rs. **Read `anywhere/hosts/pro-darwin/AGENTS.md` before touching it** — it has host-specific rules (Determinate Nix, Homebrew cleanup=`none`, `Asia/Calcutta` TZ, etc.).

### Hosts (current state)

| Host | Shape | Arch | Role | Tailscale IP |
|------|-------|------|------|-------------|
| `s145` | Home server | x86_64 | **k3s control-plane**, distributed x86_64 builder | `100.69.231.117` |
| `nuc7i3` | Intel NUC | x86_64 | k3s agent | `100.119.33.56` |
| `oracle-eu-arm1` | A1.Flex | aarch64 | k3s agent | `100.84.230.4` |
| `oracle-eu-micro1` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | `100.96.237.114` |
| `oracle-eu-micro2` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | `100.67.95.26` |
| `oracle-in-arm1` | A1.Flex | aarch64 | k3s agent | `100.117.227.112` |
| `oracle-in-micro1` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | `100.79.237.15` |
| `oracle-in-micro2` | E2.1.Micro | x86_64 | k3s agent (tainted `tiny`) | `100.91.37.26` |
| `rpi` | Raspberry Pi 4 | aarch64 | k3s agent | `100.118.166.120` |

The `anywhere/` directory is a standalone Nix flake that manages NixOS configurations and Kubernetes workloads:

```
anywhere/
├── flake.nix              # Inputs, deploy-rs nodes, NixOS configs
├── lib/                   # fleet.nix (host inventory) and binary-caches.nix (cache trust inventory)
├── profiles/              # Shared NixOS modules (base, server, tailscale, k3s-*, auto-upgrade, binary-cache, pihole, smartd)
├── hosts/<hostname>/      # Per-host: configuration.nix, disko-config.nix, sops.nix
├── secrets/<hostname>/    # SOPS-encrypted host secrets (decrypted at activation)
├── clusters/s145/         # Flux Operator GitOps manifests (Kustomizations for apps)
├── k8s/                   # Kubernetes resources (all reconciled by Flux)
├── operator/              # Flux Operator FluxInstance CR
├── scripts/               # fleet-release / fleet-reconcile (GitHub Actions release + reconcile pipeline)
├── tests/                 # fleet-invariants.nix, ssh-access.nix (VM test), fleet-reconcile.sh
├── docs/                  # Planning/runbooks (GATEWAY-NLB-PLAN, K3S-S145-MIGRATION, MCP-VIEWER-PLAN, OPENWRT-BRIDGE-PLAN, ORACLE-IN-MICRO-NIXOS, RPI4-KEXEC-FIX, TRAVELMATE-NIXOS)
├── .sops.yaml             # SOPS creation rules — maps age keys to secret paths
├── .envrc                 # direnv: sets KUBECONFIG + SOPS_AGE_KEY_FILE
├── MAINTENANCE.md         # Runbook for routine ops
└── README.md
```

### Profile-based composition

Host configs import reusable profiles from `anywhere/profiles/`. Shared settings live in profiles; each host only sets what's unique:

| Change needed | Edit this file |
|--------------|----------------|
| SSH keys, user accounts, nix GC settings | `profiles/base.nix` |
| Boot loader, serial console, firewall, SSH settings | `profiles/server.nix` |
| Tailscale enable/openFirewall settings | `profiles/tailscale.nix` |
| k3s server flags, disabled components | `profiles/k3s-server.nix` |
| k3s agent flags, taints, labels, zramSwap | `profiles/k3s-agent.nix` or `profiles/k3s-agent-tiny.nix` |
| Pull-based auto-upgrade schedule/reboot policy | `profiles/auto-upgrade.nix` (`fleet.autoUpgrade.*`) |
| Self-hosted Nix binary cache (nix-serve) | `profiles/binary-cache.nix` (`fleet.binaryCache.*`) + `lib/binary-caches.nix` |
| Pi-hole DNS (rpi) | `profiles/pihole.nix` (`fleet.pihole.*`) |
| Hostname, node IP, Tailscale extra flags | `hosts/<name>/configuration.nix` |
| Disk layout | `hosts/<name>/disko-config.nix` |
| SOPS secret declarations | `hosts/<name>/sops.nix` |

## IaC (OpenTofu/Terraform)

### Commands

```bash
# Format only Terraform files; recursive fmt also reads encrypted *.tfvars
make -C IaC fmt
tofu -chdir=IaC validate

# Local multi-environment workflow (SOPS-integrated)
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijns init
make -C IaC ENV=beijns plan
make -C IaC ENV=beijns deploy  # state-changing
```

### Critical IaC quirks

- **OCI uses SecurityToken auth** (`auth = "SecurityToken"` in `provider.tf`), not inline API keys. The session expires — run `make check-auth` or `oci session authenticate --profile-name <env> --region <region>` before any tofu command. This is what `make check-auth` automates.
- **Backend is self-hosted Garage** (S3-compatible) running on `s145` at `http://100.69.231.117:31900` — NOT OCI Object Storage. Requires Tailscale to be connected. CI bypasses with `skip_credentials_validation = true`.
- **Multi-env secrets**: the `Makefile` uses `sops exec-file <env>.tfvars 'tofu ... -var-file={}'` — never writes plaintext `.tfvars` to disk. `SOPS_AGE_KEY_FILE` is pre-set in the Makefile.
- **`availability_domain` changes are ignored** in instance lifecycle (`ignore_changes`) to prevent recreation.
- **Micro cloud-init is one-shot**: `metadata["user_data"]` is in `ignore_changes` — cloud-init runs only on first boot (installs Tailscale, joins tailnet, then clears user-data). Re-provisioning requires `taint` + `apply`.

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

### Deployment (deploy-rs, preferred)

Deploy from `anywhere/`. Prefer workers first, then control-plane.

- `nix develop -c deploy .#<hostname>`: deploy a single host.
- `nix develop -c deploy --targets .#oracle-eu-micro1 .#oracle-eu-micro2`: deploy multiple hosts.
- `nix develop -c deploy .`: deploy all hosts.

Two distributed builders are registered on `pro-darwin`, one per Linux
architecture: `s145` (x86_64-linux) and `oracle-eu-arm1` (aarch64-linux). The
four Oracle micro nodes build on `s145`; `oracle-in-arm1` and `rpi` build on
`oracle-eu-arm1`. All six use `remoteBuild = false`. The two builder hosts and
`nuc7i3` use `remoteBuild = true`. The separate `nixos-anywhere` installation
flow for 1 GB x86 micro nodes runs from s145 with `--build-on local` so s145
builds the initial closure.

### Auto-upgrade (pull-based, `profiles/auto-upgrade.nix`)

Every host also pulls and rebuilds itself from the git remote on a timer, using
its **own** CPU — the complement to deploy-rs's push model. Enabled fleet-wide
via `fleet.autoUpgrade.enable = true` in `profiles/base.nix`.

- Target: `github:jesb1n/reborn.nix?dir=anywhere#<hostName>` — each node
  self-selects by `networking.hostName`, so one profile covers the whole fleet.
- Schedule: `04:30` + up to 45 min jitter, `Persistent = true` (a node that was
  off catches up on next boot).
- `operation = "switch"` and `allowReboot = true` with a `rebootWindow` of
  `04:00`–`06:00`. A reboot happens only when the new generation actually needs
  one (kernel/initrd/systemd change) and the clock is inside that window;
  otherwise the generation still activates and the reboot defers to a later run.
  The `04:30` timer + ≤45 min jitter lands at `04:30`–`05:15`, inside the window.
  Widen with `fleet.autoUpgrade.rebootWindow`, or set it to `null` for any hour.
- **This never formats anything.** It runs `nixos-rebuild switch`, which builds a
  closure and flips the `/nix/var/nix/profiles/system` symlink. disko and
  `nixos-anywhere` are not involved. Only commits pushed to `main` roll out.
- **Self-hosted mirror later:** set `fleet.autoUpgrade.flakeRef` in `base.nix`
  (e.g. `git+https://git.example.com/jesbin/reborn.nix?dir=anywhere`). Nothing
  else in the profile assumes GitHub, so it's a one-line switch when the mirror
  exists — and it removes the GitHub API/rate-limit dependency for all 9 nodes.

```bash
# Check / drive it on a host
systemctl list-timers nixos-upgrade --all
journalctl -u nixos-upgrade -n 50 --no-pager
sudo systemctl start nixos-upgrade      # force a run now
sudo nixos-rebuild switch --rollback    # undo last auto-upgrade
```

Opt a host out with `fleet.autoUpgrade.enable = false;` in its
`hosts/<name>/configuration.nix`. Override cadence with
`fleet.autoUpgrade.dates`.

Because rollout is now pull-based, **pushing to `main` deploys the fleet.**
Anything merged there reaches every node within ~24h without a manual deploy.

### Kubernetes (s145 cluster)

- `KUBECONFIG` is set by `.envrc` to `~/.kube/s145.yaml`.
- **All apps under `anywhere/k8s/` are Flux-managed**: commit and push to `main`, then `flux reconcile kustomization <name> -n flux-system --with-source`. Do not `kubectl apply` Flux-owned resources; Flux restores Git state. Stateful workloads pin to `s145` via `nodeSelector` so PVCs land on the HDD.
- **From s145 directly** (no kubeconfig, for one-off non-Flux resources only): `ssh duck@s145 'sudo k3s kubectl apply -f -' < file.yaml`.

### Critical NixOS quirks

- **All NixOS systems use `nixpkgs-unstable`**; the `nixpkgs` input (26.05 stable) is only for devShell/tooling (deploy-rs, disko, sops-nix follow it). Exception: `rpi` is built via `nixos-raspberrypi.lib.nixosSystem` (its own nixpkgs), not `nixpkgs-unstable.lib.nixosSystem`.
- **New Nix files must be `git add`-ed before eval or deploy.** Flakes only see tracked/staged files; untracked files cause evaluation errors.
- **Build placement follows `lib/fleet.nix`** — `pro-darwin` registers two
  distributed builders, `s145` (x86_64-linux) and `oracle-eu-arm1`
  (aarch64-linux). The four micro nodes plus `oracle-in-arm1` and `rpi` use
  `remoteBuild = false` and build on the matching builder; the two builder hosts
  and `nuc7i3` use `remoteBuild = true`.
- **A host that is itself a registered builder keeps `remoteBuild = true`.**
  Setting `false` makes Nix offload to that very host, copy the outputs back to
  the Mac, then have deploy-rs push the same closure back. `tests/fleet-invariants.nix`
  enforces this for `s145` and `oracle-eu-arm1`; keep its `builderHosts` list in
  sync with `/etc/nix/machines`.
- **The nix-daemon offloads as root**, so it reads `/etc/ssh/ssh_known_hosts`,
  not your `~/.ssh/known_hosts`. A new builder needs a `programs.ssh.knownHosts`
  entry or offload fails with "Host key verification failed". All builders share
  one key, `/etc/nix/fleet-builder-key`, installed by `postActivation` — it is a
  copy of the maintainer's `~/.ssh/id_ed25519`, which `profiles/base.nix`
  authorizes for `duck` fleet-wide. Rotating that key breaks every builder at once.
- **`pro-darwin`** is a `darwinConfigurations` entry, NOT in `deploy.nodes`. Deploy with `sudo darwin-rebuild switch --flake .#pro-darwin` from `anywhere/`.
- **`nixos-anywhere` is destructive** — reformats the disk via disko. Never use for routine updates; use deploy-rs instead. For 1 GB Oracle micros, run it from **s145**, prep **2G swap** on the Ubuntu target, and use `--build-on local --no-disko-deps --kexec-extra-flags "--kexec-syscall"`. See [anywhere/docs/ORACLE-IN-MICRO-NIXOS.md](anywhere/docs/ORACLE-IN-MICRO-NIXOS.md).
- **`--elevate=sudo`** (not `--use-remote-sudo`) is the correct flag for `nixos-rebuild` remote activation.
- **`s145` overrides GRUB** with systemd-boot (`lib.mkForce`). All other OCI hosts use GRUB from `profiles/server.nix`.
- **Deploy order for input updates**: workers (`oracle-eu-micro2` → `oracle-eu-micro1`) → ARM agents → control-plane (`s145`) last.
- **`rpi` has a 900s activation timeout** (vs 600s for all others) due to slower Raspberry Pi hardware. This covers activation only, not the build — the closure is built on `oracle-eu-arm1`.
- **ARM targets build on `oracle-eu-arm1`**, the registered aarch64-linux builder, since the operator machine `pro-darwin` is aarch64-**darwin** and cannot build Linux derivations. `oracle-eu-arm1` itself still builds on-target.
- **Micro instances have only 1 GB RAM** — zramSwap at 50%, max-pods=10; don't schedule heavy workloads. Tiny taint (`tiny=true:NoSchedule`) is applied out-of-band after node registration.
- **s145 holds critical data** (1 TB XFS at `/home/duck/sda`). Oracle VMs are disposable; loss of any one degrades capacity but not data.
- **Traefik is the only ingress controller** with Cloudflare DNS-01 ACME. No cert-manager. HTTP → HTTPS redirect is global at the Traefik entrypoint.
- **`anywhere/docs/` is planning docs for `anywhere/`**, not the repo root `docs/` which covers IaC/setup.

### Profile composition

Every host imports from `profiles/`:
```
base.nix          ← users (duck), weekly GC, minimal footprint
+ server.nix      ← GRUB/systemd-boot, SSH hardening, TZ=Asia/Kolkata
+ tailscale.nix   ← gated on secrets/tailscale/secrets.yaml existing
+ k3s-server.nix  ← s145 only
  OR k3s-agent.nix          ← arm + rpi + nuc7i3
  OR k3s-agent-tiny.nix     ← micro nodes (adds zramSwap 50%, max-pods=10)
+ binary-cache.nix          ← oracle-eu-arm1 only (self-hosted nix-serve for ARM nodes)
+ pihole.nix                ← rpi only
+ smartd.nix                ← bare metal only (s145, nuc7i3)
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

# Re-key IaC secrets (mark + pro_darwin recipients only — master is retired)
cd IaC
sops updatekeys -y beijns.tfvars beijnseu.tfvars secrets/beijns.env secrets/beijnseu.env

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
- Shared secrets (`k3s/`, `tailscale/`) are decryptable by all host keys; per-host secrets only by that host + pro_darwin/mark.
- **IaC secrets (`IaC/*.tfvars`, `IaC/secrets/*.env`) are encrypted only to `mark` + `pro_darwin`** — the `master` key is retired and appears nowhere in the repo. Both machines can decrypt; neither is required.

## k3s / Kubernetes

```bash
# Cluster health
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
ssh duck@s145 'sudo k3s kubectl get pods -A'

# KUBECONFIG (set by direnv in anywhere/)
export KUBECONFIG=~/.kube/s145.yaml
kubectl get nodes

# Validate manifests without touching the cluster
kubectl kustomize anywhere/k8s/<app>
kubectl apply --dry-run=client -f anywhere/clusters/s145/<app>.yaml

# Flux reconcile (after commit + push to main)
flux get kustomizations -n flux-system
flux reconcile kustomization immich -n flux-system --with-source
```

### Critical k8s/k3s quirks

- **`tiny=true:NoSchedule` taint is NOT in NixOS config.** It must be re-applied manually after every cluster rebuild:
  ```bash
  ssh duck@s145 'sudo k3s kubectl taint node oracle-eu-micro1 tiny=true:NoSchedule --overwrite'
  ssh duck@s145 'sudo k3s kubectl taint node oracle-eu-micro2 tiny=true:NoSchedule --overwrite'
  ssh duck@s145 'sudo k3s kubectl taint node oracle-in-micro1 tiny=true:NoSchedule --overwrite'
  ssh duck@s145 'sudo k3s kubectl taint node oracle-in-micro2 tiny=true:NoSchedule --overwrite'
  ```
- **`k3s serverAddr` is hardcoded** to `https://100.69.231.117:6443` (s145's Tailscale IP) in `profiles/k3s-agent.nix`. If s145's Tailscale IP changes, update this file and redeploy all agents.
- **Every directory in `anywhere/k8s/` is Flux-managed** through a registration in `anywhere/clusters/s145/<app>.yaml` (`infra`, `cloudflared`, `garage`, `immich`, `immich-public-proxy`, `litellm`, `monitoring`, `omniroute`, `vaultwarden`). A new directory deploys nothing until registered. Nothing in `k8s/` is in k3s's auto-deploy directory; only Traefik's HelmChartConfig and the Cloudflare ACME secret get there, via NixOS activation from s145's `sops.nix` + `traefik.nix`. In-cluster secrets are sops-encrypted manifests (`k8s/<app>/*secret.yaml`) keyed to the `s145_cluster` recipient, each with its own `.sops.yaml` creation rule. See `anywhere/k8s/README.md` for conventions.
- **Traefik Middleware is namespace-scoped.** App IngressRoutes reference `security-headers` in their own namespace, not `kube-system/security-headers`.
- **All stateful workloads pin `nodeSelector: kubernetes.io/hostname: s145`** because PVCs use `local-path` storage backed by s145's 1 TB HDD.
- **Flux GitOps** syncs `github.com/jesb1n/reborn.nix@main` → `anywhere/clusters/s145/` via `FluxInstance` in `anywhere/operator/flux-instance.yaml`.
- **k3s SQLite state** is at `/var/lib/rancher/k3s/server/db/state.db` on s145 — no automated backup.
- **All cluster traffic flows over `tailscale0`** (`--flannel-iface=tailscale0`).

## Validation Checklist (before proposing changes)

- **pre-commit**: `.pre-commit-config.yaml` runs on every commit (hygiene, gitleaks, SOPS-encryption guard, AGE key guard, `nix-instantiate --parse`, `tofu fmt`). Run all: `pre-commit run --all-files`. SOPS files are excluded from fixers — never let a tool rewrite them.
- **Claude Code hook**: `.claude/hooks/nix-check.sh` (PostToolUse) parses every edited `.nix` file and evaluates `darwinConfigurations.pro-darwin` when pro-darwin files or `anywhere/flake.nix` change.

- **Terraform**: `make -C IaC fmt && tofu -chdir=IaC validate`
- **Nix**: `nix flake check` (from `anywhere/`)
- **New Nix files**: `git add <file>` before any `nix eval` or deploy
- **OCI session**: run `make -C IaC ENV=<env> check-auth` if the session may have expired

## CI (GitHub Actions)

The OpenTofu workflows (`apply.yml`, `destroy.yml`) are **manual-only** (`workflow_dispatch`). They use OpenTofu 1.9.1 on `ubuntu-latest`, write S3 backend creds from GitHub Secrets, and run the standard init → plan → apply/destroy flow. If `apply` fails, it pushes `errored.tfstate` to the backend for recovery.

Three NixOS workflows also exist: `nixos-ci.yml` (fleet checks, SSH VM test, native x86/ARM closure release via `anywhere/scripts/fleet-release`), `nixos-reconcile.yml` (rebuilds an exact `main` SHA and activates selected hosts via `anywhere/scripts/fleet-reconcile`, check-only by default), and `nix-cache-keys.yml` (validates `lib/binary-caches.nix`; never rotates keys). `nixos-ci` and `nixos-reconcile` are currently **`workflow_dispatch`-only** — automatic PR/push/schedule triggers are paused even though `docs/CICD.md` still describes them. See `CLAUDE.md` and `docs/CICD.md`.

## What Not to Commit

`IaC/terraform.tfvars`, `IaC/*.tfstate*`, `IaC/*.tfplan`, `IaC/errored.tfstate`,
`IaC/.terraform/`, `*.pem`, `*.key`, age private keys, decrypted secrets, and
`anywhere/result` (a leftover `nix build` symlink). SOPS-encrypted files **are**
committed: `IaC/<env>.tfvars`, `IaC/secrets/<env>.env`, and
`anywhere/secrets/**/*.yaml`. An `age1...` recipient is public and belongs in
`.sops.yaml`; an `AGE-SECRET-KEY-...` value is private and must never be
committed. Legacy tracked `anywhere/secrets/*/key.txt` private keys require
separate rotation/removal and must not be copied as a pattern for new hosts.

## Related Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — full infrastructure diagram
- [docs/SETUP.md](docs/SETUP.md) — step-by-step provisioning guide
- [docs/PREREQUISITES.md](docs/PREREQUISITES.md) — required tools, accounts, credentials
- [docs/CICD.md](docs/CICD.md) — GitHub Actions secrets and workflow details
- [anywhere/MAINTENANCE.md](anywhere/MAINTENANCE.md) — NixOS host operations runbook (daily checks, rollback, GC, ARM binary cache)
- [anywhere/README.md](anywhere/README.md) — host management, Tailscale setup, nixos-anywhere install
- [anywhere/docs/ORACLE-IN-MICRO-NIXOS.md](anywhere/docs/ORACLE-IN-MICRO-NIXOS.md) — India E2.1.Micro Ubuntu → NixOS via nixos-anywhere (s145 builder, swap prep)
- [.github/instructions/nixos.instructions.md](.github/instructions/nixos.instructions.md) — NixOS deployment rules for GitHub Copilot
- [anywhere/docs/K3S-S145-MIGRATION.md](anywhere/docs/K3S-S145-MIGRATION.md) — cluster migration runbook from oracle-eu-arm1 to s145
- [anywhere/docs/GATEWAY-NLB-PLAN.md](anywhere/docs/GATEWAY-NLB-PLAN.md) — planned OCI NLB + Gateway API rollout
