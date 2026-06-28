{ lib, ... }:

let
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
  tailscaleSecretsFile = ../../secrets/tailscale/secrets.yaml;
  hasTailscaleSecretsFile = builtins.pathExists tailscaleSecretsFile;
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
    ];
  };
}
