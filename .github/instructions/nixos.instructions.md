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
- Shared secrets: `tailscale/auth-key.yaml`, `k3s/token.yaml`

## Build Constraints

- All four Oracle micro nodes use deploy-rs `remoteBuild = false`; Mac-initiated deployments build their `x86_64-linux` closures through the hp348 distributed builder.
- `oracle-eu-arm1` and `oracle-in-arm1` (aarch64): `remoteBuild = true` — build on the hosts themselves.
- `s145`, `hp348`, and `rpi`: `remoteBuild = true`.
- The hp348 builder receives the Mac's local flake inputs through Nix; no repository checkout or synchronization is required on hp348.

## k3s Cluster

- Flannel traffic over `tailscale0` interface
- Workers tainted `tiny=true:NoSchedule` with `max-pods=10`
- Services conditionally enabled via `builtins.pathExists` on secrets files
