# profiles/k3s-server.nix — k3s control-plane (server) role
#
# Provides the base k3s server configuration. Host-specific settings
# (nodeName, nodeIP, tokenFile) are set in the host's configuration.nix.
#
# Depends on: profiles/tailscale.nix (flannel uses tailscale0)
{ config, lib, ... }:

let
  clusterSecretsFile = ../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
in
{
  services.k3s = lib.mkIf hasClusterSecretsFile {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets."k3s-token".path;
    disable = [
      "traefik"
    ];
    extraFlags = [
      "--flannel-iface=tailscale0"
    ];
  };

  # Ensure k3s starts after Tailscale is up
  systemd.services.k3s = lib.mkIf hasClusterSecretsFile {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };
}
