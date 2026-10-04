{ lib, ... }:

let
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
  hostSecretsFile = ../../secrets/oracle-in-arm1/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
in
{
  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = false;
    age.sshKeyPaths = [ ];

    defaultSopsFormat = "yaml";

    secrets = lib.mkMerge [
      (lib.mkIf hasTailscaleSecretsFile {
        "tailscale-auth-key" = {
          sopsFile = tailscaleSecretsFile;
        };
      })

      (lib.mkIf hasClusterSecretsFile {
        "k3s-token" = {
          sopsFile = clusterSecretsFile;
        };
      })

      # NAR signing key for the self-hosted binary cache (profiles/binary-cache.nix).
      # Private half — only the public key is committed to lib/binary-caches.nix.
      (lib.mkIf hasHostSecretsFile {
        "nix-cache-signing-key" = {
          sopsFile = hostSecretsFile;
          mode = "0400";
        };
      })
    ];
  };
}
