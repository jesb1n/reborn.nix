# TravelMate NixOS laptop

`travelmate` is an Acer TravelMate P249-M / TMP249-M-35V5 configured as a
standalone daily-use laptop. It uses the stable `nixos-26.05` input and is
intentionally excluded from fleet deploy-rs and reconciliation workflows.

## Hardware

- Intel Core i3-6006U with Intel HD Graphics 520
- 4 GB RAM with zram and a 4 GB disk swap partition
- Qualcomm Atheros QCA9377 Wi-Fi/Bluetooth
- Realtek RTL8111 Ethernet
- WDC WDS120G2G0A 120 GB SATA SSD
- UEFI boot with Secure Boot disabled

The destructive Disko target is pinned to:

```text
/dev/disk/by-id/ata-WDC_WDS120G2G0A-00JH30_181725806688
```

Always verify that link on the laptop before any reinstallation.

## Accounts

- `acer` is the interactive KDE Plasma user and uses password-authenticated
  local login and SSH.
- `duck` is hidden from SDDM, password-locked, and available only through the
  configured SSH keys for deployment and recovery.
- Root SSH login is disabled.

## Updating

The operator Mac is `aarch64-darwin`, while TravelMate is `x86_64-linux`.
Build on the laptop itself and explicitly disable other builders:

```bash
cd anywhere
out=$(
  nix build \
    --store 'ssh-ng://duck@travelmate' \
    --builders '' \
    --no-link \
    --print-out-paths \
    .#nixosConfigurations.travelmate.config.system.build.toplevel
)
ssh duck@travelmate \
  "sudo nix-env -p /nix/var/nix/profiles/system --set '$out' \
  && sudo '$out/bin/switch-to-configuration' switch"
```

Use the current IP instead of `travelmate` until local DNS or Tailscale name
resolution is available. Do not use `hp348` or another distributed builder for
this host. Updating the system profile before activation is required so the
new generation remains selected after reboot.

## Tailscale

Tailscale is installed but is not automatically authenticated. Onboard it
manually from a local terminal:

```bash
sudo tailscale up --hostname=travelmate
```

## Reinstallation

`nixos-anywhere` erases the entire SSD. It should only be used after confirming
an external backup and receiving explicit destructive-action approval. CentOS
7 required a legacy `setsid` compatibility wrapper and
`--kexec-extra-flags '--kexec-syscall'`; these are installation-only
workarounds and are not needed for routine updates.
