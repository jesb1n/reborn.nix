{ config, lib, ... }:

let
  hostSecretsFile = ../../secrets/rpi/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
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

      (lib.mkIf hasHostSecretsFile {
        "wifi-ssid" = {
          sopsFile = hostSecretsFile;
        };

        "wifi-psk" = {
          sopsFile = hostSecretsFile;
        };
      })
    ];

    templates = lib.mkIf hasHostSecretsFile {
      "rpi-network.env".content = ''
        WIFI_SSID=${config.sops.placeholder."wifi-ssid"}
        WIFI_PSK=${config.sops.placeholder."wifi-psk"}
      '';
    };
  };
}
