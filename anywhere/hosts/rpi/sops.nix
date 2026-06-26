{ config, lib, ... }:

let
  hostSecretsFile = ../../secrets/rpi/secrets.yaml;
  hasHostSecretsFile = builtins.pathExists hostSecretsFile;
in
{
  sops = {
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = false;
    age.sshKeyPaths = [ ];

    defaultSopsFormat = "yaml";

    secrets = lib.mkIf hasHostSecretsFile {
      "tailscale-auth-key" = {
        sopsFile = hostSecretsFile;
      };

      "wifi-ssid" = {
        sopsFile = hostSecretsFile;
      };

      "wifi-psk" = {
        sopsFile = hostSecretsFile;
      };
    };

    templates = lib.mkIf hasHostSecretsFile {
      "rpi-network.env".content = ''
        WIFI_SSID=${config.sops.placeholder."wifi-ssid"}
        WIFI_PSK=${config.sops.placeholder."wifi-psk"}
      '';
    };
  };
}
