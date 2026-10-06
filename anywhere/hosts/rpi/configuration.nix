# hosts/rpi/configuration.nix — Raspberry Pi 4 k3s worker
#
# Host-specific settings only. Shared config comes from profiles where the
# Raspberry Pi boot path does not need special handling.
{ config, lib, pkgs, ... }:

let
  binaryCaches = import ../../lib/binary-caches.nix;
  hostSecretsFile = ../../secrets/rpi/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
  hasTailscaleSecretsFile = builtins.pathExists ../../secrets/tailscale/secrets.yaml;
in
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/tailscale.nix
    ../../profiles/k3s-agent.nix
    ../../profiles/pihole.nix
    ./disko-config.nix
    ./sops.nix
  ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # No unattended reboots: this Pi reports under-voltage (throttled=0x50000)
  # and boots off an SD card, so a reboot with nobody watching risks coming
  # back degraded or not at all. Auto-upgrade still runs and activates the new
  # generation — only the automatic reboot is withheld for a human.
  fleet.autoUpgrade.allowReboot = false;

  # Pi-only binary cache (keep out of shared profiles/base.nix), plus the
  # self-hosted ARM cache: rpi is aarch64 and would otherwise rebuild paths
  # that oracle-eu-arm1 has already built (sops-install-secrets above all).
  # Both scopes are needed — rpi carries the nixos-raspberrypi Cachix mirror,
  # arm carries the tailnet cache.
  nix.settings = {
    substituters = lib.mkAfter (
      binaryCaches.rpiNixSettings.substituters ++ binaryCaches.armNixSettings.substituters
    );
    trusted-public-keys = lib.mkAfter (
      binaryCaches.rpiNixSettings.trusted-public-keys
      ++ binaryCaches.armNixSettings.trusted-public-keys
    );
  };

  boot.loader.raspberry-pi = {
    enable = true;
    bootloader = "kernel";
  };

  boot.kernelParams = [
    "console=tty0"
    "console=ttyAMA0,115200n8"
    "cgroup_enable=cpuset"
    "cgroup_enable=memory"
    "cgroup_memory=1"
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

  # Tailscale — host identity + exit node + LAN subnet router.
  services.tailscale.useRoutingFeatures = "server";
  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=rpi"
    "--accept-dns=false"
  ];
  services.tailscale.extraSetFlags = [
    "--advertise-exit-node"
    "--advertise-routes=10.0.0.0/24"
  ];

  # Pi-hole — network-wide DNS filtering for the tailnet and the home LAN,
  # forwarding over DNS-over-TLS to Cloudflare. Gated on the host secrets file
  # because the dashboard password comes from it; without it the module would
  # reference a secret sops-nix cannot render.
  #
  # After the first deploy, set the tailnet to use it:
  #   Tailscale admin → DNS → Global nameserver 100.118.166.120
  #                         → "Override local DNS" on
  fleet.pihole = lib.mkIf hasHostSecretsFile {
    enable = true;
    tailscaleIP = "100.118.166.120";
    # end0 is down; the Pi is on wi-fi. Change this if it moves to ethernet.
    lanInterface = "wlan0";
    webPort = 8081;
  };

  # k3s — worker in the s145-rooted cluster.
  services.k3s.nodeName = "rpi";
  services.k3s.nodeIP = "100.118.166.120";
  systemd.services.k3s.serviceConfig.ExecCondition =
    "${pkgs.runtimeShell} -c 'grep -qw memory /sys/fs/cgroup/cgroup.controllers'";

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  system.stateVersion = "26.05";
}
