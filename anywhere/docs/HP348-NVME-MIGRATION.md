# hp348 USB HDD to NVMe migration

This runbook documents the completed 2026-08-11 migration of hp348's NixOS
root from its external Toshiba USB HDD to the internal GIGABYTE NVMe. The HDD
remains unchanged and bootable as offline rollback media.

The final system uses a 512 MiB ESP, 8 GiB swap partition, and the remaining
NVMe capacity for an ext4 root filesystem. The migration copied rather than
moved the source data and verified the copy before installing the boot loader.

## Safety boundaries

- Run each stage separately and inspect its gate before continuing.
- Never run the default nixos-anywhere phase set.
- Never include the `reboot` phase.
- Disko must target only the GIGABYTE NVMe by its stable ID.
- Keep physical access and the firmware boot menu available.
- Do not mount the source HDD read-write during migration.

Known devices at planning time:

| Purpose | Stable device | Size |
| --- | --- | --- |
| Source HDD | `/dev/disk/by-id/usb-TOSHIBA_MQ01ACF050_012345678999-0:0` | 465.8 GiB |
| Destination NVMe | `/dev/disk/by-id/nvme-GIGABYTE_GP-GSM2NE3256GNTD_SN210408933996` | 238.5 GiB |

Recorded source identifiers:

| Partition | UUID | PARTUUID |
| --- | --- | --- |
| ESP (`sda1`) | `E06D-AE38` | `28ea456a-5040-4661-b531-2eb404521f02` |
| Swap (`sda2`) | `66f9eeef-accd-48cc-a454-d3086c4c5182` | `64670510-f63b-4db5-9cc9-4842e06d11e6` |
| Root (`sda3`) | `9ba8b3f8-bc1e-4f86-858f-c0aa9202bd77` | `60afb0f5-5f70-4cfc-96c6-3bd0382ba59a` |

## Stage 1: prepare and validate

From `anywhere/`, verify generated filesystem references and the destructive
Disko script before building:

```bash
nix eval --json .#nixosConfigurations.hp348.config.fileSystems
nix eval --json \
  '.#nixosConfigurations.hp348.config.swapDevices' \
  --apply 'map (device: device.device)'
NIX_SSHOPTS='-o ControlMaster=no' nix build --no-link --print-out-paths \
  --eval-store auto --store 'ssh-ng://duck@hp348' \
  .#nixosConfigurations.hp348.config.system.build.diskoScript
```

Inspect the returned Disko script on hp348. It must contain the GIGABYTE stable
ID and generated partition labels `disk-nvme-ESP`, `disk-nvme-swap`, and
`disk-nvme-root`. It must not target the Toshiba ID or `/dev/sda`.

```bash
nix flake check
NIX_SSHOPTS='-o ControlMaster=no' nix build -L --no-link --print-out-paths \
  --eval-store auto --store 'ssh-ng://duck@hp348' \
  .#nixosConfigurations.hp348.config.system.build.toplevel
git diff --check
```

The flake has no formatter output, so formatting is reviewed with the repository
style and `git diff --check`. Record the final Disko and toplevel store paths.
Do not activate this configuration while hp348 still boots from the HDD.

## Stage 2: preflight and kexec

Confirm AC power, local console access, workload downtime, wired LAN SSH, and
disk identity:

```bash
ssh duck@192.168.165.142 hostname
ssh duck@192.168.165.142 \
  'lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL'
ssh duck@192.168.165.142 \
  "ls -l /dev/disk/by-id/ | grep -E 'nvme|usb'"
ssh duck@192.168.165.142 \
  'sudo find /mnt/nvme-data -mindepth 1 -maxdepth 2 -printf "%P\n"'
```

Only `lost+found` is expected on `nvme-data`. Unmount it, then enter the RAM
installer using only the kexec phase:

```bash
ssh duck@192.168.165.142 'sudo umount /mnt/nvme-data'
nix develop -c nixos-anywhere \
  --flake .#hp348 \
  --target-host duck@192.168.165.142 \
  --phases kexec
```

The connection drops while the running system, k3s, and Tailscale stop. The
installer restores the wired address and authorizes a temporary SSH key. It
then reconnects as `root@192.168.165.142`.

Gate:

```bash
ssh root@192.168.165.142 'hostname; findmnt /; test -d /sys/firmware/efi'
ssh root@192.168.165.142 \
  'lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL'
ssh root@192.168.165.142 \
  "ls -l /dev/disk/by-id/ | grep -E 'nvme|usb'"
```

Require hostname `nixos-installer`, a RAM-backed root, UEFI, and both exact
stable disk IDs. Stop if any identity differs.

## Stage 3: partition the NVMe

Run only Disko. Because kexec is omitted, nixos-anywhere expects the installer
SSH user to be root. The repository Disko declaration must contain only NVMe.

```bash
nix develop -c nixos-anywhere \
  --flake .#hp348 \
  --target-host root@192.168.165.142 \
  --phases disko \
  --disko-mode disko \
  --build-on remote
```

Gate:

```bash
ssh root@192.168.165.142 'lsblk -f; findmnt -R /mnt; swapon --show'
ssh root@192.168.165.142 \
  'sfdisk -d /dev/disk/by-id/nvme-GIGABYTE_GP-GSM2NE3256GNTD_SN210408933996'
ssh root@192.168.165.142 \
  'blkid /dev/disk/by-id/usb-TOSHIBA_MQ01ACF050_012345678999-0:0-part{1,2,3}'
```

Require NVMe root at `/mnt`, NVMe ESP at `/mnt/boot`, and all recorded HDD
UUIDs/PARTUUIDs unchanged.

## Stage 4: copy the offline HDD

Mount the HDD root read-only without journal replay:

```bash
ssh root@192.168.165.142 \
  'mkdir -p /mnt/source && mount -o ro,noload \
   /dev/disk/by-id/usb-TOSHIBA_MQ01ACF050_012345678999-0:0-part3 \
   /mnt/source'
```

Verify the read-only mount and critical persistent state. Do not use absolute
NixOS symlinks such as `/etc/hostname` for this check because they resolve
outside the offline mount.

```bash
ssh root@192.168.165.142 \
  'findmnt -no OPTIONS /mnt/source | grep -qw ro; \
   test -L /mnt/source/nix/var/nix/profiles/system; \
   test -s /mnt/source/var/lib/sops-nix/key.txt; \
   test -d /mnt/source/var/lib/rancher; \
   test -d /mnt/source/nix/var/nix/db'
```

Copy the single source filesystem. `-x` prevents traversal into historical
kubelet bind mounts; their underlying files are copied from their real paths.

```bash
ssh root@192.168.165.142 'rsync -aHAXSx --numeric-ids --delete \
  --exclude=/boot/*** \
  --exclude=/dev/*** \
  --exclude=/proc/*** \
  --exclude=/sys/*** \
  --exclude=/run/*** \
  --exclude=/tmp/*** \
  --exclude=/mnt/*** \
  --exclude=/media/*** \
  --exclude=/lost+found \
  /mnt/source/ /mnt/'
```

Gate:

```bash
ssh root@192.168.165.142 \
  'du -xsh /mnt/source /mnt; \
   test -d /mnt/nix/store; test -d /mnt/nix/var/nix/db; \
   test -d /mnt/var/lib/rancher; test -s /mnt/etc/machine-id; \
   test -d /mnt/etc/ssh; test -s /mnt/var/lib/sops-nix/key.txt'
ssh root@192.168.165.142 'rsync -aHAXSxnc --numeric-ids --delete \
  --exclude=/boot/*** --exclude=/dev/*** --exclude=/proc/*** \
  --exclude=/sys/*** --exclude=/run/*** --exclude=/tmp/*** \
  --exclude=/mnt/*** --exclude=/media/*** --exclude=/lost+found \
  /mnt/source/ /mnt/'
```

The checksum dry-run should produce no changes.

## Stage 5: install and inspect boot files

Install only the NixOS system; do not reboot automatically:

```bash
nix develop -c nixos-anywhere \
  --flake .#hp348 \
  --target-host root@192.168.165.142 \
  --phases install \
  --build-on remote
```

Gate:

```bash
ssh root@192.168.165.142 \
  'findmnt /mnt /mnt/boot; cat /mnt/etc/fstab; \
   find /mnt/boot/EFI -maxdepth 3 -type f -print; \
   find /mnt/boot/loader/entries -maxdepth 1 -type f -print -exec cat {} \;'
```

Require the NVMe root/ESP/swap labels in `fstab`, a fallback
`EFI/BOOT/BOOTX64.EFI`, systemd-boot, kernel/initrd files, and a NixOS loader
entry referencing the newly built toplevel.

Unmount and reboot only after a separate confirmation:

```bash
ssh root@192.168.165.142 \
  'umount /mnt/source && sync && umount /mnt/boot && umount /mnt && reboot'
```

Select the NVMe Linux Boot Manager or NVMe fallback entry in UEFI if needed.

## Stage 6: acceptance and rollback

After boot:

```bash
ssh duck@hp348 'findmnt /; findmnt /boot; swapon --show; lsblk -f'
ssh duck@hp348 'sudo bootctl status --no-pager'
ssh duck@hp348 \
  'systemctl --failed; systemctl is-active NetworkManager tailscaled k3s smartd'
ssh duck@s145 'sudo k3s kubectl get node hp348 -o wide'
ssh duck@s145 'sudo k3s kubectl get pods -A -o wide --field-selector spec.nodeName=hp348'
```

Require `/` and `/boot` on NVMe, the HDD unmounted, all services active, node
Ready, and local workloads healthy. Reboot once more and repeat the checks.

For rollback, power off and select the Toshiba USB/systemd-boot entry in UEFI.
The source disk remains unchanged. Do not repartition it until the NVMe has
completed the agreed soak period and the backup design has a restore test.

## Recorded outcome

The migration completed successfully on 2026-08-11:

- NVMe ESP: `/dev/nvme0n1p1`, UUID `F1A2-9274`.
- NVMe swap: `/dev/nvme0n1p2`, UUID `86a4894a-a25e-4c44-b0c1-1dff9e9008fe`.
- NVMe root: `/dev/nvme0n1p3`, UUID `d82253c7-3720-4581-bbe3-e1761d6d5a34`.
- The checksum-based rsync verification reported no differences.
- systemd-boot loads the NVMe installation through its fallback EFI path.
- hp348 rejoined k3s as Ready and all assigned workloads recovered.
- Redistributable firmware restored Realtek Wi-Fi/Bluetooth and Intel DMC
  firmware loading.
- The hp348-specific kernel command line retains `console=tty1` but removes the
  inherited OCI `ttyS0` console, eliminating the serial-getty restart loop.

Keep the Toshiba HDD disconnected during normal operation. When it is attached,
the firmware may prefer its fallback EFI loader and boot the rollback system
instead of the NVMe.
