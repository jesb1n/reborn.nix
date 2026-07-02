# profiles/k3s-agent.nix — generic k3s worker (agent) role.
#
# All current agents join the s145-rooted cluster (s145 is the only
# control-plane). Host-specific identity (nodeName, nodeIP) is set in the
# host's configuration.nix.
#
# Tiny (1 GB) nodes should import profiles/k3s-agent-tiny.nix instead,
# which layers max-pods=10 and zramSwap on top of this profile.
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
    serverAddr = "https://100.69.231.117:6443"; # s145 (Tailscale IP)
    tokenFile = config.sops.secrets."k3s-token".path;
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
