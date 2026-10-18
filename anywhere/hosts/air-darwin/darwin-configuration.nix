{ pkgs, inputs, ... }:

{
  determinateNix = {
    customSettings.trusted-users = [ "root" "duck" ];
    determinateNixd.garbageCollector.strategy = "automatic";
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "s145";
        sshUser = "duck";
        protocol = "ssh-ng";
        sshKey = "/etc/nix/fleet-builder-key";
        systems = [ "x86_64-linux" ];
        maxJobs = 4;
        speedFactor = 2;
      }
      {
        hostName = "oracle-eu-arm1";
        sshUser = "duck";
        protocol = "ssh-ng";
        sshKey = "/etc/nix/fleet-builder-key";
        systems = [ "aarch64-linux" ];
        maxJobs = 2;
        supportedFeatures = [ "big-parallel" "benchmark" ];
      }
    ];
  };

  programs.ssh.knownHosts = {
    s145 = {
      hostNames = [ "s145" "s145.panther-company.ts.net" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP4if+UQEgOtJ2/1hykw2vRtQ8vXj5qgZf5Tl+P7zSe/";
    };
    oracle-eu-arm1 = {
      hostNames = [ "oracle-eu-arm1" "100.84.230.4" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH5SbCYGZ0lxUm7tCJa8eJNtCcTPNZxJRNPFpxaoS37D";
    };
  };

  system.activationScripts.postActivation.text = ''
    install -m 600 -o root -g wheel /Users/duck/.ssh/id_ed25519 /etc/nix/fleet-builder-key
  '';

  networking = {
    hostName = "air-darwin";
    computerName = "air-darwin";
    localHostName = "air-darwin";
    applicationFirewall = {
      enable = true;
      enableStealthMode = true;
    };
  };

  time.timeZone = "Asia/Calcutta";

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    dock = {
      autohide = true;
      magnification = true;
      largesize = 57;
      tilesize = 44;
    };
    finder.FXPreferredViewStyle = "clmv";
    trackpad.Clicking = true;
    NSGlobalDomain.AppleInterfaceStyle = "Dark";
  };

  fonts.packages = [ pkgs.nerd-fonts.meslo-lg ];

  nix-homebrew = {
    enable = true;
    user = "duck";
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
  };

  homebrew = {
    enable = true;
    greedyCasks = true;
    casks = [
      "arc"
      "bitwarden"
      "claude-code"
      "maccy"
      "orbstack"
      "spotify"
      "tailscale-app"
      "visual-studio-code"
      "warp"
      "whatsapp"
    ];
  };

  documentation.enable = false;
  system.primaryUser = "duck";
  system.stateVersion = 7;
}
