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
    ../../profiles/k3s-agent.nix
    ./disko-config.nix
    ./sops.nix
  ];

  networking.hostName = "oracle-in-arm1";

  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=oracle-in-arm1"
  ];

  services.k3s.nodeName = "oracle-in-arm1";
  services.k3s.nodeIP = "100.117.227.112";

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  system.stateVersion = "26.05";
}
