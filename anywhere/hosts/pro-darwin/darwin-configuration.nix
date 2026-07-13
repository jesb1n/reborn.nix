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
    casks = [
      "arc"
      "cloudflare-warp"
      "maccy"
      "tailscale-app"
      "warp"
      "whatsapp"
    ];
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  environment.systemPackages = [ pkgs.defaultbrowser ];

  system.activationScripts.setBrowser.text = ''
    defaultbrowser company.thebrowser.Browser
  '';

  system.activationScripts.installGkePlugin.text = ''
    PLUGIN_URL="https://dl.google.com/dl/cloudsdk/channels/rapid/components/google-cloud-sdk-gke-gcloud-auth-plugin-darwin-arm-20260522195849.tar.gz"
    PLUGIN_BIN="/usr/local/bin/gke-gcloud-auth-plugin"

    # Skip if already installed
    if [ -x "$PLUGIN_BIN" ]; then
      echo "gke-gcloud-auth-plugin already installed"
    else
      TMPDIR=$(mktemp -d)
      trap 'rm -rf "$TMPDIR"' EXIT

      curl -sL "$PLUGIN_URL" -o "$TMPDIR/plugin.tar.gz"
      tar -xzf "$TMPDIR/plugin.tar.gz" -C "$TMPDIR"
      install -m 755 "$TMPDIR/bin/gke-gcloud-auth-plugin" "$PLUGIN_BIN"
      echo "Installed gke-gcloud-auth-plugin"
    fi
  '';

  system.activationScripts.configureMaccy.text = ''
    # Faster clipboard check (100ms vs default 500ms)
    defaults write org.p0deje.Maccy clipboardCheckInterval -float 0.1
  '';

  time.timeZone = "Asia/Calcutta";
}
