{ lib, pkgs, ... }:

let
  binaryCaches = import ../../lib/binary-caches.nix;
in
{
  networking.hostName = "travelmate";
  nixpkgs.hostPlatform = "x86_64-linux";
  nix.settings = binaryCaches.nixSettings // {
    trusted-users = [ "root" "duck" ];
  };
  nix.buildMachines = lib.mkForce [ ];
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "brave"
      "google-chrome"
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "ahci"
    "ehci_pci"
    "sd_mod"
    "sdhci_pci"
    "sr_mod"
    "usb_storage"
    "xhci_pci"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.cpu.intel.updateMicrocode = true;

  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;

  networking.networkmanager.enable = true;
  networking.modemmanager.enable = false;
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  services.blueman.enable = true;

  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = [
    pkgs.kdePackages.discover
  ];
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.hiddenUsers = [ "duck" ];

  environment.etc = {
    "xdg/kdeglobals".text = ''
      [General]
      ColorScheme=BreezeDark

      [Icons]
      Theme=breeze-dark
    '';
    "xdg/plasmarc".text = ''
      [Theme]
      name=breeze-dark
    '';
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.fstrim.enable = true;

  systemd.services.travelmate-balanced-power = {
    description = "Set the default laptop power profile to balanced";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced
    '';
  };

  boot.kernel.sysctl."vm.swappiness" = 100;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  environment.systemPackages = with pkgs; [
    brave
    chromium
    google-chrome
    kdePackages.ark
    kdePackages.dolphin
    kdePackages.kate
    kdePackages.okular
    kdePackages.spectacle
    libreoffice-fresh
  ];

  users.users.acer = {
    isNormalUser = true;
    description = "acer";
    hashedPassword = "$6$travelmateacer$ouG3wd/5CBhXZ76istomg8mNcShtIsvGKLfl9GanNX23SjCijVePNKutsDEbIPY5vYQek8iv96xL7Hx/ZkOmm1";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDGmT5meeiDIK9c/W8imy++S7hb9TLBcHcPsWcml4D2 duck@Ducks-MacBook-Air.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXD9NvwXKTrqrH2kZmuDkU4CeUEpf3e7JmWGze7E1HP jesbin@Jesbins-MacBook-Pro.local"
    ];
  };

  users.mutableUsers = false;
  users.users.root.hashedPassword = "!";
  users.users.duck = {
    isNormalUser = true;
    description = "Deployment administrator";
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDGmT5meeiDIK9c/W8imy++S7hb9TLBcHcPsWcml4D2 duck@Ducks-MacBook-Air.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXD9NvwXKTrqrH2kZmuDkU4CeUEpf3e7JmWGze7E1HP jesbin@Jesbins-MacBook-Pro.local"
    ];
  };

  security.sudo = {
    wheelNeedsPassword = true;
    extraRules = [
      {
        users = [ "duck" ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  time.timeZone = "Asia/Kolkata";
  system.stateVersion = "26.05";
}
