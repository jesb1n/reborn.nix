---
applyTo: "anywhere/**"
description: "Use when editing NixOS configurations, flake inputs, host configs, disko layouts, or SOPS secrets under the anywhere/ directory"
---

# NixOS Configuration Guidelines

## Deployment Workflow

1. Edit host config under `anywhere/hosts/<hostname>/configuration.nix`
2. Validate: `nix flake check`
3. Deploy: `nix develop -c deploy .#<hostname>`

**Never use `nixos-anywhere`** for routine changes — it wipes and reinstalls the host.

## Host File Layout

Each host has: `configuration.nix` (main config), `disko-config.nix` (disk layout), `sops.nix` (secret declarations). The ARM host also has `hardware-configuration.nix`.

## Secrets

- Encrypted with SOPS + age under `anywhere/secrets/`
- Decrypted at activation into `/run/secrets/<name>`
- Host age keys live at `/var/lib/sops-nix/key.txt`
- Shared secrets: `secrets/tailscale/secrets.yaml`, `secrets/k3s/secrets.yaml`

## Build Constraints

- All four Oracle micro nodes use deploy-rs `remoteBuild = false`; Mac-initiated deployments build their `x86_64-linux` closures through the s145 distributed builder.
- Two distributed builders are registered on `pro-darwin`, one per Linux architecture: `s145` (x86_64-linux) and `oracle-eu-arm1` (aarch64-linux).
- `oracle-in-arm1` and `rpi` (aarch64): `remoteBuild = false` — built on `oracle-eu-arm1` rather than on the weak target hardware.
- `s145`, `oracle-eu-arm1`, and `nuc7i3`: `remoteBuild = true`. For the two builder hosts this is deliberate — building on the target *is* building on the builder, and flipping them to `false` would force a pointless closure round-trip. `tests/fleet-invariants.nix` enforces it.
- Both builders receive the Mac's local flake inputs through Nix; no repository checkout or synchronization is required on either.

## k3s Cluster

- Flannel traffic over `tailscale0` interface
- Workers tainted `tiny=true:NoSchedule` with `max-pods=10`
- Services conditionally enabled via `builtins.pathExists` on secrets files
