# hosts/hp348/configuration.nix — standalone server (x86_64, USB-booted laptop)
#
# Host-specific settings only. Shared config comes from profiles.
{ lib, ... }:

let
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
in
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../profiles/tailscale.nix
    ../../profiles/k3s-agent.nix
    ./disko-config.nix
    ./sops.nix
  ];

  networking.hostName = "hp348";

  # Boot — systemd-boot (override GRUB from server.nix)
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce true;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;

  # Root disk is on USB — include USB storage drivers in initrd
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ehci_pci"
    "usb_storage"
    "uas"
    "usbhid"
  ];

  # Tailscale — host identity
  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=hp348"
    "--accept-dns=false"
  ];

  # k3s — host-specific identity
  services.k3s.nodeName = "hp348";
  services.k3s.nodeIP = "100.91.37.112";

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
}
