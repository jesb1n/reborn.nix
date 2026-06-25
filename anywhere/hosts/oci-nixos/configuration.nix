{ config, lib, ... }:

let
  hostSecretsFile = ../../secrets/oci-nixos/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
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
  networking.firewall.trustedInterfaces = [
    "tailscale0"
  ];

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

  services.k3s = lib.mkIf hasClusterSecretsFile {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets."k3s-token".path;
    nodeName = "oci-nixos";
    nodeIP = "100.84.230.4";
    disable = [
      "traefik"
    ];
    extraFlags = [
      "--flannel-iface=tailscale0"
    ];
  };

  systemd.services.k3s = lib.mkIf hasClusterSecretsFile {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJrNGTJviFWKFWJsvkD/0ajOflMSUKWIjP/N0Y39HY0S duck@s145"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  documentation.enable = false;
  programs.command-not-found.enable = false;
  environment.defaultPackages = [ ];
  environment.systemPackages = [ ];

  system.stateVersion = "26.05";
}
