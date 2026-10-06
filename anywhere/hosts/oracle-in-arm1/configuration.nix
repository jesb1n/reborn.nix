{ lib, modulesPath, ... }:

let
  binaryCaches = import ../../lib/binary-caches.nix;
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
  hostSecretsFile = ../../secrets/oracle-in-arm1/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../profiles/tailscale.nix
    ../../profiles/k3s-agent.nix
    ../../profiles/binary-cache.nix
    ./disko-config.nix
    ./sops.nix
  ];

  networking.hostName = "oracle-in-arm1";

  # Native aarch64 build host + binary cache for the ARM nodes (rpi, eu-arm1).
  # Stays off until secrets/oracle-in-arm1/secrets.yaml carries the signing key.
  fleet.binaryCache.enable = hasHostSecretsFile;
  # Must match this host's nodeIP / Tailscale address so tailnet peers can
  # reach the cache; see profiles/binary-cache.nix.
  fleet.binaryCache.bindAddress = "100.117.227.112";

  # Consume the *other* ARM cache so build output is shared both ways.
  nix.settings = {
    substituters = lib.mkAfter binaryCaches.armNixSettings.substituters;
    trusted-public-keys = lib.mkAfter binaryCaches.armNixSettings.trusted-public-keys;
  };

  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=oracle-in-arm1"
  ];

  services.k3s.nodeName = "oracle-in-arm1";
  services.k3s.nodeIP = "100.117.227.112";

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  system.stateVersion = "26.05";
}
