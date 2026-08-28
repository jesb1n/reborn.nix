# hosts/nuc7i3/configuration.nix — Intel NUC server
#
# Normal k3s worker using its stable Tailscale address.
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
    ../../profiles/smartd.nix
    ./disko-config.nix
    ./sops.nix
  ];

  networking = {
    hostName = "nuc7i3";
    wireless.enable = lib.mkForce false;
    networkmanager.unmanaged = [ "type:wifi" ];
  };

  # UEFI bare metal uses systemd-boot instead of the OCI GRUB default.
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot = {
    enable = lib.mkForce true;
    configurationLimit = 3;
  };
  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
  boot.kernelParams = lib.mkForce [ "console=tty1" ];
  boot.blacklistedKernelModules = [
    "btintel"
    "btusb"
    "iwlmvm"
    "iwlwifi"
  ];
  boot.initrd.availableKernelModules = [
    "ahci"
    "ehci_pci"
    "sd_mod"
    "uas"
    "usb_storage"
    "usbhid"
    "xhci_pci"
  ];

  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = true;
    bluetooth.enable = false;
  };

  services = {
    fstrim.enable = true;
    tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
      "--hostname=nuc7i3"
      "--accept-dns=false"
    ];
    k3s = {
      nodeName = "nuc7i3";
      nodeIP = "100.119.33.56";
    };
  };

  # This unattended server must never enter a firmware sleep state.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
}
