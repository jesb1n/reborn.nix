# pro-darwin — Agent Instructions

Host-specific rules for managing `pro-darwin` (Jesbin's MacBook Pro, Apple Silicon).
Read this file **before** making any changes to `darwin-configuration.nix` or `home.nix`.

## Host Facts

| Field | Value |
|-------|-------|
| Hostname | `pro-darwin` |
| Hardware | MacBook Pro, Apple Silicon (M-series) |
| System | `aarch64-darwin` |
| User | `jesbin` |
| Home | `/Users/jesbin` |
| Timezone | `Asia/Calcutta` (**not** `Asia/Kolkata` — macOS uses the older name) |
| Nix flavor | **Determinate Systems Nix** |
| macOS version target | Sonoma+ |
| Deploy command | `sudo darwin-rebuild switch --flake .#pro-darwin` |

## Repository Location

**Use `/Users/jesbin/Projects/reborn.nix/`** (remote `github.com/jesb1n/reborn.nix`) — this is the authoritative working copy.

The old `~/Documents/oracle-cloud-free-tier/` and iCloud paths are **deprecated**. Do not commit from them.

## Stack

- **nix-darwin** — system-level macOS configuration
- **home-manager** (as nix-darwin module) — user-level dotfiles/packages
- **Homebrew** (managed by nix-darwin) — only for packages that Nix cannot handle
- **home-manager `targets.darwin.copyApps`** — copies Nix `.app` bundles into `~/Applications/Home Manager Apps` so Spotlight/Launchpad index them (replaced mac-app-util; `linkApps` is disabled)
- **Determinate Nix** + **`determinate.darwinModules.default`** — provides the Nix daemon/store; the module manages Nix settings
- **nix-homebrew** — pins Homebrew itself and its taps as flake inputs
- **nix-index-database** — prebuilt index for command-not-found and `,` (comma)
- **sops-nix** (`darwinModules.sops`) — Mac-side secrets; inactive until `secrets/pro-darwin/secrets.yaml` exists and the age key is at `~/.config/sops/age/keys.txt`

## Critical Quirks (READ CAREFULLY)

### Determinate Nix

- The Determinate module sets `nix.enable = false` (forced). Do not set `nix.*` options — `nix.settings`, `nix.gc`, `nix.optimise` all assert `nix.enable`.
- Custom Nix settings go in **`determinateNix.customSettings`**, which writes `/etc/nix/nix.custom.conf`. Never edit that file by hand. Don't duplicate settings already in Determinate's `/etc/nix/nix.conf` (e.g. `extra-substituters = https://install.determinate.systems/`).
- `trusted-users = [ "root" "jesbin" ]` is set there.
- Store GC: `determinateNix.determinateNixd.garbageCollector.strategy = "automatic"` (writes `/etc/determinate/config.json`).
- The standard `/etc/nix/machines` remote-builder file is still managed with `environment.etc` (tests/fleet-invariants.nix mirrors it). `determinateNix.buildMachines` is unused.

### Homebrew — DANGER

- **`onActivation.cleanup = "none"`** — MUST stay `"none"`. Setting it to `"zap"` **destroys** any brew-installed package not listed in the Brewfile. This previously wiped the user's entire shell environment (uninstalled zsh plugins, tools, etc.). Do not change this without explicit user confirmation.
- **`onActivation.autoUpdate = false`** — skips `brew update` during rebuild for speed.
- **`greedyCasks = true`** — `brew upgrade` also upgrades self-updating casks. Run the `brewup` alias (`brew update && brew upgrade --greedy`) occasionally; rebuilds never upgrade.
- **nix-homebrew with `mutableTaps = false`**: taps come from flake inputs (`homebrew-core`, `homebrew-cask`, `homebrew-netbird`). `brew tap` does not work — to add a tap, add a `flake = false` input and a `nix-homebrew.taps` entry, and keep `homebrew.taps` in sync. Bump taps with `nix flake update homebrew-core homebrew-cask homebrew-netbird`.
- First migration of an existing `/opt/homebrew` fails with "An existing /opt/homebrew/Library/Taps is in the way" — move `Library/Taps` aside and rerun (done once on 2026-10-13; old copy at `Library/Taps.before-nix-homebrew`).

### Timezone

- Must be `"Asia/Calcutta"` — the macOS system timezone database uses the old name. `"Asia/Kolkata"` will silently fail or behave unexpectedly.

### Touch ID sudo

- `security.pam.services.sudo_local.touchIdAuth = true` — enables Touch ID for `sudo`. `reattach = true` adds `pam_reattach` so it also works inside tmux/screen.
- **Only works when the MacBook lid is open.** Physically doesn't work with lid closed (no fingerprint sensor exposed).
- Requires logout/reboot to take effect after first enabling.

### System version

- `system.stateVersion = 7` (nix-darwin state version)
- `system.primaryUser = "jesbin"` — REQUIRED for many modern nix-darwin options

### Documentation

- `documentation.enable = false` + `documentation.doc.enable = false` + `documentation.man.enable = false` — suppresses nix-darwin's manual docs generation to speed up rebuilds.

## Home-Manager Quirks

### `home.homeDirectory`

- **MUST use `lib.mkForce`**: `homeDirectory = lib.mkForce "/Users/jesbin";`
- Without `mkForce`, home-manager's `common.nix` default of `null` fights the assignment and evaluation fails.

### Git

- Use `programs.git.settings = {...}` — the newer attribute. `programs.git.extraConfig` is deprecated/renamed.
- User identity (`user.name`, `user.email`) is managed here — do NOT try `git config --global`; the file `~/.config/git/config` is a read-only symlink to the Nix store.

### Zsh

- Use `programs.zsh.initContent = ''...''` — NOT `initExtra` (deprecated in newer home-manager).

## Unfree Packages

`nixpkgs.config.allowUnfreePredicate` currently allows:
- `cursor` (Cursor editor)
- `slack` (Slack)
- `spotify` (Spotify)

If adding another unfree Nix package, extend this list. Do NOT use `allowUnfree = true` globally.
(Note: `vscode` was removed from this list because it is now installed via Homebrew cask — see "Must be Homebrew" table.)

## Package Placement — Nix vs Homebrew Decision Tree

**Prefer Nix.** Only fall back to Homebrew if one of the below applies.

### Must be Homebrew (do not attempt to move to Nix)

| Package | Reason |
|---------|--------|
| `1password` | The app self-updates and migrates its local data forward. The nixpkgs `_1password-gui` lives in the read-only store, cannot self-update, and lags upstream — once a newer build has touched the data, the Nix copy refuses to open it ("saved data appears to be newer than this version"). Use the official auto-updating cask. |
| `anydesk` | Remote-control app requiring preserved macOS signing plus Accessibility and Screen Recording permissions; use the current official Homebrew cask. |
| `arc` | Removed from nixpkgs (unmaintained). |
| `cloudflare-warp` | Needs macOS Network Extension entitlements — cannot ship via Nix. |
| `tailscale-app` | Needs macOS Network Extension entitlements. The app installs its own matching `tailscale` CLI at `/usr/local/bin/tailscale`; do NOT add nixpkgs `tailscale` to home.packages — a second CLI can drift out of version with the app's daemon. |
| `warp` | Marked broken in nixpkgs. |
| `maccy` | Not in nixpkgs. Preferences set manually (sandboxed app — see Maccy section). |
| `docker-desktop` | Requires macOS system extensions; Docker Desktop is not available in nixpkgs. (Cask was renamed from `docker`.) |
| `discord` | The Nix app was rejected by Gatekeeper when launched through mac-app-util's trampoline (pre-copyApps); use the official signed cask. |
| `microsoft-teams` | The Nix app was rejected by Gatekeeper when launched through mac-app-util's trampoline (pre-copyApps); use Microsoft's official signed cask. |
| `whatsapp` | macOS app not in nixpkgs. |
| `handy` | Not in nixpkgs. GUI speech-to-text app; needs macOS Accessibility, Microphone, and Input Monitoring entitlements (granted manually in System Settings after first launch). |
| `loom` | Not in nixpkgs. Proprietary screen-recording app; needs macOS Screen Recording, Microphone, and Camera entitlements (granted manually in System Settings after first launch). |
| `visual-studio-code` | nixpkgs `vscode` has recurring build failures (broken ripgrep path inside the upstream zip). Moved to Homebrew cask as a reliable fallback. |
| `chatgpt` | Official ChatGPT desktop app is not available as a supported nixpkgs package. |
| `claude` | Official Claude desktop app is distributed as a Homebrew cask and is not packaged as a supported nixpkgs macOS app here. |
| `github-copilot-app` | GitHub Copilot desktop app is not in nixpkgs. |
| `hermes-desktop` | Official Hermes Agent Desktop distribution is provided as a signed Homebrew cask; the upstream Nix flake packages the CLI, not the desktop app. |
| `lens` | Lens Kubernetes IDE is proprietary; not packaged usefully in nixpkgs for macOS. |
| `netbirdio/tap/netbird-ui` | NetBird's macOS UI installs privileged networking components and depends on the vendor's `netbirdio/tap/netbird` formula. Keep the tap, formula, and cask together. |
| `zen` | Zen Browser is not in nixpkgs for aarch64-darwin; the official Homebrew cask ships a universal macOS build. |
| `vlc` | nixpkgs `vlc` excludes `aarch64-darwin` from `meta.platforms` — not buildable here. |
| `libreoffice` | nixpkgs `libreoffice` excludes `aarch64-darwin` from `meta.platforms` — not buildable here. |
| `cursor-cli` | Cursor's CLI agent is distributed only as a Homebrew cask; nixpkgs `code-cursor` is the GUI editor, not this binary. |

### Mac App Store (masApps)

| App | MAS ID | Reason |
|-----|--------|--------|
| `WireGuard` | `1451685025` | GUI VPN client. `wireguard-tools` (CLI) was removed since the MAS app covers the use case. |
| `Bitwarden` | `1352778147` | Password manager. nixpkgs `bitwarden-desktop` uses EOL electron (insecure) — MAS version is safe and auto-updates. |

### Nix (home.packages)

CLI: `fd`, `ripgrep`, `yq-go`, `tree`, `gh`, `pre-commit`, `kubectl`, `kubectx`, `kubernetes-helm`, `opencode`, `cloudflared`, `k9s`, `google-cloud-sdk`, `opentofu`, `awscli2`, `oci-cli`, `sops`, `ffmpeg`, `k6`
GUI: `code-cursor`, `firefox`, `iterm2`, `slack`, `spotify`

### Homebrew tap bundles

- NetBird requires all three declarations: trusted tap `netbirdio/tap`, formula `netbirdio/tap/netbird`, and cask `netbirdio/tap/netbird-ui`.

### Special case: blocked `gcloud components` (gke-gcloud-auth-plugin, cloud-run-proxy)

- `google-cloud-sdk` from nixpkgs does NOT bundle certain components (`gke-gcloud-auth-plugin`, `cloud-run-proxy`, ...).
- `gcloud components install <name>` is **blocked** on both:
  - Nix `google-cloud-sdk` (error: "managed by an external package manager")
  - Homebrew `gcloud-cli` cask (same error)
- **Current solution**: an `install_gcloud_component <name> <url>` shell function inside `system.activationScripts.postActivation.text` (see below section on activation scripts) downloads Google's official component tarball and installs the binary to `/usr/local/bin/<name>`. Idempotent — skips if the binary already exists.
- **When updating a URL**: get the current version from `https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json` — look for the `<component>-darwin-arm` component's `data.source` field (e.g. `gke-gcloud-auth-plugin-darwin-arm`, `cloud-run-proxy-darwin-arm`). Update the URL passed to `install_gcloud_component` in `darwin-configuration.nix`.
- **Adding another blocked component**: add one more `install_gcloud_component <name> <url>` call inside `postActivation.text`. Do NOT try `gcloud components install`, and do NOT add a new top-level `system.activationScripts.installFoo` — those DO NOT RUN (see next section).

### CRITICAL: `system.activationScripts.<custom-name>` DOES NOT EXECUTE

nix-darwin (≥ 26.05) only runs three shell-code slots on activation:

- `system.activationScripts.preActivation.text`
- `system.activationScripts.extraActivation.text`
- `system.activationScripts.postActivation.text`

Any other name (e.g. `system.activationScripts.installGkePlugin.text`, `.setBrowser.text`, `.configureMaccy.text`) is **silently ignored as far as execution is concerned** — it only produces a dead file derivation. This is different from NixOS, and different from older nix-darwin. The `postUserActivation`/`preUserActivation` slots have also been removed (activation is now always root; assertions will fire if you use them).

**Rule**: put all custom activation shell code inside `system.activationScripts.postActivation.text`. `pro-darwin`'s single `postActivation` block contains: the fleet builder key copy, and the `install_gcloud_component` helper + its calls. Activation runs as root, so never use a bare `defaults write` here for user preferences — it writes root's domain. Use `system.defaults.CustomUserPreferences` for non-sandboxed apps.

Verify a change actually runs by looking for its output in `sudo darwin-rebuild switch --flake .#pro-darwin` output, or by grepping the built activate script: `grep -c '<marker>' /run/current-system/activate`.

## Default Browser

- Not managed by Nix. Set Arc (or another browser) manually in **System Settings → Desktop & Dock → Default web browser**.
- Do **not** reintroduce `defaultbrowser` activation or PlistBuddy hacks on `com.apple.launchservices.secure.plist` — both caused fragile/broken behavior.

## Maccy (Clipboard Manager)

- Installed via Homebrew cask `maccy`.
- **Preferences are NOT managed by Nix.** Maccy is sandboxed, so its domain lives in `~/Library/Containers/org.p0deje.Maccy/`. macOS blocks other processes from writing there, so `system.defaults.CustomUserPreferences` aborts activation ("Could not write domain …"), and a `defaults write` in `postActivation` runs as root and writes root's domain instead. Set it once by hand from a terminal and allow the "access data from other apps" prompt:
  `defaults write org.p0deje.Maccy clipboardCheckInterval -float 0.1`
- Current settings: `clipboardCheckInterval = 0.1` (100ms; default is 500ms).
- Other useful keys from README: `ignoreEvents`, `showFooter`. See https://github.com/p0deje/Maccy for full list.

## iTerm2 Dynamic Profile

- Dracula theme + JetBrainsMonoNerdFont, defined in `home.nix` via `programs.iterm2.dynamicProfiles`.
- Requires iTerm2 to be installed (currently via Nix `pkgs.iterm2`).
- The font comes from `fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ]` in `darwin-configuration.nix` (installed to `/Library/Fonts/Nix Fonts`).

## Shell Aliases and Functions

Defined in `home.nix` under `programs.zsh`:
- Aliases: `gs`, `gd`, `gl`, `k` (kubectl), `kx` (kubectx)
- Functions (via `initContent`):
  - `gx` — fzf picker to **permanently** switch gcloud project
  - `tgx` — fzf picker to **temporarily** switch gcloud project (session-only via `CLOUDSDK_CORE_PROJECT`)

When adding new aliases or functions, keep them in the same section for discoverability.

## pre-commit (global hook template)

- `pre-commit` is in `home.packages`; git's `init.templateDir = ~/.git-template` (in `programs.git.settings`) gives every new clone/`git init` the hook.
- The hook is written by `home.activation.preCommitTemplate` as a **real file** (`install -m 0755`), calling `/etc/profiles/per-user/jesbin/bin/pre-commit`. Do not convert it to `home.file` or reference a `/nix/store` path: git copies template files — symlinks included — into each repo, so those would dangle after GC.
- Repos without `.pre-commit-config.yaml` are skipped (`--skip-on-missing-config`). For existing repos run `git init` (safe) or `pre-commit install` once.

## Networking, firewall, SSH

- `networking.hostName`/`computerName`/`localHostName` = `pro-darwin`.
- `networking.applicationFirewall` enabled with stealth mode.
- SSH uses the 1Password agent: `programs.ssh.settings."*".IdentityAgent` in `home.nix` (enable it in 1Password → Settings → Developer). `~/.ssh/config` is Home Manager-managed. The nix-daemon's builder offload uses `/etc/nix/fleet-builder-key` as root and is unaffected.

## Deploy Workflow

```bash
cd /Users/jesbin/Projects/reborn.nix/anywhere

# Validate (always run before rebuild)
nix flake check

# Optional: dry build to catch errors without activating
sudo darwin-rebuild build --flake .#pro-darwin

# Activate
sudo darwin-rebuild switch --flake .#pro-darwin
```

**New Nix files must be `git add`-ed before `nix flake check` or `darwin-rebuild`.** Flakes only see tracked/staged files; untracked files cause evaluation errors.

## Do NOT

- **Do not** set `homebrew.onActivation.cleanup = "zap"`. It will destroy the user's shell setup.
- **Do not** re-enable `nix.enable` or set `nix.*` options — Determinate Nix owns the daemon; use `determinateNix.*`.
- **Do not** re-add mac-app-util or enable `targets.darwin.linkApps` — `copyApps` and `linkApps` conflict.
- **Do not** run `brew tap` / set `mutableTaps = true` to add a tap — add a flake input instead.
- **Do not** try to install blocked gcloud components (`gke-gcloud-auth-plugin`, `cloud-run-proxy`, ...) via `gcloud components install` — it is blocked by both Nix and Homebrew SDK installations. Add another `install_gcloud_component` call inside `postActivation.text` instead.
- **Do not** add `system.activationScripts.<customName>.text = "..."` expecting it to run — only `preActivation` / `extraActivation` / `postActivation` execute; custom names are silently ignored. Merge new activation code into `postActivation.text`.
- **Do not** reintroduce `defaultbrowser` activation or PlistBuddy default-browser hacks.
- **Do not** move `1password`, `anydesk`, `arc`, `warp`, `cloudflare-warp`, `tailscale-app`, `maccy`, `docker-desktop`, `discord`, `microsoft-teams`, `whatsapp`, `handy`, `hermes-desktop`, `loom`, `visual-studio-code`, `github-copilot-app`, `lens`, or `zen` from Homebrew to Nix — they cannot work as Nix packages (see reasons above).
- **Do not** reinstall `opencode`, `ripgrep`, `ffmpeg`, or `k6` via Homebrew — they are managed by Nix in `home.packages`. Brew copies shadow Nix because `sessionPath` prepends `/opt/homebrew/bin`.
- **Do not** add `nodejs` to `home.packages` — `~/.local/bin/node` (Hermes's bundled node) comes first on PATH and shadows it.
- **Do not** add `wireguard-tools` back to `home.packages` — WireGuard is managed via the Mac App Store GUI app.
- **Do not** hardcode `user.name`/`user.email` via `git config --global` — use `programs.git.settings` in `home.nix`.
- **Do not** commit from the old `~/Documents/oracle-cloud-free-tier/` or iCloud paths — use `/Users/jesbin/Projects/reborn.nix/`.
- **Do not** commit `anywhere/result` (Nix build symlink) — should be gitignored.

## Files in this folder

- `darwin-configuration.nix` — nix-darwin system config (Homebrew, defaults, activation scripts, system packages)
- `home.nix` — home-manager user config (shell, git, tools, iTerm2 profile, Nix-installed packages)
- `AGENTS.md` — this file
