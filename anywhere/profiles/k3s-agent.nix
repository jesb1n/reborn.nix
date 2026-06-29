# profiles/k3s-agent.nix — k3s worker (agent) role for tiny nodes
#
# Configures k3s as an agent with the "tiny" taint and max-pods=10.
# Host-specific settings (nodeName, nodeIP, serverAddr) are set in
# the host's configuration.nix.
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
    role = "agent";
    serverAddr = "https://100.84.230.4:6443";
    tokenFile = config.sops.secrets."k3s-token".path;
    extraFlags = [
      "--flannel-iface=tailscale0"
      "--kubelet-arg=max-pods=10"
    ];
  };

  # Ensure k3s starts after Tailscale is up
  systemd.services.k3s = lib.mkIf hasClusterSecretsFile {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  # ZRAM — essential for 1GB RAM nodes
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
