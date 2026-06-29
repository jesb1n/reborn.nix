{ config, lib, ... }:

let
  hostSecretsFile = ../../secrets/s145/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
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
      "s145-network.env".content = ''
        WIFI_SSID=${config.sops.placeholder."wifi-ssid"}
        WIFI_PSK=${config.sops.placeholder."wifi-psk"}
      '';
    };
  };
}
