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

**Use `/Users/jesbin/Documents/oracle-cloud-free-tier/`** — this is the authoritative working copy.

The iCloud path (`/Users/jesbin/Library/Mobile Documents/com~apple~CloudDocs/Documents/oracle-cloud-free-tier/`) exists but is **deprecated**. Do not commit from it. If you find yourself there, rsync to the local path first.

## Stack

- **nix-darwin** — system-level macOS configuration
- **home-manager** (as nix-darwin module) — user-level dotfiles/packages
- **Homebrew** (managed by nix-darwin) — only for packages that Nix cannot handle
- **mac-app-util** — creates Spotlight/Launchpad trampolines for Nix-installed `.app` bundles
- **Determinate Nix** — provides the Nix daemon and store

## Critical Quirks (READ CAREFULLY)

### Determinate Nix

- **`nix.enable = false`** is REQUIRED in `darwin-configuration.nix`. Determinate manages nixd itself; letting nix-darwin manage it will conflict.
- Custom Nix settings go in `/etc/nix/nix.custom.conf`, NOT via `nix.settings` in the flake.

### Homebrew — DANGER

- **`onActivation.cleanup = "none"`** — MUST stay `"none"`. Setting it to `"zap"` **destroys** any brew-installed package not listed in the Brewfile. This previously wiped the user's entire shell environment (uninstalled zsh plugins, tools, etc.). Do not change this without explicit user confirmation.
- **`onActivation.autoUpdate = false`** — skips `brew update` during rebuild for speed.

### Timezone

- Must be `"Asia/Calcutta"` — the macOS system timezone database uses the old name. `"Asia/Kolkata"` will silently fail or behave unexpectedly.

### Touch ID sudo

- `security.pam.services.sudo_local.touchIdAuth = true` — enables Touch ID for `sudo`.
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
- `1password` (1Password GUI)
- `slack` (Slack)
- `spotify` (Spotify)
- `vscode` (VS Code)

If adding another unfree Nix package, extend this list. Do NOT use `allowUnfree = true` globally.

## Package Placement — Nix vs Homebrew Decision Tree

**Prefer Nix.** Only fall back to Homebrew if one of the below applies.

### Must be Homebrew (do not attempt to move to Nix)

| Package | Reason |
|---------|--------|
| `arc` | Removed from nixpkgs (unmaintained). |
| `cloudflare-warp` | Needs macOS Network Extension entitlements — cannot ship via Nix. |
| `tailscale-app` | Needs macOS Network Extension entitlements. (The `tailscale` CLI IS installed via Nix in home.packages — separate from the GUI app.) |
| `warp` | Marked broken in nixpkgs. |
| `maccy` | Not in nixpkgs. Configured via `defaults write org.p0deje.Maccy ...`. |
| `docker` | Requires macOS system extensions; Docker Desktop is not available in nixpkgs. |
| `whatsapp` | macOS app not in nixpkgs. |
| `handy` | Not in nixpkgs. GUI speech-to-text app; needs macOS Accessibility, Microphone, and Input Monitoring entitlements (granted manually in System Settings after first launch). |

### Mac App Store (masApps)

| App | MAS ID | Reason |
|-----|--------|--------|
| `WireGuard` | `1451685025` | GUI VPN client. `wireguard-tools` (CLI) was removed since the MAS app covers the use case. |
| `Bitwarden` | `1352778147` | Password manager. nixpkgs `bitwarden-desktop` uses EOL electron (insecure) — MAS version is safe and auto-updates. |

### Nix (system — environment.systemPackages)

- `defaultbrowser` — sets the default browser via activation script
- `_1password-gui` — 1Password GUI app (system-installed for proper macOS integration)

### Nix (home.packages)

CLI: `fd`, `ripgrep`, `yq-go`, `tree`, `gh`, `kubectl`, `kubectx`, `kubernetes-helm`, `opencode`, `tailscale` (CLI), `k9s`, `google-cloud-sdk`, `opentofu`, `awscli2`
GUI: `firefox`, `iterm2`, `vscode`, `slack`, `spotify`

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

**Rule**: put all custom activation shell code inside `system.activationScripts.postActivation.text`. `pro-darwin`'s single `postActivation` block contains: `defaultbrowser` invocation, Maccy `defaults write`, and the `install_gcloud_component` helper + its calls.

Verify a change actually runs by looking for its output in `sudo darwin-rebuild switch --flake .#pro-darwin` output, or by grepping the built activate script: `grep -c '<marker>' /run/current-system/activate`.

## Default Browser

- Set to Arc (`company.thebrowser.Browser`) via [`defaultbrowser`](https://github.com/kerma/defaultbrowser) CLI tool.
- `defaultbrowser` is installed via `environment.systemPackages = [ pkgs.defaultbrowser ];`.
- The activation script runs `defaultbrowser company.thebrowser.Browser` on every rebuild — idempotent (prints "already set" if unchanged).
- **Do NOT go back to PlistBuddy hacks on `com.apple.launchservices.secure.plist`** — the array indexing is fragile and previous attempts left the plist in inconsistent states.

## Maccy (Clipboard Manager)

- Installed via Homebrew cask `maccy`.
- Configured via activation script using `defaults write org.p0deje.Maccy ...`.
- Current settings: `clipboardCheckInterval = 0.1` (100ms; default is 500ms).
- Other useful keys from README: `ignoreEvents`, `showFooter`. See https://github.com/p0deje/Maccy for full list.

## iTerm2 Dynamic Profile

- Dracula theme + JetBrainsMonoNerdFont, defined in `home.nix` via `programs.iterm2.dynamicProfiles`.
- Requires iTerm2 to be installed (currently via Nix `pkgs.iterm2`).

## Shell Aliases and Functions

Defined in `home.nix` under `programs.zsh`:
- Aliases: `gs`, `gd`, `gl`, `k` (kubectl), `kx` (kubectx)
- Functions (via `initContent`):
  - `gx` — fzf picker to **permanently** switch gcloud project
  - `tgx` — fzf picker to **temporarily** switch gcloud project (session-only via `CLOUDSDK_CORE_PROJECT`)

When adding new aliases or functions, keep them in the same section for discoverability.

## Deploy Workflow

```bash
cd /Users/jesbin/Documents/oracle-cloud-free-tier/anywhere

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
- **Do not** re-enable `nix.enable` — Determinate Nix owns the daemon.
- **Do not** try to install blocked gcloud components (`gke-gcloud-auth-plugin`, `cloud-run-proxy`, ...) via `gcloud components install` — it is blocked by both Nix and Homebrew SDK installations. Add another `install_gcloud_component` call inside `postActivation.text` instead.
- **Do not** add `system.activationScripts.<customName>.text = "..."` expecting it to run — only `preActivation` / `extraActivation` / `postActivation` execute; custom names are silently ignored. Merge new activation code into `postActivation.text`.
- **Do not** replace the `defaultbrowser` activation with PlistBuddy hacks.
- **Do not** move `arc`, `warp`, `cloudflare-warp`, `tailscale-app`, `maccy`, `docker`, or `whatsapp` from Homebrew to Nix — they cannot work as Nix packages (see reasons above).
- **Do not** add `wireguard-tools` back to `home.packages` — WireGuard is managed via the Mac App Store GUI app.
- **Do not** hardcode `user.name`/`user.email` via `git config --global` — use `programs.git.settings` in `home.nix`.
- **Do not** commit from the iCloud path — use `/Users/jesbin/Documents/oracle-cloud-free-tier/`.
- **Do not** commit `anywhere/result` (Nix build symlink) — should be gitignored.

## Files in this folder

- `darwin-configuration.nix` — nix-darwin system config (Homebrew, defaults, activation scripts, system packages)
- `home.nix` — home-manager user config (shell, git, tools, iTerm2 profile, Nix-installed packages)
- `AGENTS.md` — this file
