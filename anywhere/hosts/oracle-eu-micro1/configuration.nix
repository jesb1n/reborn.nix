# hosts/oracle-eu-micro1/configuration.nix — k3s worker (x86_64 E2.1.Micro)
#
# Host-specific settings only. Shared config comes from profiles.
{ lib, modulesPath, ... }:

let
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../profiles/tailscale.nix
    ../../profiles/k3s-agent-tiny.nix
    ./disko-config.nix
    ./sops.nix
  ];

  networking.hostName = "oracle-eu-micro1";

  # Tailscale — host identity
  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=oracle-eu-micro1"
    "--accept-dns=false"
  ];

  # k3s — host-specific identity
  services.k3s.nodeName = "oracle-eu-micro1";
  services.k3s.nodeIP = "100.96.237.114";

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
}
