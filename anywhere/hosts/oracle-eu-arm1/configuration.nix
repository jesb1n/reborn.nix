# hosts/oracle-eu-arm1/configuration.nix — k3s control-plane (ARM A1.Flex)
#
# Host-specific settings only. Shared config comes from profiles.
{ config, lib, ... }:

let
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
in
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../profiles/tailscale.nix
    ../../profiles/k3s-server.nix
    ./hardware-configuration.nix
    ./sops.nix
  ];

  networking.hostName = "oracle-eu-arm1";

  # Tailscale — exit node + server routing
  services.tailscale.useRoutingFeatures = "server";
  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--advertise-exit-node"
  ];

  # k3s — host-specific identity
  services.k3s.nodeName = "oracle-eu-arm1";
  services.k3s.nodeIP = "100.84.230.4";

  system.stateVersion = "26.05";
}
