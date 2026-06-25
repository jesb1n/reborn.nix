# hosts/oci-nixos/sops.nix — Secret declarations for the OCI NixOS host.
#
# This follows the same pattern as retire.nix:
# - generate a dedicated age key on the host
# - keep the host private key at /var/lib/sops-nix/key.txt
# - commit only encrypted secrets under secrets/oci-nixos/
#
# Generate on the host:
#   sudo mkdir -p /var/lib/sops-nix
#   sudo age-keygen -o /var/lib/sops-nix/key.txt
#   sudo chmod 600 /var/lib/sops-nix/key.txt
#
# Then add the PUBLIC age key to .sops.yaml as &oci_nixos.
{ lib, ... }:

let
  hostSecretsFile = ../../secrets/oci-nixos/secrets.yaml;
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
      # Tailscale pre-auth key for joining the tailnet on activation/boot.
      # Decrypted by sops-nix to /run/secrets/tailscale-auth-key.
        "tailscale-auth-key" = {
          sopsFile = hostSecretsFile;
        };
      })

      (lib.mkIf hasClusterSecretsFile {
        # Shared k3s cluster token used by the server and tiny worker agents.
        "k3s-token" = {
          sopsFile = clusterSecretsFile;
        };
      })
    ];
  };
}
