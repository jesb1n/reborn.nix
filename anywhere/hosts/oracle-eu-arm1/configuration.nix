# hosts/oracle-eu-arm1/configuration.nix — k3s agent (ARM A1.Flex)
#
# Disposable worker capacity — cluster control-plane lives on s145.
# Host-specific settings only. Shared config comes from profiles.
{ config, lib, ... }:

let
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
    ../../profiles/hermes-agent.nix
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

  # Hermes Agent — feed the SOPS-rendered .env into the gateway. The template
  # only exists once host secrets are encrypted (see secrets/oracle-eu-arm1/),
  # so this is gated on the same file the sops module checks.
  services.hermes-agent.environmentFiles = lib.mkIf hasHostSecretsFile [
    config.sops.templates."hermes-agent.env".path
  ];

  system.stateVersion = "26.05";
}

