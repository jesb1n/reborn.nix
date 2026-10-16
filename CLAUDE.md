# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

`AGENTS.md` (imported above) is the primary rulebook: host table, profile
composition, IaC/SOPS/k3s quirks, validation checklist. This file only adds
what it does not cover. `anywhere/hosts/pro-darwin/AGENTS.md` and
`anywhere/hosts/air-darwin/AGENTS.md` still apply to those hosts and override
general NixOS conventions.

## Environment

- On macOS, Nix lives at `/nix/var/nix/profiles/default/bin` and is often
  **not on PATH in non-interactive shells**. Prefix Nix commands with
  `export PATH=/nix/var/nix/profiles/default/bin:$PATH` (the PostToolUse hook
  does the same). `deploy`, `flux`, `age`, `ssh-to-age`, `nixos-anywhere` and
  `disko` exist only inside `nix develop` in `anywhere/`; `tofu`, `sops`,
  `kubectl`, `oci` are Homebrew/system binaries.
- Evaluating the flake from a Mac prints "ignoring untrusted flake
  configuration setting" unless `--accept-flake-config` is passed (hosts set
  `accept-flake-config = true` in `profiles/base.nix`; CI sets it via
  `NIX_CONFIG`). Without it, builds skip the extra Cachix substituters.
- A `~/.codex/config.toml` exists on this machine; run `/import` to scan it
  for importable MCP servers/skills, then `/import --yes=<digest>` to apply.

## Checks and single-test equivalents (run from `anywhere/`)

`nix flake check` builds every `checks.<system>.*` attribute:

| Check | What it is | Run alone |
|---|---|---|
| `fleet-invariants` | Pure-eval assertions over `lib/fleet.nix`, `nixosConfigurations`, `deploy`, `ciDeploy` (x86_64-linux only) | `nix build .#checks.x86_64-linux.fleet-invariants` |
| `ssh-access` | NixOS VM test of `profiles/base.nix` + `server.nix` SSH hardening (needs an x86_64-linux builder) | `nix build .#checks.x86_64-linux.ssh-access` |
| `deploy-*` / `ci-deploy-*` | deploy-rs schema checks for `deploy.nodes` and `ciDeploy.nodes` | `nix build .#checks.x86_64-linux.deploy-schema` |

Other focused checks:

```bash
# Cache trust inventory self-checks (what nix-cache-keys.yml runs)
nix eval --json --impure --expr '(import ./lib/binary-caches.nix).valid'

# Release/reconcile shell helpers (what nixos-ci.yml runs)
bash -n scripts/fleet-release scripts/fleet-reconcile scripts/release.sh scripts/reconcile.sh
FLEET_RECONCILE_RETRY_BASE_SECONDS=0 FLEET_RECONCILE_RETRY_JITTER_SECONDS=0 bash tests/fleet-reconcile.sh

# Evaluate (not build) a Mac host — what .claude/hooks/nix-check.sh runs after edits
nix eval --raw .#darwinConfigurations.pro-darwin.system.drvPath
nix eval --raw .#darwinConfigurations.air-darwin.system.drvPath

# Fleet inventory as JSON (used by CI to order hosts)
nix eval --json .#fleet

# Kubernetes: render one app, dry-run one Flux registration
kubectl kustomize anywhere/k8s/<app>
kubectl apply --dry-run=client -f anywhere/clusters/s145/<app>.yaml
```

Formatting/lint: `pre-commit run --all-files`. nixfmt, statix and deadnix are
deliberately **not** enabled yet (tree would fail); do not add them without a
one-off cleanup commit.

## Architecture beyond AGENTS.md

### `lib/fleet.nix` is the single fleet inventory

Each of the nine hosts has `system`, `role`, `class`, `wave`, `order`,
`activationTimeout`, `confirmTimeout`, `remoteBuild`, `fastConnection`.
`flake.nix` derives `deploy.nodes`, `ciDeploy.nodes`, the `packages.<system>.<host>-toplevel`
/ `<host>-activation` release outputs and the public `#fleet` output from it;
`nixosConfigurations` are still listed by hand. `tests/fleet-invariants.nix`
asserts `nixosConfigurations == fleet + travelmate` and exactly nine fleet
hosts, so **adding a host touches** `lib/fleet.nix`, `flake.nix`
(`nixosConfigurations`), `hosts/<name>/`, `.sops.yaml`, and the invariant
count. `wave` (`x86-canary` = oracle-eu-micro2, `arm-canary` = oracle-eu-arm1,
`workers`, `control-plane` = s145) and `order` drive CI rollout order.

`travelmate` is a tenth `nixosConfiguration` outside the fleet: a Plasma
laptop on stable `nixpkgs`, no sops, no deploy-rs node, no k3s. Do not add it
to `fleet.nix`.

### Three rollout paths

1. **deploy-rs from a Mac** (`pro-darwin` or `air-darwin`; `deploy.nodes`, `remoteBuild` per `fleet.nix`) — the supervised path; see AGENTS.md.
2. **Pull-based auto-upgrade** (`profiles/auto-upgrade.nix`, `fleet.autoUpgrade.*`) — every host rebuilds itself from `main` nightly. `rpi` sets `allowReboot = false` (SD card, under-voltage).
3. **GitHub Actions release + reconcile** — `nixos-ci.yml` runs `scripts/fleet-release` on native x86/ARM runners to export one union closure per arch (`closure.nar.zst` + `manifest.json` + `SHA256SUMS`); `nixos-reconcile.yml` runs `scripts/fleet-reconcile`, which verifies/imports the archives, preflights each host over strict SSH, then activates via a generated deploy-rs definition (`ciDeploy`, `remoteBuild = false`, substitution disabled) canary → workers → control-plane with per-host rollback. `scripts/release.sh` and `scripts/reconcile.sh` are thin wrappers. **Both NixOS workflows are currently `workflow_dispatch`-only** (automatic triggers paused), even though `docs/CICD.md` still describes PR/push/schedule triggers.

### Binary cache trust (`lib/binary-caches.nix`)

Single reviewed inventory of substituters and public keys with scopes
`fleet`, `rpi`, `arm`, plus self-checks (`.valid`). `flake.nix`'s `nixConfig`
must stay a literal copy of `flakeNixConfig` — the `flake-literals-match-inventory`
check fails otherwise, so edit both together. The `arm` scope is the
self-hosted `nix-serve` on `oracle-eu-arm1` (`profiles/binary-cache.nix`,
`fleet.binaryCache.*`): tailnet-only, bound to the host's Tailscale IP, signing
key from sops. `oracle-in-arm1` is intentionally absent until its keypair
exists; a placeholder key breaks evaluation. `nix-cache-keys.yml` validates on
changes to these files and never rotates keys automatically.

### Optional `fleet.*` modules and other profiles

- `fleet.autoUpgrade` — enabled fleet-wide in `profiles/base.nix`.
- `fleet.binaryCache` — `oracle-eu-arm1` only, gated on its host secrets file.
- `fleet.pihole` (`profiles/pihole.nix`) — `rpi` only: Pi-hole FTL + stubby DNS-over-TLS, serving the tailnet (`100.118.166.120`) and the home LAN; config is immutable (`misc.readOnly`), password via sops `FTLCONF_*` env.
- `profiles/k3s-cni.nix` — imported by both k3s profiles; re-links k3s CNI binaries to the active generation on every start.
- `profiles/smartd.nix` — bare metal only (`s145`, `nuc7i3`).
- `s145` extras: `samba.nix`, `traefik.nix` (HelmChartConfig + Cloudflare ACME secret placed into k3s's manifests dir), `wifi-watchdog.nix`.
- **Hermes Agent was removed from all NixOS hosts** (commit `6b6690a`). Do not recreate `profiles/hermes-agent.nix`; the legacy `hermes/*` keys left in `secrets/oracle-eu-arm1/secrets.yaml` are undeclared. pro-darwin keeps its own Hermes install.

### Flux-managed apps (all of `anywhere/k8s/`)

Every directory under `k8s/` is Flux-managed via a registration in
`clusters/s145/<app>.yaml`; a new directory does nothing until registered, and
`kubectl apply` against Flux-owned resources is reverted by Flux. Dependency
graph: `infra` → {`cloudflared`, `garage`, `immich` → `immich-public-proxy`,
`litellm`, `monitoring`, `omniroute`, `vaultwarden`}. Reconcile `infra` first.
Node pinning exceptions to the "stateful → s145" rule: `monitoring`
(kube-prometheus-stack) → `oracle-in-arm1`; `litellm` → `oracle-eu-arm1`
(NodePort only); `omniroute` → `nuc7i3` (tailnet NodePorts).
`immich-public-proxy` is reached via the Cloudflare Tunnel (`cloudflared/`),
not Traefik.

Encrypted k8s manifests (`k8s/<app>/*secret.yaml`) use the `s145_cluster` age
recipient and need their **own** `creation_rules` entry in `anywhere/.sops.yaml`
with `encrypted_regex: "^(data|stringData)$"`; the pre-commit `sops-encrypted`
guard matches `anywhere/k8s/.*secret\.yaml`.

### Secret gating is per-file, so missing secrets silently disable features

`builtins.pathExists` on `secrets/<host>/secrets.yaml` toggles Tailscale auth,
k3s, the binary cache, Pi-hole and WiFi profiles. A host whose secrets file is
absent still evaluates and builds — it just comes up without those services.
Check for the file before concluding a service is "not configured".
