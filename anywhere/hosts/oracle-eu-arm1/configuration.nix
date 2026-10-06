# hosts/oracle-eu-arm1/configuration.nix — k3s agent (ARM A1.Flex)
#
# Disposable worker capacity — cluster control-plane lives on s145.
# Host-specific settings only. Shared config comes from profiles.
{ config, lib, ... }:

let
  binaryCaches = import ../../lib/binary-caches.nix;
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
  hostSecretsFile = ../../secrets/oracle-eu-arm1/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
in
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../profiles/tailscale.nix
    ../../profiles/k3s-agent.nix
    ../../profiles/binary-cache.nix
    ./hardware-configuration.nix
    ./sops.nix
  ];

  networking.hostName = "oracle-eu-arm1";

  # Native aarch64 build host + binary cache for the ARM nodes (rpi, in-arm1).
  # Gated on host secrets because the NAR signing key is sops-managed.
  fleet.binaryCache.enable = hasHostSecretsFile;
  # Must match this host's nodeIP / Tailscale address so tailnet peers can
  # reach the cache; see profiles/binary-cache.nix.
  fleet.binaryCache.bindAddress = "100.84.230.4";

  # Consume the *other* ARM cache so the two nodes share build output both
  # ways; a path built here is served to in-arm1 and vice versa.
  nix.settings = {
    substituters = lib.mkAfter binaryCaches.armNixSettings.substituters;
    trusted-public-keys = lib.mkAfter binaryCaches.armNixSettings.trusted-public-keys;
  };

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

