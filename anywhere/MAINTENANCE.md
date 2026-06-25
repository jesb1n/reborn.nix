# Maintaining the OCI NixOS hosts

This repo manages three NixOS machines:

| Host | Role | Architecture | Access |
| --- | --- | --- | --- |
| `oci-nixos` | k3s control-plane | `aarch64-linux` | `ubuntu@129.159.222.42` or `ubuntu@oci-nixos` |
| `oracle-eu-micro1` | k3s worker | `x86_64-linux` | `ubuntu@oracle-eu-micro1` |
| `oracle-eu-micro2` | k3s worker | `x86_64-linux` | `ubuntu@oracle-eu-micro2` |

The preferred management machine is `s145`, because it is AMD/x86 and can build the two micro nodes locally.

## Recommendation: use `nixos-rebuild` for now

For this setup, plain `nixos-rebuild` is the best default:

- it is already working;
- it is easy to understand when something goes wrong;
- it handles one host at a time, which is safer for a small cluster;
- it does not require adding another deployment framework yet.

`deploy-rs` is viable later, especially if you want a single command to deploy all machines, parallel deploys, and automatic activation rollback behavior. But it adds another layer of flake outputs and deployment rules. It also does not remove the need to think about CPU architecture, SSH access, sudo, SOPS keys, and trusted Nix users.

My current advice: keep using `nixos-rebuild` until the cluster grows beyond a few machines or you want CI/CD-style deployments.

## Daily health checks

From any machine that can SSH into the control-plane:

```bash
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get nodes -o wide'
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get pods -A'
```

Check each NixOS host:

```bash
ssh ubuntu@129.159.222.42 'hostname; systemctl is-system-running; systemctl --failed'
ssh ubuntu@oracle-eu-micro1 'hostname; systemctl is-system-running; systemctl --failed'
ssh ubuntu@oracle-eu-micro2 'hostname; systemctl is-system-running; systemctl --failed'
```

Check Tailscale:

```bash
ssh ubuntu@129.159.222.42 'sudo tailscale status'
ssh ubuntu@oracle-eu-micro1 'sudo tailscale ip -4'
ssh ubuntu@oracle-eu-micro2 'sudo tailscale ip -4'
```

The hosts intentionally do not install convenience tools like `vim`, `nano`, `git`, `curl`, `wget`, `htop`, or `tmux`. If you need a temporary tool while debugging, use `nix shell` on the host:

```bash
ssh ubuntu@oracle-eu-micro1
nix shell nixpkgs#vim nixpkgs#curl
```

If a node's Tailscale IP changes, update that host's `services.k3s.nodeIP` in:

```text
hosts/<host>/configuration.nix
```

Then deploy that host again.

## Normal edit and deploy flow

From `s145`:

```bash
cd ~/oracle-cloud-free-tier/anywhere
git status --short
```

Evaluate a value before deploying:

```bash
nix eval --raw .#nixosConfigurations.oracle-eu-micro1.config.networking.hostName
nix eval --raw .#nixosConfigurations.oracle-eu-micro1.config.services.k3s.nodeIP
```

Build only, without activating:

```bash
nix build -L .#nixosConfigurations.oracle-eu-micro1.config.system.build.toplevel
nix build -L .#nixosConfigurations.oracle-eu-micro2.config.system.build.toplevel
```

For `oci-nixos`, build on the ARM host itself:

```bash
nix run nixpkgs#nixos-rebuild -- \
  build \
  --flake .#oci-nixos \
  --build-host ubuntu@129.159.222.42 \
  --no-reexec \
  --use-substitutes
```

## Deploy commands

### Deploy `oracle-eu-micro1`

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oracle-eu-micro1 \
  --target-host ubuntu@oracle-eu-micro1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

### Deploy `oracle-eu-micro2`

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oracle-eu-micro2 \
  --target-host ubuntu@oracle-eu-micro2 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

### Deploy `oci-nixos`

`oci-nixos` is ARM, so from `s145` it should build remotely on the target host:

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oci-nixos \
  --target-host ubuntu@129.159.222.42 \
  --build-host ubuntu@129.159.222.42 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

## Safer pre-flight before `switch`

Use `dry-activate` when you want to see what would restart:

```bash
nix run nixpkgs#nixos-rebuild -- \
  dry-activate \
  --flake .#oracle-eu-micro1 \
  --target-host ubuntu@oracle-eu-micro1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

Use `test` when you want to activate temporarily until reboot:

```bash
nix run nixpkgs#nixos-rebuild -- \
  test \
  --flake .#oracle-eu-micro1 \
  --target-host ubuntu@oracle-eu-micro1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

Use `switch` only when you want the generation to become the boot default.

## After every deploy

Check the target:

```bash
ssh ubuntu@oracle-eu-micro1 'readlink -f /run/current-system; systemctl is-system-running; systemctl --failed'
```

Check the cluster:

```bash
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get nodes -o wide'
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get pods -A'
```

## Rollback

Rollback the current host to the previous generation:

```bash
ssh ubuntu@oracle-eu-micro1 'sudo nixos-rebuild switch --rollback'
```

Check generations:

```bash
ssh ubuntu@oracle-eu-micro1 'sudo nixos-rebuild list-generations | tail'
```

If the system is unreachable after a bad boot, use Oracle Cloud console recovery. This is why one-host-at-a-time deploys are safer for this cluster.

## SOPS secrets

Use the local age key on `s145`:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

Edit secrets:

```bash
sops secrets/k3s/secrets.yaml
sops secrets/oci-nixos/secrets.yaml
sops secrets/oracle-eu-micro1/secrets.yaml
sops secrets/oracle-eu-micro2/secrets.yaml
```

Test decrypt:

```bash
sops -d secrets/k3s/secrets.yaml >/dev/null && echo k3s-ok
sops -d secrets/oracle-eu-micro1/secrets.yaml >/dev/null && echo micro1-ok
sops -d secrets/oracle-eu-micro2/secrets.yaml >/dev/null && echo micro2-ok
```

If you add a new admin key or host key, update `.sops.yaml` and rekey the affected files:

```bash
sops updatekeys secrets/k3s/secrets.yaml
sops updatekeys secrets/oracle-eu-micro1/secrets.yaml
sops updatekeys secrets/oracle-eu-micro2/secrets.yaml
```

Do not commit unencrypted secrets.

## Updating Nix inputs

Inspect current inputs:

```bash
nix flake metadata
```

Update all inputs:

```bash
nix flake update
```

Or update only one input:

```bash
nix flake lock --update-input nixpkgs
```

Then build and deploy one host first. Do not update all machines at once.

Suggested order:

1. `oracle-eu-micro2`
2. `oracle-eu-micro1`
3. `oci-nixos`

Keep the control-plane last unless the change is specifically for it.

## `nixos-anywhere` is for reinstalling

Use `nixos-anywhere` only when installing/reinstalling a machine.

Important: the normal `nixos-anywhere` flow with `disko` reformats the target disk. It is not the day-to-day update command.

For normal maintenance, use `nixos-rebuild switch`.

If you ever need to reinstall a micro node:

```bash
cd ~/oracle-cloud-free-tier/anywhere

nix run github:nix-community/nixos-anywhere -- \
  --debug \
  --flake .#oracle-eu-micro2 \
  --target-host ubuntu@89.168.126.35 \
  --copy-host-keys \
  --extra-files /tmp/oracle-eu-micro2-extra \
  --build-on local \
  --no-disko-deps \
  --kexec-extra-flags "--kexec-syscall"
```

Only run this when you are prepared to destroy and recreate that machine's OS disk.

## Terraform / OCI network changes

From the repo root:

```bash
tofu fmt -check
tofu plan -out=tfplan
tofu apply tfplan
```

Use Terraform/OpenTofu for OCI infrastructure changes such as security list rules, instance creation, public IPs, and networking.

Use Nix for OS/service changes such as Tailscale, k3s, users, SSH keys, packages, and systemd services.

## Tiny worker notes

The 1 vCPU / 1 GB RAM workers should stay protected from accidental heavy workloads.

Check taints:

```bash
ssh ubuntu@129.159.222.42 'sudo k3s kubectl describe nodes | grep -E "Name:|Taints:"'
```

If a workload should run on the tiny nodes, give it an explicit toleration for:

```text
tiny=true:NoSchedule
```

This keeps the little machines useful without letting Kubernetes schedule random heavy pods onto them.
