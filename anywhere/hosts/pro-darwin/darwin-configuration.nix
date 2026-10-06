# hosts/pro-darwin/darwin-configuration.nix — macOS system configuration
#
# Managed by nix-darwin + Determinate Nix. Rebuild with:
#   darwin-rebuild switch --flake .#pro-darwin
{ config, lib, pkgs, ... }:

{
  # Determinate Nix manages the Nix installation, daemon, and settings.
  # /etc/nix/nix.conf already reads this standard builders file.
  nix.enable = false;
  # Two distributed builders, one per Linux architecture. Fields are
  # positional: URI, systems, ssh-key (unused — given in the URI), maxJobs,
  # speedFactor, supportedFeatures, mandatoryFeatures. Because the aarch64
  # line populates supportedFeatures, its trailing `-` is mandatory.
  #
  # maxJobs tracks core count (s145 4, oracle-eu-arm1 2). `kvm` is NOT claimed
  # for the Oracle A1.Flex — nested virt is not guaranteed there, and claiming
  # it would route kvm-requiring derivations to a host that cannot run them.
  environment.etc."nix/machines".text = ''
    ssh-ng://duck@s145?ssh-key=/etc/nix/fleet-builder-key x86_64-linux - 4 2
    ssh-ng://duck@oracle-eu-arm1?ssh-key=/etc/nix/fleet-builder-key aarch64-linux - 2 1 big-parallel,benchmark -
  '';
  # The nix-daemon runs as root: it does not read ~/.ssh/known_hosts, so
  # without these entries offload dies with "Host key verification failed".
  # programs.ssh.knownHosts writes the system-wide /etc/ssh/ssh_known_hosts,
  # which root does read.
  programs.ssh.knownHosts.s145 = {
    hostNames = [ "s145" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP4if+UQEgOtJ2/1hykw2vRtQ8vXj5qgZf5Tl+P7zSe/";
  };
  programs.ssh.knownHosts.oracle-eu-arm1 = {
    # Bare name resolves via Tailscale MagicDNS; the IP is listed so offload
    # still authenticates if MagicDNS is unavailable for root.
    hostNames = [ "oracle-eu-arm1" "100.84.230.4" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH5SbCYGZ0lxUm7tCJa8eJNtCcTPNZxJRNPFpxaoS37D";
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "1password"
    "cursor"
    "slack"
    "spotify"
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
    taps = [
      {
        name = "netbirdio/tap";
        trusted = true;
      }
    ];
    brews = [ "netbirdio/tap/netbird" ];
    masApps = {
      "WireGuard" = 1451685025;
      "Bitwarden" = 1352778147;
    };
    casks = [
      "anydesk"
      "arc"
      "chatgpt"
      "claude"
      "cloudflare-warp"
      "cursor-cli"
      "docker-desktop"
      "discord"
      "github-copilot-app"
      "handy"
      "hermes-desktop"
      "lens"
      "libreoffice"
      "loom"
      "maccy"
      "microsoft-teams"
      "netbirdio/tap/netbird-ui"
      "tabby"
      "tailscale-app"
      "visual-studio-code"
      "vlc"
      "warp"
      "whatsapp"
      "zen"
    ];
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  environment.systemPackages = [ pkgs._1password-gui ];

  # nix-darwin ≥ 26.05 only runs three shell-code slots on activation:
  # `preActivation.text`, `extraActivation.text`, `postActivation.text`.
  # Custom names like `system.activationScripts.installFoo` are silently
  # NOT executed — they only produce dead file derivations. All custom
  # activation must go here. See:
  #   https://github.com/nix-darwin/nix-darwin/blob/main/modules/system/activation-scripts.nix
  system.activationScripts.postActivation.text = ''
    # The Nix daemon cannot read keys from a user's home directory. Copy the
    # fleet-authorized key outside the Nix store for daemon-only use. The same
    # key is authorized for `duck` on every host via profiles/base.nix, so one
    # file serves both the s145 (x86_64) and oracle-eu-arm1 (aarch64) builders.
    # Must be 0600 root-owned: ssh refuses a group/world-readable private key,
    # and it must never go in the Nix store, which is world-readable.
    install -m 600 -o root -g wheel \
      /Users/jesbin/.ssh/id_ed25519 /etc/nix/fleet-builder-key

    # Superseded by fleet-builder-key above; remove the per-host copies so the
    # maintainer's private key does not linger in several places under /etc/nix.
    rm -f /etc/nix/s145-builder-key /etc/nix/hp348-builder-key \
          /etc/nix/nuc7i3-builder-key

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
