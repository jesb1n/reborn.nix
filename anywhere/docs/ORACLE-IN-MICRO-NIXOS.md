# Oracle India micro nodes → NixOS (nixos-anywhere)

Runbook for installing (or reinstalling) `oracle-in-micro1` / `oracle-in-micro2`
from stock Ubuntu to NixOS with `nixos-anywhere` + Disko. Captures the August
2026 migration in OCI region `ap-mumbai-1`.

Status after that migration: both hosts are NixOS k3s agents, tainted `tiny`,
and running (`remoteBuild = false` in `deploy.nodes`, per the current build
constraints). This procedure remains the active runbook for any future
reinstall of these hosts.

| Host | Tailscale IP | Public IP (install-time; may change) |
|------|--------------|--------------------------------------|
| `oracle-in-micro1` | `100.79.237.15` | `130.210.0.72` |
| `oracle-in-micro2` | `100.91.37.26` | `161.118.161.51` |

Configs match the EU micros: `qemu-guest` + `base` + `server` + `tailscale` +
`k3s-agent-tiny` + Disko `/dev/sda` + shared k3s/Tailscale SOPS.

## Why not build on the Mac or on the micro itself

- **Mac (Apple Silicon)** cannot practically build `x86_64-linux` closures for these hosts.
- **E2.1.Micro (1 GB RAM)** OOMs if it builds the system or if kexec runs without swap.
- **Use `s145`** (NixOS, x86_64, enough RAM) as the nixos-anywhere runner with
  `--build-on local` (local = s145).

Do not use `--build-on remote` (builds on the 1 GB target).

## Prerequisites (already done for India micros)

- Host configs under `hosts/oracle-in-micro{1,2}/`
- Host public age recipients in `.sops.yaml`; matching private keys available
  from a protected operator-only location
- Shared `secrets/k3s/secrets.yaml` and `secrets/tailscale/secrets.yaml` include
  the India micro recipients
- `deploy.nodes` entries use `sshUser = "duck"`, MagicDNS hostname,
  `remoteBuild = false` (Mac-initiated deploys build the `x86_64-linux`
  closure through the hp348 distributed builder; see
  `.github/instructions/nixos.instructions.md`)

Tailscale auth key in SOPS must be **reusable**. A single-use key is consumed by
the first host that joins; the second host then fails with
`invalid key: API key … not valid`.

> Security note: age private keys are credentials. Never commit them or include
> them in a general flake archive. The historical migration used legacy
> `secrets/oracle-in-micro*/key.txt` files that are currently tracked; treat
> those keys as exposed and rotate/move them before a future reinstall. Only
> `age1...` public recipients belong in `.sops.yaml`.

## Procedure

Install **one host at a time**. Optional but recommended: OCI Console → boot
volume backup before wipe.

### 1. Authorize s145 → Ubuntu target SSH

Neither Ubuntu micro has an SSH private key (only OCI `authorized_keys`). From
the Mac (which already has access), append s145’s pubkey:

```bash
S145_PUB=$(ssh duck@s145 'cat ~/.ssh/id_ed25519.pub')
# micro2 example — use the current public IP for the target
ssh ubuntu@161.118.161.51 "mkdir -p ~/.ssh && chmod 700 ~/.ssh &&
  grep -qxF '$S145_PUB' ~/.ssh/authorized_keys || echo '$S145_PUB' >> ~/.ssh/authorized_keys"

ssh duck@s145 'ssh -o StrictHostKeyChecking=accept-new ubuntu@161.118.161.51 hostname'
```

That `authorized_keys` entry lives on the Ubuntu rootfs and is **destroyed by
Disko** — no cleanup needed on the target.

### 2. Copy the flake onto s145

Prefer a full tree copy from the Mac (includes lockfile + encrypted secrets).
s145 often has no `rsync` on PATH:

```bash
ssh duck@s145 'mkdir -p ~/reborn-anywhere'
tar -C anywhere \
  --exclude='result' --exclude='result-*' --exclude='.direnv' \
  --exclude='.git' --exclude='secrets/*/key.txt' \
  -czf - . | ssh duck@s145 'tar -xzf - -C ~/reborn-anywhere'
# Strip macOS AppleDouble junk if present
ssh duck@s145 'cd ~/reborn-anywhere && find . -name "._*" -delete; find . -name ".DS_Store" -delete'
```

Do **not** copy results back from s145 afterward — the Mac repo remains source of
truth for commits. s145’s tree is a disposable install workspace.

### 3. Transfer and stage the host age key for `--extra-files`

Use the private key matching the host's public recipient in `.sops.yaml`. Keep
it outside the repository and transfer it separately from the general flake
archive. The following assumes an operator-only key file on the Mac:

```bash
HOST=oracle-in-micro2
HOST_KEY_SOURCE="$HOME/.config/sops/age/hosts/${HOST}.txt"

test -f "$HOST_KEY_SOURCE"
age-keygen -y "$HOST_KEY_SOURCE"
ssh duck@s145 \
  'install -d -m 700 /tmp/oracle-in-micro2-extra/var/lib/sops-nix &&
   install -m 600 /dev/stdin /tmp/oracle-in-micro2-extra/var/lib/sops-nix/key.txt' \
  < "$HOST_KEY_SOURCE"
```

Compare the `age-keygen -y` output with the `oracle_in_micro2` recipient in
`.sops.yaml` before proceeding. Use the same pattern for micro1.

SOPS decrypt during build is **not** required on s145. Encrypted YAML is enough;
the target decrypts at activation with the age key above.

### 4. Prepare the Ubuntu target (required on 1 GB)

Without this, kexec OOMs (~430 MB RSS) and nixos-anywhere fails with
`Out of memory: Killed process … (kexec)`.

```bash
ssh ubuntu@<public-ip> 'bash -s' <<'EOF'
set -euo pipefail
sudo systemctl stop snapd.service snapd.socket oracle-cloud-agent.service 2>/dev/null || true
sudo systemctl stop unattended-upgrades 2>/dev/null || true
sudo sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
fi
free -h
EOF
```

Confirm SSH still works from s145 and that `/dev/sda` is the intended boot disk:

```bash
ssh duck@s145 'ssh ubuntu@<public-ip> "findmnt /; lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS /dev/sda"'
```

### 5. Run `nixos-anywhere` from s145

```bash
ssh duck@s145
cd ~/reborn-anywhere

# Optional: duck user nix.conf if flake nixConfig warnings appear
# (durable fix is nix.settings.accept-flake-config in profiles/base.nix)
mkdir -p ~/.config/nix
printf '%s\n' \
  'accept-flake-config = true' \
  'extra-experimental-features = nix-command flakes' \
  > ~/.config/nix/nix.conf

nix develop --command nixos-anywhere \
  --debug \
  --flake .#oracle-in-micro2 \
  --target-host ubuntu@161.118.161.51 \
  --copy-host-keys \
  --extra-files /tmp/oracle-in-micro2-extra \
  --build-on local \
  --no-disko-deps \
  --kexec-extra-flags "--kexec-syscall"
```

Required flags for these micros:

| Flag | Why |
|------|-----|
| `--build-on local` | Build on s145, not the 1 GB target |
| `--no-disko-deps` | Lower kexec RAM pressure |
| `--kexec-extra-flags "--kexec-syscall"` | Needed on the observed OCI Ubuntu kernels |
| `--debug` | Trace kexec / Disko / upload failures |

This command is the destructive boundary: Disko reformats `/dev/sda`. During
kexec, SSH to `ubuntu@` will fail; that is expected. Wait for `### Done! ###`.

### 6. Post-install

After reboot, SSH is `duck@` (keys from `profiles/base.nix`). `--copy-host-keys`
should preserve the SSH host identity; if verification still reports a changed
key, compare it through the OCI console before replacing the local entry:

```bash
ssh-keygen -R oracle-in-micro2
ssh -o StrictHostKeyChecking=accept-new duck@oracle-in-micro2 hostname
```

Verify:

```bash
ssh duck@oracle-in-micro2 'hostname; systemctl is-system-running; systemctl --failed; sudo tailscale ip -4'
ssh duck@s145 'sudo k3s kubectl get nodes -o wide'
```

Then on the Mac (source of truth):

1. Set `services.k3s.nodeIP` to the Tailscale IPv4 in
   `hosts/oracle-in-microN/configuration.nix`
2. Ensure `deploy.nodes.oracle-in-microN` uses `hostname = "oracle-in-microN"`,
   `sshUser = "duck"`, `remoteBuild = false`
3. Apply the tiny taint (not in NixOS config):

```bash
ssh duck@s145 'sudo k3s kubectl taint node oracle-in-micro2 tiny=true:NoSchedule --overwrite'
ssh duck@s145 'sudo k3s kubectl get node oracle-in-micro2 -o jsonpath="{.spec.taints}"; echo'
```

4. Deploy nodeIP (and any other pending config) from `anywhere/`:

```bash
nix develop -c deploy --targets .#oracle-in-micro1 .#oracle-in-micro2
```

Verify the deployed generations and cluster health:

```bash
ssh duck@oracle-in-micro1 'readlink -f /run/current-system; systemctl is-system-running; systemctl --failed'
ssh duck@oracle-in-micro2 'readlink -f /run/current-system; systemctl is-system-running; systemctl --failed'
ssh duck@s145 'sudo k3s kubectl get nodes -o wide; sudo k3s kubectl get pods -A'
```

After the host has successfully decrypted its SOPS secrets, remove the staged
installer copy of the private key from s145:

```bash
ssh duck@s145 'rm -f /tmp/oracle-in-micro2-extra/var/lib/sops-nix/key.txt'
```

If Tailscale autoconnect failed (`invalid key`), join manually once:

```bash
sudo tailscale up --accept-dns=false --hostname=oracle-in-micro1
# complete browser auth, then restart k3s
sudo systemctl restart k3s
```

Then update SOPS with a **reusable** auth key for future installs.

## Lessons learned (Aug 2026)

1. First kexec without swap → OOM kill of `kexec`; Ubuntu stayed up. 2G swap fixed it.
2. Single-use Tailscale auth key → micro2 joined, micro1 autoconnect failed until
   interactive `tailscale up`.
3. Mac must not be the builder; s145 must be. Do not expect to copy flake edits
   back from s145 — edit on Mac, re-sync only if reinstalling.
4. `accept-flake-config` (user `nix.conf` or `profiles/base.nix`) avoids ignored
   flake substituters / from-source builds on Nix 2.34+.

## Related

- [../README.md](../README.md) — general tiny-node nixos-anywhere overview
- [../MAINTENANCE.md](../MAINTENANCE.md) — reinstall flags + tiny taint notes
- [RPI4-KEXEC-FIX.md](./RPI4-KEXEC-FIX.md) — different kexec story (Raspberry Pi)
