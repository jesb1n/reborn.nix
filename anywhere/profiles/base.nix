# profiles/base.nix — applied to every OCI host
#
# Provides the absolute baseline: nix daemon settings, garbage collection,
# minimal system footprint, and the shared user account.
{ ... }:
{
  # Nix settings
  nix.settings = {
    trusted-users = [
      "root"
      "duck"
    ];
    # Nix 2.34+ ignores flake nixConfig substituters unless this is set
    # (otherwise builds fall back to compiling from source).
    accept-flake-config = true;
    extra-experimental-features = [
      "nix-command"
      "flakes"
    ];
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

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

  # Minimal system — no docs, no default packages
  documentation.enable = false;
  programs.command-not-found.enable = false;
  environment.defaultPackages = [ ];
  environment.systemPackages = [ ];

  # Shared user account
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

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMDHy9Gc18Osi7HFBiUMm+Da9JQ95cU1a7dsmyJCY5s1 jesbin@Duck.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEDGmT5meeiDIK9c/W8imy++S7hb9TLBcHcPsWcml4D2 duck@Ducks-MacBook-Air.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHXD9NvwXKTrqrH2kZmuDkU4CeUEpf3e7JmWGze7E1HP jesbin@Jesbins-MacBook-Pro.local"
    ];
  };

  security.sudo.wheelNeedsPassword = false;
}
