# profiles/tailscale.nix — Tailscale mesh VPN with SOPS integration
#
# Enables Tailscale and conditionally configures auth key from SOPS.
# Host-specific extraUpFlags (--hostname, --advertise-exit-node) are
# set in hosts/<name>/configuration.nix via lib.mkForce or mkAfter.
{ config, lib, ... }:

let
  tailscaleSecretsFile = ../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
in
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
  } // lib.optionalAttrs hasTailscaleSecretsFile {
    authKeyFile = config.sops.secrets."tailscale-auth-key".path;
  };
}
