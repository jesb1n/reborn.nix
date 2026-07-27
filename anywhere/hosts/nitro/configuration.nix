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

  networking.hostName = "nitro";

  # Boot — systemd-boot (override GRUB from server.nix)
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce true;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;

  # Remove serial console from server.nix — not useful on a laptop
  boot.kernelParams = lib.mkForce [ ];

  # NVMe — force load in initrd so root partition is found
  boot.initrd.kernelModules = [ "nvme" ];
  boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "usb_storage" "sd_mod" "sr_mod" ];

  # WiFi firmware (covers common laptop adapters)
  hardware.enableRedistributableFirmware = true;

  # Tailscale — host identity
  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=nitro"
    "--accept-dns=false"
  ];

  # k3s — host-specific identity
  services.k3s.nodeName = "nitro";
  # services.k3s.nodeIP = "<tailscale-ip>";  # fill after first Tailscale join

  # Laptop running as a server — keep it awake.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  # NVIDIA GTX 1650 — compute mode for k8s workloads
  hardware.nvidia.modesetting.enable = true;
  hardware.graphics.enable = true;

  # zram (16GB RAM → 8GB zram)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
}
