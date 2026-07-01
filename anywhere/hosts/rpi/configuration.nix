{ config, lib, ... }:

let
  hostSecretsFile = ../../secrets/rpi/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMDHy9Gc18Osi7HFBiUMm+Da9JQ95cU1a7dsmyJCY5s1 jesbin@Duck.local"
  ];
in
{
  imports = [
    ./disko-config.nix
    ./sops.nix
  ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot.loader.raspberry-pi = {
    enable = true;
    bootloader = "kernel";
  };

  boot.kernelParams = [
    "console=tty0"
    "console=ttyAMA0,115200n8"
    "rootwait"
  ];

  boot.initrd.availableKernelModules = [
    "mmc_block"
    "sd_mod"
    "uas"
    "usb_storage"
    "usbhid"
    "xhci_pci"
  ];

  hardware.enableRedistributableFirmware = true;

  networking.hostName = "rpi";
  networking.useDHCP = lib.mkDefault true;
  networking.networkmanager.enable = true;
  networking.networkmanager.ensureProfiles = lib.mkMerge [
    {
      profiles.rpi-wired = {
        connection = {
          id = "rpi-wired";
          type = "ethernet";
          autoconnect = true;
          autoconnect-priority = 100;
        };

        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    }
    (lib.mkIf hasHostSecretsFile {
      environmentFiles = [
        config.sops.templates."rpi-network.env".path
      ];

      profiles.rpi-wifi = {
        connection = {
          id = "rpi-wifi";
          type = "wifi";
          interface-name = "wlan0";
          autoconnect = true;
        };

        wifi = {
          mode = "infrastructure";
          ssid = "$WIFI_SSID";
        };

        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };

        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    })
  ];

  networking.firewall = {
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [
      "tailscale0"
    ];
  };

  time.timeZone = "Asia/Kolkata";

  services.openssh.enable = true;
  services.openssh.openFirewall = true;

  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };

  services.journald.extraConfig = ''
    Storage=persistent
  '';

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--advertise-exit-node"
      "--advertise-routes=10.0.0.0/24"
    ];
  } // lib.optionalAttrs hasTailscaleSecretsFile {
    authKeyFile = config.sops.secrets."tailscale-auth-key".path;

    extraUpFlags = [
      "--hostname=rpi"
      "--accept-dns=false"
    ];
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  nix.settings.trusted-users = [
    "root"
    "duck"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
    randomizedDelaySec = "45min";
  };

  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
    randomizedDelaySec = "45min";
  };

  users.mutableUsers = false;

  users.users.root = {
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [ ];
  };

  users.users.duck = {
    isNormalUser = true;

    extraGroups = [
      "wheel"
      "networkmanager"
    ];

    hashedPassword = "!";

    openssh.authorizedKeys.keys = sshKeys;
  };

  security.sudo.wheelNeedsPassword = false;

  documentation.enable = false;
  programs.command-not-found.enable = false;
  environment.defaultPackages = [ ];

  system.stateVersion = "26.05";
}
