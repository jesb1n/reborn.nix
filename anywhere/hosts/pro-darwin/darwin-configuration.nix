# hosts/pro-darwin/darwin-configuration.nix — macOS system configuration
#
# Managed by nix-darwin + Determinate Nix. Rebuild with:
#   darwin-rebuild switch --flake .#pro-darwin
{ config, lib, pkgs, ... }:

{
  # Determinate Nix manages the Nix installation, daemon, and settings.
  # Custom Nix config goes in /etc/nix/nix.custom.conf, not here.
  nix.enable = false;

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "1password"
    "slack"
    "spotify"
    "vscode"
  ];

  documentation.enable = false;
  documentation.doc.enable = false;
  documentation.man.enable = false;

  system.stateVersion = 7;
  system.primaryUser = "jesbin";

  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;
      minimize-to-application = true;
      show-recents = false;
    };
    finder = {
      AppleShowAllExtensions = true;
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
    };
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticSpellingCorrectionEnabled = false;
    };
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    onActivation.autoUpdate = false;
    masApps = {
      "WireGuard" = 1451685025;
      "Bitwarden" = 1352778147;
    };
    casks = [
      "arc"
      "cloudflare-warp"
      "docker"
      "handy"
      "maccy"
      "tailscale-app"
      "warp"
      "whatsapp"
    ];
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  environment.systemPackages = [ pkgs.defaultbrowser pkgs._1password-gui ];

  # nix-darwin ≥ 26.05 only runs three shell-code slots on activation:
  # `preActivation.text`, `extraActivation.text`, `postActivation.text`.
  # Custom names like `system.activationScripts.installFoo` are silently
  # NOT executed — they only produce dead file derivations. All custom
  # activation must go here. See:
  #   https://github.com/nix-darwin/nix-darwin/blob/main/modules/system/activation-scripts.nix
  system.activationScripts.postActivation.text = ''
    # --- Default browser (Arc) --------------------------------------------
    defaultbrowser company.thebrowser.Browser || true

    # --- Maccy: 100 ms clipboard poll (default 500 ms) --------------------
    defaults write org.p0deje.Maccy clipboardCheckInterval -float 0.1

    # --- Blocked gcloud components ----------------------------------------
    # `google-cloud-sdk` from nixpkgs / Homebrew rejects
    # `gcloud components install` ("managed by an external package manager").
    # Workaround: pull Google's official component tarball and drop the
    # binary into /usr/local/bin. Bump URLs from:
    #   https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json
    # (look for `<component>-darwin-arm` -> `data.source`).
    install_gcloud_component() {
      local name="$1" url="$2" bin="/usr/local/bin/$1"
      if [ -x "$bin" ]; then
        echo "$name already installed"
        return 0
      fi
      echo "Installing $name..."
      local tmp
      tmp=$(mktemp -d)
      # trap in a subshell so it doesn't stomp postActivation's own traps
      (
        trap 'rm -rf "$tmp"' EXIT
        curl -fsSL "$url" -o "$tmp/pkg.tar.gz"
        tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"
        install -m 755 "$tmp/bin/$name" "$bin"
      )
      echo "Installed $name"
    }

    install_gcloud_component gke-gcloud-auth-plugin \
      "https://dl.google.com/dl/cloudsdk/channels/rapid/components/google-cloud-sdk-gke-gcloud-auth-plugin-darwin-arm-20260522195849.tar.gz"

    install_gcloud_component cloud-run-proxy \
      "https://dl.google.com/dl/cloudsdk/channels/rapid/components/google-cloud-sdk-cloud-run-proxy-darwin-arm-20260109121340.tar.gz"
  '';

  time.timeZone = "Asia/Calcutta";
}
