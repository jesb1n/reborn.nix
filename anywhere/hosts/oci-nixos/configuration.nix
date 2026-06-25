{ config, lib, pkgs, ... }:

let
  hostSecretsFile = ../../secrets/oci-nixos/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
in
{
  imports = [
    ./hardware-configuration.nix
    ./sops.nix
  ];

  boot.loader.systemd-boot.enable = false;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    efiInstallAsRemovable = true;
  };

  boot.loader.efi.canTouchEfiVariables = false;

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty1"
  ];

  networking.hostName = "oci-nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Kolkata";

  services.openssh.enable = true;
  services.openssh.openFirewall = true;

  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
  } // lib.optionalAttrs hasHostSecretsFile {
    authKeyFile = config.sops.secrets."tailscale-auth-key".path;

    extraUpFlags = [
      "--advertise-exit-node"
    ];
  };

  users.mutableUsers = false;

  users.users.root = {
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [ ];
  };

  users.users.ubuntu = {
    isNormalUser = true;

    extraGroups = [
      "wheel"
      "networkmanager"
    ];

    hashedPassword = "!";

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMDHy9Gc18Osi7HFBiUMm+Da9JQ95cU1a7dsmyJCY5s1 jesbin@Duck.local"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    nano
    vim
    curl
    wget
    git
    htop
    tmux
    age
    parted
    gptfdisk
  ];

  system.stateVersion = "26.05";
}
