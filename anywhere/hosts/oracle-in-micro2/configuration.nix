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

  networking.hostName = "oracle-in-micro2";

  services.tailscale.extraUpFlags = lib.mkIf hasTailscaleSecretsFile [
    "--hostname=oracle-in-micro2"
    "--accept-dns=false"
  ];

  services.k3s.nodeName = "oracle-in-micro2";
  services.k3s.nodeIP = "0.0.0.0"; # placeholder, update after Tailscale assigns IP

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "26.05";
}
