{ lib, ... }:

let
  hostSecretsFile = ../../secrets/oracle-eu-micro2/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
  clusterSecretsFile = ../../secrets/k3s/secrets.yaml;
  hasClusterSecretsFile = builtins.pathExists clusterSecretsFile;
in
{
  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = false;
    age.sshKeyPaths = [ ];

    defaultSopsFormat = "yaml";

    secrets = lib.mkMerge [
      (lib.mkIf hasHostSecretsFile {
        "tailscale-auth-key" = {
          sopsFile = hostSecretsFile;
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
