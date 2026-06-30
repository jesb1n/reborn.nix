# hosts/s145/configuration.nix — standalone server (x86_64, WiFi)
#
# Host-specific settings only. Shared config comes from profiles.
{ config, lib, ... }:

let
  hostSecretsFile = ../../secrets/s145/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
  hasTailscaleSecretsFile = builtins.pathExists ../../secrets/tailscale/secrets.yaml;
in
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../profiles/tailscale.nix
    ./disko-config.nix
    ./sops.nix
  ];

  networking.hostName = "s145";

  # Boot — systemd-boot (override GRUB from server.nix)
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce true;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
  boot.kernelParams = lib.mkForce [ "systemd.gpt_auto=0" ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  # Realtek USB WiFi adapter firmware
  hardware.enableRedistributableFirmware = true;

  # WiFi via NetworkManager + SOPS
  networking.networkmanager.ensureProfiles = lib.mkMerge [
    {
      profiles.s145-wired = {
        connection = {
          id = "s145-wired";
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
        config.sops.templates."s145-network.env".path
      ];

      profiles.s145-wifi = {
        connection = {
          id = "s145-wifi";
          type = "wifi";
          interface-name = "wlp2s0f3u2";
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

  # Tailscale — host identity
  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=s145"
    "--accept-dns=false"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
}
