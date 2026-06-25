# Managing the OCI NixOS Host

This folder contains the flake used to manage the OCI ARM NixOS host.

For day-to-day maintenance, update, rollback, SOPS, and k3s cluster commands, see [MAINTENANCE.md](./MAINTENANCE.md).

Current host:

```text
oci-nixos -> ubuntu@129.159.222.42
```

The flake output is:

```text
.#oci-nixos
```

## What this folder is for

Use this folder for normal NixOS management with `nixos-rebuild`.

Do not use `nixos-anywhere` for routine updates on the existing host. `nixos-anywhere` is mainly for installation/reinstallation and can destroy/recreate disks when used with a disk layout.

## Enter the management shell

From this folder:

```bash
cd anywhere
direnv allow
```

If direnv is already allowed, entering the folder should make tools like `nixos-anywhere` available.

Check:

```bash
which nixos-anywhere
nixos-anywhere --help
```

## Inspect the flake

```bash
nix flake show
```

Confirm the host platform:

```bash
nix eval --raw .#nixosConfigurations.oci-nixos.config.nixpkgs.hostPlatform.system
```

Expected:

```text
aarch64-linux
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

## Tailscale with SOPS

Tailscale is configured declaratively in `hosts/oci-nixos/configuration.nix`.

Secrets follow the same host-key pattern as `retire.nix`:

- your Mac has a master age key for editing secrets;
- the OCI host has its own age key at `/var/lib/sops-nix/key.txt`;
- encrypted host secrets live under `secrets/oci-nixos/`;
- `sops-nix` decrypts them into `/run/secrets/` during activation.

The service can start without a SOPS secret, but automatic login requires an encrypted SOPS file at:

```text
secrets/oci-nixos/secrets.yaml
```

### 1. Generate your master age key on the Mac

```bash
mkdir -p ~/.config/sops/age
test -f ~/.config/sops/age/keys.txt || age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt
```

Keep the private key in `~/.config/sops/age/keys.txt` private.

### 2. Generate the host age key on oci-nixos

This is the key that `sops-nix` will use on the host during activation.

```bash
ssh ubuntu@129.159.222.42 'sudo mkdir -p /var/lib/sops-nix && sudo age-keygen -o /var/lib/sops-nix/key.txt && sudo chmod 600 /var/lib/sops-nix/key.txt && sudo age-keygen -y /var/lib/sops-nix/key.txt'
```

Copy the printed public key.

If `age-keygen` is missing on the host, deploy this config once without the
secret first. The host config includes `age` in `environment.systemPackages`, so
`age-keygen` will be available after that switch.

### 3. Create `.sops.yaml`

Copy the template and replace both public keys:

```bash
cp .sops.yaml.example .sops.yaml
```

The final file should look like:

```yaml
keys:
  - &master age1YOUR_MASTER_PUBLIC_AGE_KEY
  - &oci_nixos age1YOUR_OCI_NIXOS_PUBLIC_AGE_KEY

creation_rules:
  - path_regex: secrets/oci-nixos/.*
    key_groups:
      - age:
          - *master
          - *oci_nixos
```

### 4. Create the encrypted Tailscale auth key secret

```bash
mkdir -p secrets/oci-nixos
sops secrets/oci-nixos/secrets.yaml
```

Add this plaintext while inside the editor opened by `sops`:

```yaml
tailscale-auth-key: "tskey-auth-xxxxx"
```

Save and quit. The file written to disk should be encrypted.

### 5. Deploy

This repository is a Git flake. Nix only sees files that are tracked or staged,
so add the new Nix/SOPS files before evaluating or deploying:

```bash
git add .sops.yaml hosts/oci-nixos/sops.nix secrets/oci-nixos/README.md
```

Also add the encrypted secret after creating it:

```bash
git add secrets/oci-nixos/secrets.yaml
```

Use the normal safe validation flow below: `dry-activate`, then `switch`.

After switching, verify:

```bash
ssh ubuntu@129.159.222.42 'sudo tailscale status; sudo tailscale ip -4'
```

## Installing the tiny Oracle nodes with nixos-anywhere

The two Ubuntu micro VMs are configured as future NixOS k3s agent nodes:

```text
oracle-eu-micro1 -> oracle-eu-micro1-instance.panther-company.ts.net -> 100.107.80.116
oracle-eu-micro2 -> oracle-eu-micro2-instance.panther-company.ts.net -> 100.67.95.26
```

Their flake outputs are:

```text
.#oracle-eu-micro1
.#oracle-eu-micro2
```

These configs use Disko and target `/dev/sda`.

Warning: `nixos-anywhere` will wipe the Ubuntu installation on the selected micro VM.
Take an OCI boot volume backup first, and install one node at a time.

### 1. Create host age keys locally

For a new nixos-anywhere install, create each host's age private key locally,
then pass it into the installed NixOS system with `--extra-files`.

```bash
mkdir -p /tmp/oracle-eu-micro1-extra/var/lib/sops-nix
age-keygen -o /tmp/oracle-eu-micro1-extra/var/lib/sops-nix/key.txt
chmod 600 /tmp/oracle-eu-micro1-extra/var/lib/sops-nix/key.txt
age-keygen -y /tmp/oracle-eu-micro1-extra/var/lib/sops-nix/key.txt
```

Repeat for micro2:

```bash
mkdir -p /tmp/oracle-eu-micro2-extra/var/lib/sops-nix
age-keygen -o /tmp/oracle-eu-micro2-extra/var/lib/sops-nix/key.txt
chmod 600 /tmp/oracle-eu-micro2-extra/var/lib/sops-nix/key.txt
age-keygen -y /tmp/oracle-eu-micro2-extra/var/lib/sops-nix/key.txt
```

Copy the printed public keys.

### 2. Add the micro public keys to `.sops.yaml`

Add these keys:

```yaml
  - &oracle_eu_micro1 age1MICRO1_PUBLIC_KEY
  - &oracle_eu_micro2 age1MICRO2_PUBLIC_KEY
```

Add rules for the host secrets:

```yaml
  - path_regex: secrets/oracle-eu-micro1/.*
    key_groups:
      - age:
          - *master
          - *oracle_eu_micro1

  - path_regex: secrets/oracle-eu-micro2/.*
    key_groups:
      - age:
          - *master
          - *oracle_eu_micro2
```

Add the shared k3s secret rule:

```yaml
  - path_regex: secrets/k3s/.*
    key_groups:
      - age:
          - *master
          - *oci_nixos
          - *oracle_eu_micro1
          - *oracle_eu_micro2
```

### 3. Create the micro Tailscale secrets

Use a reusable Tailscale auth key.

```bash
sops secrets/oracle-eu-micro1/secrets.yaml
```

Plaintext while editing:

```yaml
tailscale-auth-key: "tskey-auth-xxxxx"
```

Repeat:

```bash
sops secrets/oracle-eu-micro2/secrets.yaml
```

Plaintext while editing:

```yaml
tailscale-auth-key: "tskey-auth-xxxxx"
```

### 4. Create the shared k3s token secret

Generate a token:

```bash
openssl rand -base64 48
```

Create the encrypted secret:

```bash
sops secrets/k3s/secrets.yaml
```

Plaintext while editing:

```yaml
k3s-token: "paste-the-generated-token"
```

### 5. Stage files before evaluating

This repository is a Git flake. Nix only sees tracked/staged files.

From `anywhere/`:

```bash
git add flake.nix flake.lock .sops.yaml .sops.yaml.example README.md
git add hosts/oci-nixos/configuration.nix hosts/oci-nixos/sops.nix
git add hosts/oracle-eu-micro1 hosts/oracle-eu-micro2
git add secrets/k3s secrets/oracle-eu-micro1 secrets/oracle-eu-micro2
```

### 6. Validate evaluation

```bash
nix eval --raw .#nixosConfigurations.oracle-eu-micro1.config.nixpkgs.hostPlatform.system
nix eval --raw .#nixosConfigurations.oracle-eu-micro2.config.nixpkgs.hostPlatform.system
```

Expected:

```text
x86_64-linux
```

### 7. Install micro1

After taking an OCI boot volume backup for micro1:

```bash
nixos-anywhere \
  --flake .#oracle-eu-micro1 \
  --target-host ubuntu@oracle-eu-micro1-instance.panther-company.ts.net \
  --copy-host-keys \
  --extra-files /tmp/oracle-eu-micro1-extra
```

After reboot:

```bash
ssh ubuntu@oracle-eu-micro1.panther-company.ts.net 'hostname; systemctl is-system-running; systemctl --failed; sudo tailscale status'
```

### 8. Install micro2

Only after micro1 is healthy, take an OCI boot volume backup for micro2 and run:

```bash
nixos-anywhere \
  --flake .#oracle-eu-micro2 \
  --target-host ubuntu@oracle-eu-micro2-instance.panther-company.ts.net \
  --copy-host-keys \
  --extra-files /tmp/oracle-eu-micro2-extra
```

After reboot:

```bash
ssh ubuntu@oracle-eu-micro2.panther-company.ts.net 'hostname; systemctl is-system-running; systemctl --failed; sudo tailscale status'
```

### 9. Verify k3s

After the server and agents are installed:

```bash
ssh ubuntu@129.159.222.42 'sudo k3s kubectl get nodes -o wide'
```

The micro nodes are tainted:

```text
tiny=true:NoSchedule
```

Only workloads with the matching toleration should run there.

## Safe validation flow

Run these from `anywhere/`.

### 1. Build only

Build the system configuration on the remote host without activating it:

```bash
nix run nixpkgs#nixos-rebuild -- \
  build \
  --flake .#oci-nixos \
  --build-host ubuntu@129.159.222.42 \
  --no-reexec \
  --use-substitutes
```

This may copy/download Nix store paths, but it does not switch generations, restart services, install the bootloader, or reboot.

### 2. Dry activation

Preview what activation would do:

```bash
nix run nixpkgs#nixos-rebuild -- \
  dry-activate \
  --flake .#oci-nixos \
  --target-host ubuntu@129.159.222.42 \
  --build-host ubuntu@129.159.222.42 \
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
  --flake .#oci-nixos \
  --target-host ubuntu@129.159.222.42 \
  --build-host ubuntu@129.159.222.42 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

`test` activates the config now, but does not make it the default boot generation. It can restart services such as SSH, NetworkManager, systemd units, and firewall-related units.

Before running `test`, it is wise to have OCI console access available in case SSH drops.

### 4. Verify the host after test

```bash
ssh ubuntu@129.159.222.42 'hostname; systemctl is-system-running; systemctl --failed'
```

Healthy output should look like:

```text
oci-nixos
running
0 loaded units listed.
```

### 5. Persistent switch

After `dry-activate`, `test`, and verification pass, make the configuration persistent:

```bash
nix run nixpkgs#nixos-rebuild -- \
  switch \
  --flake .#oci-nixos \
  --target-host ubuntu@129.159.222.42 \
  --build-host ubuntu@129.159.222.42 \
  --elevate=sudo \
  --no-reexec \
  --use-substitutes
```

`switch` activates the config, creates a new NixOS generation, updates the bootloader, and makes the generation the default for future boots.

It normally does not reboot the machine.

## Verify the current generation

```bash
ssh ubuntu@129.159.222.42 'readlink -f /run/current-system; sudo nixos-rebuild list-generations | tail; systemctl is-system-running; systemctl --failed'
```

The current generation should be marked `True`, and failed units should be `0`.

## Roll back

If the current running config is bad but SSH still works, roll back to the previous generation:

```bash
ssh ubuntu@129.159.222.42 'sudo nixos-rebuild switch --rollback'
```

Then verify:

```bash
ssh ubuntu@129.159.222.42 'readlink -f /run/current-system; sudo nixos-rebuild list-generations | tail; systemctl is-system-running; systemctl --failed'
```

If the host cannot boot or SSH is unavailable, use the OCI console/serial console and boot an older NixOS generation from the GRUB menu.

## Troubleshooting

### Remote sudo error

If activation fails with an access denied error from `systemd-run`, make sure the command includes:

```text
--elevate=sudo
```

Older examples may use `--use-remote-sudo`, but that option is deprecated.

### Signature error when copying from the remote builder

If a build fails while copying paths back to macOS with:

```text
because it lacks a signature by a trusted key
```

the remote build probably succeeded, but macOS refused to import unsigned paths from the remote builder.

The safer path is to continue with `dry-activate`, `test`, or `switch` using both:

```text
--target-host ubuntu@129.159.222.42
--build-host ubuntu@129.159.222.42
```

This avoids relying on importing the final remote-built closure into the local Mac store.

### Dirty Git tree warning

`nixos-rebuild` may warn:

```text
warning: Git tree '...' is dirty
```

This means the flake is being built from local uncommitted changes. After a successful switch, commit the known-good config and lock file so the host state is reproducible.

Suggested commit:

```bash
git status
git add anywhere/flake.nix anywhere/flake.lock anywhere/.sops.yaml anywhere/.sops.yaml.example anywhere/hosts/oci-nixos/configuration.nix anywhere/hosts/oci-nixos/hardware-configuration.nix anywhere/hosts/oci-nixos/sops.nix anywhere/secrets/oci-nixos/README.md anywhere/secrets/oci-nixos/secrets.yaml anywhere/README.md
git commit -m "Manage OCI NixOS host with flake"
```
