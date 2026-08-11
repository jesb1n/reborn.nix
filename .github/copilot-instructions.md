# Repository Copilot Instructions

## Safety and sources of truth

- Do not commit, push, delete, deploy, apply, destroy, or run `nixos-anywhere` unless the user explicitly confirms the state-changing action.
- Read `.github/instructions/nixos.instructions.md` for any change under `anywhere/`. Before changing `anywhere/hosts/pro-darwin/`, also read its `AGENTS.md`; its host-specific rules override general NixOS conventions.
- Prefer current configuration over older prose when they disagree. `anywhere/flake.nix`, `IaC/backend.tf`, and `IaC/provider.tf` are authoritative for build placement, state backend, and OCI authentication.
- Never expose decrypted SOPS values, age private keys, OCI credentials, Terraform state, plans, or PEM/key files. SOPS-encrypted files and `age1...` public recipients may be tracked.

## Validation and operations

### OpenTofu (`IaC/`)

```bash
# Format only .tf files, then validate the initialized configuration
# (recursive tofu fmt also reads SOPS-encrypted *.tfvars and fails)
make -C IaC fmt
tofu -chdir=IaC validate

# Preferred local multi-environment flow; ENV defaults to beijns
make -C IaC ENV=beijns check-auth
make -C IaC ENV=beijns init
make -C IaC ENV=beijns plan
# State-changing; require explicit confirmation
make -C IaC ENV=beijns deploy
```

- There is no unit-test suite; `tofu validate` is the focused static check for IaC changes, and `make -C IaC ENV=<env> plan` is the environment-specific behavioral check.
- Run `check-auth` before operations because the OCI provider uses expiring `SecurityToken` sessions.
- The Makefile decrypts environment data in memory with `sops exec-file`; do not create plaintext `.tfvars` as a workaround.
- The S3-compatible backend is Garage on `s145` (`http://100.69.231.117:31900`), so local init/plan requires Tailscale and backend credentials.

### NixOS and nix-darwin (`anywhere/`)

Run commands from `anywhere/`; `direnv` sets environment variables but does not enter the dev shell.

```bash
# Full flake validation
nix flake check

# Focused evaluation/build for one host (closest equivalent to a single test)
nix eval --raw .#nixosConfigurations.<host>.config.networking.hostName
nix build -L .#nixosConfigurations.<host>.config.system.build.toplevel

# Routine deployment; state-changing, so require confirmation
nix develop -c deploy .#<host>

# pro-darwin is not a deploy-rs node
sudo darwin-rebuild build --flake .#pro-darwin
sudo darwin-rebuild switch --flake .#pro-darwin
```

- Stage newly created Nix files before flake evaluation because flakes do not see untracked files.
- All deploy-rs nodes currently use `remoteBuild = true`. `rpi` uses `nixos-raspberrypi.lib.nixosSystem`; other NixOS hosts use `nixpkgs-unstable`.
- Use deploy-rs for routine changes. `nixos-anywhere` is destructive installation/reinstallation tooling; its special 1 GB micro-node procedure is documented in `anywhere/docs/ORACLE-IN-MICRO-NIXOS.md`.
- For input updates, deploy workers first, ARM agents next, and the `s145` control-plane last.

### Kubernetes and Flux

```bash
# Inspect one Flux-managed app that has kustomization.yaml (single-app check)
kubectl kustomize anywhere/k8s/<app>

# Check a manually managed app without changing the cluster
kubectl apply --dry-run=client -f anywhere/k8s/<app>/

# Manual manifests; state-changing
kubectl apply -f anywhere/k8s/<app>/

# Flux-managed app after commit/push; state-changing
flux reconcile kustomization <app> -n flux-system --with-source
```

- `anywhere/clusters/s145/*.yaml` contains Flux Kustomization CRs that point into `anywhere/k8s/`; application resources live in the latter.
- Not every app directory has a `kustomization.yaml`, and not everything under `anywhere/k8s/` is automatically applied. Follow the app README and its `clusters/s145` registration.

## Architecture

- `IaC/` provisions OCI networking and compute in multiple environments. The provider authenticates through OCI CLI SecurityToken profiles; encrypted environment tfvars and Garage credentials are supplied by SOPS through the Makefile.
- `anywhere/` is an independent flake that configures the machines after provisioning. Shared behavior belongs in `profiles/`; host files compose profiles and hold only identity, node IP, disk, secret declarations, and genuine hardware overrides.
- `s145` is the sole k3s control-plane and durable storage node. All cluster networking uses Tailscale, and agents join `https://100.69.231.117:6443` with flannel on `tailscale0`.
- Flux Operator syncs `main` into the `s145` cluster. `anywhere/operator/` defines the Flux instance, `anywhere/clusters/s145/` registers applications, and `anywhere/k8s/` holds their resources.
- Traefik is the only ingress controller and performs Cloudflare DNS-01 ACME plus global HTTP-to-HTTPS redirect. There is no cert-manager.
- `pro-darwin` is a separate nix-darwin/home-manager output and must never be treated as a NixOS deploy-rs node.

## Repository conventions

- Put fleet-wide users, SSH, GC, boot, firewall, Tailscale, and k3s behavior in the matching `anywhere/profiles/*.nix`; keep `hosts/<name>/configuration.nix` host-specific.
- Optional secret-backed services use `builtins.pathExists` plus `lib.mkIf`. Host age keys are pre-provisioned at `/var/lib/sops-nix/key.txt`; `sops.age.generateKey` remains false.
- Tiny Oracle micro nodes have 1 GB RAM, `zramSwap` at 50%, and `max-pods=10`. Their `tiny=true:NoSchedule` taint is intentionally applied out-of-band after registration.
- Stateful workloads using `local-path` storage pin to `kubernetes.io/hostname: s145`; monitoring is the documented exception and pins to `oracle-in-arm1`.
- Traefik Middleware is namespace-scoped. Public routes use a same-namespace `security-headers` middleware; do not reference `kube-system/security-headers` or add per-app HTTPS redirects.
- Terraform deliberately ignores instance `availability_domain` drift and micro `metadata["user_data"]` changes. Micro cloud-init is one-shot; changing it does not update existing instances.
- Keep `pro-darwin` invariants: Determinate Nix requires `nix.enable = false`, Homebrew cleanup stays `"none"`, timezone stays `Asia/Calcutta`, and custom activation code belongs in `system.activationScripts.postActivation.text`.
