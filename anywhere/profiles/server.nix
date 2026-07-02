# profiles/server.nix — defaults for headless OCI cloud instances
#
# SSH with hardened settings, serial console for OCI, GRUB bootloader,
# and timezone. Host-specific overrides (hostname, etc.) live in
# hosts/<name>/configuration.nix.
{ ... }:
{
  # Boot — GRUB for OCI instances (no systemd-boot)
  boot.loader.systemd-boot.enable = false;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    efiInstallAsRemovable = true;
    configurationLimit = 3;
  };

  boot.loader.efi.canTouchEfiVariables = false;

  # Serial console for OCI console connection
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty1"
  ];

  # Networking defaults
  networking.networkmanager.enable = true;
  networking.firewall.trustedInterfaces = [
    "tailscale0"
  ];

  # Timezone
  time.timeZone = "Asia/Kolkata";

  # SSH
  services.openssh.enable = true;
  services.openssh.openFirewall = true;

  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };
}
