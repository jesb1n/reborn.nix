# Raspberry Pi minimal NixOS host

This host is wired into the flake as:

```text
.#rpi
```

The Raspberry Pi board support is provided by
`github:nvmd/nixos-raspberrypi`, using the `raspberry-pi-4.base` module with
the Raspberry Pi U-Boot + extlinux boot path.

Current observed addresses before reinstall:

```text
LAN:       10.0.0.173
Tailscale: 100.79.146.32
Wi-Fi:     wlan0
```

The deploy target in `flake.nix` uses `ubuntu@100.79.146.32`.

## Before running nixos-anywhere

This Pi is Wi-Fi-only, so verify boot and network details first:

```bash
ssh ubuntu@100.79.146.32 'uname -m; cat /proc/device-tree/model; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS; findmnt / /boot /boot/firmware'
```

Confirm:

- `uname -m` is `aarch64`;
- the install disk in `disko-config.nix` matches the real boot disk;
- you have a recovery path if Wi-Fi does not come back after reinstall.

The default Disko target is `/dev/mmcblk0`, which is the usual SD-card disk.
Change it before install if the Pi boots from USB storage.

The FAT firmware partition is mounted at `/boot/firmware`. This is intentional:
`nixos-raspberrypi` manages Raspberry Pi firmware there, while U-Boot loads
the extlinux config from `/boot` on the NixOS root filesystem.

## Secrets

Create the host age key locally, then pass it with `--extra-files` during install:

```bash
mkdir -p /tmp/rpi-extra/var/lib/sops-nix
age-keygen -o /tmp/rpi-extra/var/lib/sops-nix/key.txt
chmod 600 /tmp/rpi-extra/var/lib/sops-nix/key.txt
age-keygen -y /tmp/rpi-extra/var/lib/sops-nix/key.txt
```

Add the printed public key to `.sops.yaml` as `rpi`, then add a
`secrets/rpi/.*` creation rule.

Expected host secret shape:

```yaml
wifi-ssid: "your-wifi-ssid"
wifi-psk: "your-wifi-password"
```

The shared Tailscale key lives in `secrets/tailscale/secrets.yaml`.

## Install sketch

> **Note:** The kexec packages (`packages/`) were removed from the flake.
> To restore them, see commit `8839460` (`Add Wi-Fi Tailscale kexec image`).

From `anywhere/`:

```bash
nix build .#packages.aarch64-linux.kexec-wifi-tailscale-image

nix develop -c nixos-anywhere \
  --flake .#rpi \
  --kexec ./result \
  --phases kexec \
  ubuntu@100.79.146.32
```

After the kexec-only test, wait for the Pi to return on Tailscale, then verify:

```bash
ssh root@100.79.146.32
```

If this works, either reboot back to Debian/Raspberry Pi OS and run the full
install from there, or continue from the RAM installer. The full install is
destructive and will wipe `/dev/mmcblk0`.

From Debian/Raspberry Pi OS:

```bash
nix develop -c nixos-anywhere \
  --flake .#rpi \
  --kexec ./result \
  --extra-files /tmp/rpi-extra \
  ubuntu@100.79.146.32
```

From the RAM installer after the kexec-only test:

```bash
nix develop -c nixos-anywhere \
  --flake .#rpi \
  --phases disko,install,reboot \
  --extra-files /tmp/rpi-extra \
  root@100.79.146.32
```

For a Wi-Fi-only install, prefer using Tailscale for the SSH target. If the Pi
does not keep a usable Wi-Fi profile across the install environment, use
temporary USB Ethernet or install from a prepared NixOS SD image first, then
manage it with this flake.
