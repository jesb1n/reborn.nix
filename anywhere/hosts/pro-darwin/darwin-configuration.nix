# hosts/pro-darwin/darwin-configuration.nix — macOS system configuration
#
# Managed by nix-darwin + Determinate Nix. Rebuild with:
#   darwin-rebuild switch --flake .#pro-darwin
{ config, lib, pkgs, inputs, ... }:

{
  # Determinate Nix manages the Nix installation and daemon. Its nix-darwin
  # module (imported in flake.nix) sets nix.enable = false and writes
  # /etc/nix/nix.custom.conf from determinateNix.customSettings — never edit
  # that file by hand.
  determinateNix = {
    enable = true;
    customSettings = {
      # Lets `jesbin` use flake-declared caches without sudo prompts.
      trusted-users = [ "root" "jesbin" ];
    };
    # nix.gc asserts nix.enable, so store GC is delegated to determinate-nixd.
    determinateNixd.garbageCollector.strategy = "automatic";
  };

  # /etc/nix/nix.conf already reads this standard builders file.
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

  # --- Local VM networking (vagrant-qemu, ~/Projects/rancher-fleet/vm) ---
  # Homebrew QEMU cannot use vmnet.framework without root. socket_vmnet holds
  # the root vmnet membership as a daemon and QEMU connects to its unix socket
  # as a normal user (same approach as Lima/Colima). The flags are
  # authoritative for the subnet: static VM IPs in the Vagrantfile must sit in
  # 192.168.105.0/24 above the DHCP range (.101+).
  # First activation after adding this: the daemon starts before `brew bundle`
  # has installed the binary, so launchd retries it until the bundle finishes.
  # Socket and log live outside /opt/homebrew on purpose: launchd runs this as
  # root and brew refuses to install into a prefix with root-owned dirs.
  launchd.daemons.socket_vmnet = {
    serviceConfig = {
      Label = "io.github.lima-vm.socket_vmnet";
      ProgramArguments = [
        "/opt/homebrew/opt/socket_vmnet/bin/socket_vmnet"
        "--vmnet-gateway=192.168.105.1"
        "--vmnet-dhcp-end=192.168.105.100"
        "--socket-group=staff"
        "/var/run/socket_vmnet"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/socket_vmnet.log";
      StandardErrorPath = "/var/log/socket_vmnet.log";
    };
  };

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "slack"
    "1password-cli" # op, used by the github-mcp launcher (home.nix)
    "claude-code"
  ];

  networking = {
    hostName = "pro-darwin";
    computerName = "pro-darwin";
    localHostName = "pro-darwin";
    applicationFirewall = {
      enable = true;
      enableStealthMode = true;
    };
  };

  # Used by the iTerm2 dynamic profile and starship glyphs (home.nix).
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # Pinned Homebrew + immutable taps. autoMigrate adopts the existing
  # /opt/homebrew install (keeps installed packages).
  nix-homebrew = {
    enable = true;
    user = "jesbin";
    autoMigrate = true;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
  };

  # Prebuilt nix-index DB: command-not-found suggestions and `, <cmd>`.
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  # sops-nix for Mac-side secrets. Decrypts with the pro_darwin age key from
  # .sops.yaml; secrets activate only once secrets/pro-darwin/secrets.yaml exists.
  sops = {
    age.keyFile = "/Users/jesbin/.config/sops/age/keys.txt";
    defaultSopsFile = lib.mkIf (builtins.pathExists ../../secrets/pro-darwin/secrets.yaml)
      ../../secrets/pro-darwin/secrets.yaml;
  };

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
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
      _FXSortFoldersFirst = true;
      FXDefaultSearchScope = "SCcf"; # search the current folder
      FXEnableExtensionChangeWarning = false;
    };
    trackpad.Clicking = true; # tap to click
    screencapture = {
      location = "/Users/jesbin/Pictures/Screenshots"; # created in home.nix
      type = "png";
    };
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };
    # Clicking the wallpaper must not hide every window (Sonoma+ default).
    WindowManager.EnableStandardClickToShowDesktop = false;
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSDocumentSaveNewDocumentsToCloud = false;
    };
  };

  homebrew = {
    enable = true;
    onActivation.cleanup = "none";
    onActivation.autoUpdate = false;
    # Self-updating casks are upgraded by `brew upgrade` too (alias `brewup`).
    greedyCasks = true;
    taps = [ ];
    brews = [
      # Kubernetes MCP server for Claude Code; not in nixpkgs. Config is
      # ~/.config/kubernetes-mcp-server/config.toml (home.nix).
      "kubernetes-mcp-server"
      # Hypervisor for the vagrant-qemu provider (~/Projects/rancher-fleet/vm). The
      # plugin is tested against Homebrew's qemu layout (firmware under
      # $(brew --prefix)/share/qemu), so keep it beside the vagrant cask.
      "qemu"
      # Rootless vmnet for those VMs; run as a launchd daemon (see
      # launchd.daemons.socket_vmnet above), not `brew services`.
      "socket_vmnet"
    ];
    masApps = {
      "WireGuard" = 1451685025;
      "Bitwarden" = 1352778147;
    };
    casks = [
      "1password"
      "anydesk"
      "arc"
      "aside"
      "chatgpt"
      "claude"
      "cloudflare-warp"
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
      "spotify"
      "tabby"
      "tailscale-app"
      "transmission"
      # Local test VMs (Fleet/Rancher downstream, ~/Projects/rancher-fleet).
      # nixpkgs `vagrant` is not built for aarch64-darwin. The vagrant-qemu
      # plugin itself is mutable state: `vagrant plugin install vagrant-qemu`
      # (see that repo's Makefile), not managed here.
      "vagrant"
      "visual-studio-code"
      "vlc"
      # "warp" # TEMP: upstream cask sha256 is stale — warp.dev serves a different dmg for
      # 0.2026.09.30 (still true 2026-10-13). Warp.app is installed and self-updates;
      # re-enable once Homebrew/homebrew-cask bumps the cask.
      "whatsapp"
      "zen"
    ];
  };

  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true; # Touch ID inside tmux/screen
  };

  # nix-darwin ≥ 26.05 only runs three shell-code slots on activation:
  # `preActivation.text`, `extraActivation.text`, `postActivation.text`.
  # Custom names like `system.activationScripts.installFoo` are silently
  # NOT executed — they only produce dead file derivations. All custom
  # activation must go here. See:
  #   https://github.com/nix-darwin/nix-darwin/blob/main/modules/system/activation-scripts.nix
  system.activationScripts.postActivation.text = ''
    # Names for the test VMs. Deliberately NOT environment.etc.hosts: that
    # symlinks /etc/hosts into the store, and Apple's /usr/bin/ssh resolves via
    # Network.framework, which ignores a symlinked hosts file even though
    # ping/nc/curl honour it (nix-darwin/nix-darwin#1351). So install a real
    # file. Idempotent: copies only when content differs. Rollback leaves the
    # file in place; the first block is the stock macOS content.
    hostsSrc=${pkgs.writeText "hosts" ''
      ##
      # Host Database
      #
      # localhost is used to configure the loopback interface
      # when the system is booting.  Do not change this entry.
      ##
      127.0.0.1	localhost
      255.255.255.255	broadcasthost
      ::1             localhost

      # rancher-fleet test VMs (socket_vmnet, ~/Projects/rancher-fleet/vm/Vagrantfile)
      192.168.105.120 ubuntu2004.vm ubuntu2004
      192.168.105.122 ubuntu2204.vm ubuntu2204
      192.168.105.124 ubuntu2404.vm ubuntu2404
    ''}
    if ! cmp -s "$hostsSrc" /etc/hosts; then
      echo "updating /etc/hosts..." >&2
      rm -f /etc/hosts.before-nix-darwin
      install -m 0644 -o root -g wheel "$hostsSrc" /etc/hosts
    fi

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
