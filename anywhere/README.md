# Managing the NixOS fleet

This directory is the standalone Nix flake for all NixOS hosts and Kubernetes
workloads in this repository. Routine host updates use deploy-rs; destructive
first installs and reinstalls use `nixos-anywhere`.

For daily health checks, deployment, rollback, SOPS, and cluster operations,
see [MAINTENANCE.md](./MAINTENANCE.md). The current host inventory is maintained
in the repository [AGENTS.md](../AGENTS.md#hosts-current-state).

## What this folder is for

Use this folder for evaluation, builds, deploy-rs deployments, and encrypted
secret management.

Do not use `nixos-anywhere` for routine updates on the existing host. `nixos-anywhere` is mainly for installation/reinstallation and can destroy/recreate disks when used with a disk layout.

## Enter the management shell

From the repository root:

```bash
cd anywhere
direnv allow
nix develop
```

`direnv` sets `KUBECONFIG` and `SOPS_AGE_KEY_FILE`; it does **not** load the dev
shell. Use `nix develop`, or prefix commands with `nix develop -c`.

Check:

```bash
nix develop -c nixos-anywhere --help
nix develop -c deploy --help
```

## Inspect the flake

```bash
nix flake show
```

Confirm a host platform:

```bash
nix eval --raw .#nixosConfigurations.oracle-in-micro1.config.nixpkgs.hostPlatform.system
```

Expected:

```text
x86_64-linux
```

## Lock or update inputs

Create/update the lock file without changing the remote host:

```bash
nix flake lock
```

Update all flake inputs:

```bash
nix flake update
```

These commands affect the local `flake.lock`. They do not activate or modify the OCI host.

## Tailscale and k3s secrets with SOPS

Each host decrypts secrets during activation with its age private key at
`/var/lib/sops-nix/key.txt`. Public age recipients are declared in `.sops.yaml`;
shared encrypted values live in `secrets/tailscale/secrets.yaml` and
`secrets/k3s/secrets.yaml`.

Before using `sops` from an operator machine:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops -d secrets/k3s/secrets.yaml >/dev/null
sops -d secrets/tailscale/secrets.yaml >/dev/null
```

The Tailscale auth key must be reusable so multiple hosts can enroll. Never
commit an age private key or decrypted secret. Only `age1...` public recipients
and SOPS-encrypted YAML belong in Git.

When adding a host, generate its age key into a protected operator-only path,
add only the printed public recipient to `.sops.yaml`, re-key the shared SOPS
files, and provision the private key with `--extra-files` during installation.

## Installing the tiny Oracle nodes with nixos-anywhere

All four E2.1.Micro workers use the same NixOS profile stack
(`k3s-agent-tiny` + Disko `/dev/sda`) and the same install constraints:
**1 GB RAM**, so kexec needs a swap file on the Ubuntu target, and the system
closure must be built on a roomier x86 host (prefer **s145**), not on the micro
and not on Apple Silicon.

| Host | Role | Tailscale IP |
|------|------|--------------|
| `oracle-eu-micro1` | k3s agent (`tiny`) | `100.96.237.114` |
| `oracle-eu-micro2` | k3s agent (`tiny`) | `100.67.95.26` |
| `oracle-in-micro1` | k3s agent (`tiny`) | `100.79.237.15` |
| `oracle-in-micro2` | k3s agent (`tiny`) | `100.91.37.26` |

Flake outputs: `.#oracle-eu-micro1`, `.#oracle-eu-micro2`,
`.#oracle-in-micro1`, `.#oracle-in-micro2`.

Warning: `nixos-anywhere` + Disko **wipes** the target disk. Install one node
at a time. Prefer an OCI boot volume backup first.

### Required install flags (all micros)

```bash
nix develop --command nixos-anywhere \
  --debug \
  --flake .#oracle-in-micro2 \
  --target-host ubuntu@<public-or-tailscale-ip> \
  --copy-host-keys \
  --extra-files /tmp/<host>-extra \
  --build-on local \
  --no-disko-deps \
  --kexec-extra-flags "--kexec-syscall"
```

- `--build-on local` — build on the runner (s145), not the 1 GB target
- `--no-disko-deps` — keep kexec RAM pressure down
- `--kexec-extra-flags "--kexec-syscall"` — required on these OCI kernels

### India (`ap-mumbai-1`) full runbook

Age keys, SOPS recipients, SSH bootstrap from s145, Ubuntu swap prep, and
post-install (`nodeIP`, `tiny` taint, deploy-rs) are documented in:

**[docs/ORACLE-IN-MICRO-NIXOS.md](./docs/ORACLE-IN-MICRO-NIXOS.md)**

### Shared secrets (first-time / new host)

Use a **reusable** Tailscale auth key (`sops secrets/tailscale/secrets.yaml`).
Single-use keys fail on the second micro.

Host age private keys go in `--extra-files` as
`/var/lib/sops-nix/key.txt` (see the India runbook). Public keys belong in
`.sops.yaml` and must be recipients of `secrets/k3s/` and `secrets/tailscale/`.

### After install

```bash
ssh duck@oracle-in-micro2 'hostname; systemctl is-system-running; sudo tailscale ip -4'
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
ssh duck@s145 'sudo k3s kubectl taint node oracle-in-micro2 tiny=true:NoSchedule --overwrite'
```

Set `services.k3s.nodeIP` to the Tailscale IPv4 in the host `configuration.nix`,
then `nix develop -c deploy .#oracle-in-micro2`. SSH user after install is
`duck`, not `ubuntu`.

## Safe validation flow

Run these from `anywhere/`.

### 1. Build only

Build the system configuration on the remote host without activating it:

```bash
nix run nixpkgs#nixos-rebuild -- \
  build \
  --flake .#oracle-eu-arm1 \
  --build-host duck@oracle-eu-arm1 \
  --no-reexec \
  --use-substitutes
```

This may copy/download Nix store paths, but it does not switch generations, restart services, install the bootloader, or reboot.

### 2. Dry activation

Preview what activation would do:

```bash
nix run nixpkgs#nixos-rebuild -- \
  dry-activate \
  --flake .#oracle-eu-arm1 \
  --target-host duck@oracle-eu-arm1 \
  --build-host duck@oracle-eu-arm1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

This should show which units would restart/reload. It does not persist the new generation.

### 3. Temporary activation test

Activate the configuration temporarily:

```bash
nix run nixpkgs#nixos-rebuild -- \
  test \
  --flake .#oracle-eu-arm1 \
  --target-host duck@oracle-eu-arm1 \
  --build-host duck@oracle-eu-arm1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

`test` activates the config now, but does not make it the default boot generation. It can restart services such as SSH, NetworkManager, systemd units, and firewall-related units.

Before running `test`, it is wise to have OCI console access available in case SSH drops.

### 4. Verify the host after test

```bash
ssh duck@oracle-eu-arm1 'hostname; systemctl is-system-running; systemctl --failed'
```

Healthy output should look like:

```text
oracle-eu-arm1
running
0 loaded units listed.
```

### 5. Persistent switch

After `dry-activate`, `test`, and verification pass, make the configuration persistent:

```bash
nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oracle-eu-arm1 \
  --target-host duck@oracle-eu-arm1 \
  --build-host duck@oracle-eu-arm1 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

`switch` activates the config, creates a new NixOS generation, updates the bootloader, and makes the generation the default for future boots.

It normally does not reboot the machine.

## Verify the current generation

```bash
ssh duck@oracle-eu-arm1 'readlink -f /run/current-system; sudo nixos-rebuild list-generations | tail; systemctl is-system-running; systemctl --failed'
```

The current generation should be marked `True`, and failed units should be `0`.

## Roll back

If the current running config is bad but SSH still works, roll back to the previous generation:

```bash
ssh duck@oracle-eu-arm1 'sudo nixos-rebuild switch --rollback'
```

Then verify:

```bash
ssh duck@oracle-eu-arm1 'readlink -f /run/current-system; sudo nixos-rebuild list-generations | tail; systemctl is-system-running; systemctl --failed'
```

If the host cannot boot or SSH is unavailable, use the OCI console/serial console and boot an older NixOS generation from the GRUB menu.

## Troubleshooting

### Remote sudo error

If activation fails with an access denied error from `systemd-run`, make sure the command includes:

```text
--elevate=sudo
```

Do not use `--use-remote-sudo`; it is not supported by the `nixos-rebuild`
version used here.

### Signature error when copying from the remote builder

If a build fails while copying paths back to macOS with:

```text
because it lacks a signature by a trusted key
```

the remote build probably succeeded, but macOS refused to import unsigned paths from the remote builder.

The safer path is to continue with `dry-activate`, `test`, or `switch` using both:

```text
--target-host duck@oracle-eu-arm1
--build-host duck@oracle-eu-arm1
```

This avoids relying on importing the final remote-built closure into the local Mac store.

### Dirty Git tree warning

`nixos-rebuild` may warn:

```text
warning: Git tree '...' is dirty
```

This means the flake is being built from local uncommitted changes. After a successful switch, commit the known-good config and lock file so the host state is reproducible.

Review and stage only the intended files after validation. Commit and push only
after explicit operator confirmation.
