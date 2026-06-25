{ config, lib, pkgs, modulesPath, ... }:

let
  hostSecretsFile = ../../secrets/oracle-eu-micro1/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disko-config.nix
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

  networking.hostName = "oracle-eu-micro1";
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
  } // lib.optionalAttrs hasHostSecretsFile {
    authKeyFile = config.sops.secrets."tailscale-auth-key".path;

    extraUpFlags = [
      "--hostname=oracle-eu-micro1"
      "--accept-dns=false"
    ];
  };

  services.k3s = lib.mkIf hasClusterSecretsFile {
    enable = true;
    role = "agent";
    serverAddr = "https://100.84.230.4:6443";
    tokenFile = config.sops.secrets."k3s-token".path;
    nodeName = "oracle-eu-micro1";
    nodeIP = "100.96.237.114";
    nodeLabel = [
      "node-size=tiny"
    ];
    nodeTaint = [
      "tiny=true:NoSchedule"
    ];
    extraFlags = [
      "--flannel-iface=tailscale0"
      "--kubelet-arg=max-pods=10"
    ];
  };

  systemd.services.k3s = lib.mkIf hasClusterSecretsFile {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  nix.settings.trusted-users = [
    "root"
    "ubuntu"
  ];

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

  environment.systemPackages = with pkgs; [
    age
    curl
    git
    htop
    nano
    tmux
    vim
    wget
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
}
